# Anthropic Claude provider.
#
# Uses the Anthropic Messages API with tool-use to constrain output to a
# JSON object conforming to the MDSpec schema. The tool's input_schema is the
# MDSpec JSON Schema itself, which gives us "free" structured output.
#
# Read ANTHROPIC_API_KEY from the environment. If unset, transpile() returns
# a TranspileResult with spec=nothing and an explanatory raw_response — never
# throws — so the rest of the pipeline (and the Pluto UI) keeps working.

using HTTP

struct AnthropicProvider <: LLMProvider
    model::String
    api_url::String
    api_version::String
    max_tokens::Int
    timeout_s::Int
end

AnthropicProvider(;
    model::String="claude-opus-4-7",
    api_url::String="https://api.anthropic.com/v1/messages",
    api_version::String="2023-06-01",
    max_tokens::Int=8192,
    timeout_s::Int=120,
) = AnthropicProvider(model, api_url, api_version, max_tokens, timeout_s)

provider_name(::AnthropicProvider) = :anthropic

function transpile(p::AnthropicProvider, paper_text::AbstractString;
                   schema_path::AbstractString=joinpath(@__DIR__, "..", "spec", "schema.json"),
                  )::TranspileResult
    api_key = get(ENV, "ANTHROPIC_API_KEY", "")
    if isempty(api_key)
        return TranspileResult(
            "", nothing,
            "ANTHROPIC_API_KEY not set; transpile is a no-op. " *
            "Set the env var and re-run, or hand-write an MDSpec for testing.",
            :anthropic, p.model, 0.0,
        )
    end

    schema = JSON3.read(read(schema_path, String), Dict)

    tool_def = Dict(
        "name" => "emit_mdspec",
        "description" => "Emit an MDSpec v0.1.0 JSON object describing the simulation in the supplied paper.",
        "input_schema" => schema,
    )

    body = Dict(
        "model" => p.model,
        "max_tokens" => p.max_tokens,
        "system" => TRANSPILE_SYSTEM_PROMPT,
        "tools" => [tool_def],
        "tool_choice" => Dict("type" => "tool", "name" => "emit_mdspec"),
        "messages" => [
            Dict("role" => "user", "content" => "Paper text:\n\n" * String(paper_text)),
        ],
    )

    response_str = ""
    try
        resp = HTTP.post(
            p.api_url,
            [
                "x-api-key" => api_key,
                "anthropic-version" => p.api_version,
                "content-type" => "application/json",
            ],
            JSON3.write(body);
            readtimeout = p.timeout_s,
        )
        response_str = String(resp.body)
    catch err
        return TranspileResult("", nothing,
            "anthropic request failed: $(err)",
            :anthropic, p.model, 0.0)
    end

    spec_json = ""
    spec = nothing
    try
        parsed = JSON3.read(response_str)
        # Find the tool_use content block
        tool_block = nothing
        for c in parsed.content
            if get(c, :type, "") == "tool_use" && get(c, :name, "") == "emit_mdspec"
                tool_block = c
                break
            end
        end
        if tool_block === nothing
            return TranspileResult("", nothing,
                "anthropic response did not contain a tool_use for emit_mdspec: $(response_str)",
                :anthropic, p.model, _estimate_cost(parsed, p.model))
        end
        spec_json = JSON3.write(tool_block.input)
        spec = spec_from_json(spec_json)
        return TranspileResult(spec_json, spec, response_str,
            :anthropic, p.model, _estimate_cost(parsed, p.model))
    catch err
        return TranspileResult(spec_json, nothing,
            "failed to parse anthropic response into MDSpec: $(err)\nraw: $(response_str)",
            :anthropic, p.model, 0.0)
    end
end

# Crude cost estimate from usage block; conservative pricing baked in here
# just to surface ballpark figures in the Pluto UI. Update from the
# Anthropic pricing page when the env var ANTHROPIC_PRICING_VERSION changes.
function _estimate_cost(parsed, model::AbstractString)
    usage = get(parsed, :usage, nothing)
    usage === nothing && return 0.0
    in_tok  = Float64(get(usage, :input_tokens, 0))
    out_tok = Float64(get(usage, :output_tokens, 0))
    # Rough mid-2025 placeholder rates (USD per 1M tokens). User should treat
    # these as ballpark; real billing comes from the Anthropic console.
    if occursin("opus", model)
        return (in_tok * 15.0 + out_tok * 75.0) / 1_000_000
    elseif occursin("sonnet", model)
        return (in_tok * 3.0 + out_tok * 15.0) / 1_000_000
    elseif occursin("haiku", model)
        return (in_tok * 0.8 + out_tok * 4.0) / 1_000_000
    else
        return 0.0
    end
end
