# RecordedProvider — replays a fixture MDSpec JSON instead of calling an API.
#
# Used by the deterministic LLM testset so we can exercise the full
# provider→spec→validate→render pipeline without consuming Anthropic tokens
# (or requiring an API key in CI). The fixture is the same shape an
# AnthropicProvider would emit.

struct RecordedProvider <: LLMProvider
    fixture_path::String
end

provider_name(::RecordedProvider) = :recorded

function transpile(p::RecordedProvider, paper_text::AbstractString; kwargs...)::TranspileResult
    isfile(p.fixture_path) ||
        return TranspileResult("", nothing,
            "RecordedProvider: fixture not found at $(p.fixture_path)",
            :recorded, "fixture", 0.0)
    spec_json = read(p.fixture_path, String)
    spec = nothing
    raw = "loaded fixture $(p.fixture_path)"
    try
        spec = spec_from_json(spec_json)
    catch err
        raw *= "\nfixture parse error: $(err)"
    end
    TranspileResult(spec_json, spec, raw, :recorded, "fixture", 0.0)
end
