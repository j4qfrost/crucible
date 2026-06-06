# LocalProvider — OpenAI-compatible /v1/chat/completions client.
#
# Hits any endpoint that speaks the OpenAI Chat Completions API with a
# `response_format={"type": "json_schema", "json_schema": {...}}` (vLLM,
# Ollama in OpenAI mode, llama.cpp server, OpenRouter, LM Studio). Same
# structured-output contract as AnthropicProvider.
#
# Configure via constructor or env:
#   LocalProvider(; endpoint="http://localhost:8000/v1", model="qwen3:14b")
#   ENV: CRUCIBLE_LOCAL_ENDPOINT, CRUCIBLE_LOCAL_MODEL, CRUCIBLE_LOCAL_API_KEY
#
# When the endpoint is unreachable or returns malformed JSON, returns a
# TranspileResult with spec=nothing and the error in raw_response — never
# throws (matches AnthropicProvider's fail-soft contract).

struct LocalProvider <: LLMProvider
    endpoint::String                  # e.g. "http://localhost:8000/v1"
    model::String
    api_key::String                   # vLLM/llama.cpp default to "EMPTY"
    timeout_s::Int
end

LocalProvider(;
    endpoint::AbstractString = get(ENV, "CRUCIBLE_LOCAL_ENDPOINT", "http://localhost:8000/v1"),
    model::AbstractString    = get(ENV, "CRUCIBLE_LOCAL_MODEL", "qwen3:14b"),
    api_key::AbstractString  = get(ENV, "CRUCIBLE_LOCAL_API_KEY", "EMPTY"),
    timeout_s::Int           = 120,
) = LocalProvider(String(endpoint), String(model), String(api_key), timeout_s)

provider_name(::LocalProvider) = :local

function transpile(p::LocalProvider, paper_text::AbstractString;
                   schema_path::AbstractString = joinpath(@__DIR__, "..", "spec", "schema.json"),
                  )::TranspileResult
    schema = JSON3.read(read(schema_path, String), Dict)

    body = Dict(
        "model" => p.model,
        "messages" => [
            Dict("role" => "system", "content" => TRANSPILE_SYSTEM_PROMPT),
            Dict("role" => "user",   "content" => "Paper text:\n\n" * String(paper_text)),
        ],
        "response_format" => Dict(
            "type" => "json_schema",
            "json_schema" => Dict(
                "name"   => "mdspec",
                "schema" => schema,
                "strict" => true,
            ),
        ),
        "temperature" => 0.0,
        "max_tokens"  => 8192,
    )

    url = rstrip(p.endpoint, '/') * "/chat/completions"
    response_str = ""
    try
        resp = HTTP.post(
            url,
            [
                "Authorization" => "Bearer " * p.api_key,
                "content-type"  => "application/json",
            ],
            JSON3.write(body);
            readtimeout = p.timeout_s,
        )
        response_str = String(resp.body)
    catch err
        return TranspileResult("", nothing,
            "local provider request to $(url) failed: $(err)",
            :local, p.model, 0.0)
    end

    spec_json = ""
    spec = nothing
    try
        parsed = JSON3.read(response_str)
        choices = get(parsed, :choices, nothing)
        if choices === nothing || isempty(choices)
            return TranspileResult("", nothing,
                "local provider response had no choices: $(response_str)",
                :local, p.model, 0.0)
        end
        msg = choices[1].message
        spec_json = String(get(msg, :content, ""))
        spec = spec_from_json(spec_json)
        return TranspileResult(spec_json, spec, response_str,
            :local, p.model, 0.0)
    catch err
        return TranspileResult(spec_json, nothing,
            "failed to parse local provider response into MDSpec: $(err)\nraw: $(response_str)",
            :local, p.model, 0.0)
    end
end
