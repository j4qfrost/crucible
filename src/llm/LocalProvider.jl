# LocalProvider — stub for the option-3 roadmap.
#
# Phase A (current): does nothing useful, exists to lock the interface so the
# rest of the codebase can pretend the local path is wired even when it isn't.
#
# Phase D (target): swap in a fine-tuned chem model served via vLLM or
# llama.cpp, accessed over a local OpenAI-compatible HTTP endpoint. The
# transpile() implementation will mirror AnthropicProvider's tool-use shape
# so the Router/Validator above the provider don't need to change.

struct LocalProvider <: LLMProvider
    endpoint::String                  # e.g. "http://localhost:8000/v1"
    model::String
    available::Bool
end

LocalProvider(; endpoint="http://localhost:8000/v1", model="crucible-chem-7b") =
    LocalProvider(endpoint, model, false)

provider_name(::LocalProvider) = :local

function transpile(p::LocalProvider, ::AbstractString; kwargs...)::TranspileResult
    TranspileResult("", nothing,
        "LocalProvider is a stub (option-3 roadmap). " *
        "Phase D will plug in a fine-tuned chem model at $(p.endpoint).",
        :local, p.model, 0.0)
end
