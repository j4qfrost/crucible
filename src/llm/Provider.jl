# Abstract LLM provider — defines the contract that AnthropicProvider satisfies
# in v0 and that LocalProvider/FineTunedProvider implement on the option-3
# roadmap.

abstract type LLMProvider end

struct TranspileResult
    spec_json::String                 # raw JSON the provider emitted
    spec::Union{Nothing,MDSpec}       # parsed MDSpec, or nothing if parsing failed
    raw_response::String              # full provider response for audit
    provider_name::Symbol
    model::String
    cost_estimate_usd::Float64        # provider-specific token-cost estimate
end

"""
    transpile(provider, paper_text; options...) -> TranspileResult

Provider contract: take normalized paper text, return an MDSpec (as JSON) +
the parsed Julia struct + the raw response. Providers should never throw on
LLM-side issues — they should record errors in `raw_response` and return a
`TranspileResult` with `spec=nothing`.
"""
function transpile(p::LLMProvider, paper_text::AbstractString; kwargs...)::TranspileResult
    error("transpile not implemented for $(typeof(p))")
end

provider_name(p::LLMProvider) = error("provider_name not implemented for $(typeof(p))")

# Common system prompt fragment shared by all providers.
const TRANSPILE_SYSTEM_PROMPT = """
You are Crucible's molecular-dynamics paper transpiler. You read a chemistry or drug-discovery paper (or its Methods section) and emit a single JSON object that conforms exactly to the MDSpec v0.1.0 schema.

CONTRACT, NON-NEGOTIABLE:
1. Output ONLY a JSON object that validates against the MDSpec schema. No prose, no markdown, no code fences.
2. Never invent force-field parameters. If the paper does not state a force field, use the closest match from the allowlist and add a warning + provenance entry with source="assumed".
3. Every numeric field that came from the paper MUST have a provenance entry citing the section/figure/table. Fields you defaulted MUST have provenance with source="paper_default" (paper implied it but did not state it explicitly) or "assumed" (you guessed).
4. Use the protein/water/ligand FF allowlists exactly as written. If a paper says "Amber99", map it to "amber99sb_ildn" and add a warning explaining the mapping.
5. NEVER convert units. Emit values in the units named by the field (temperature_K, dt_fs, duration_ns, etc.). The downstream renderer is the only thing that converts.
6. If the paper describes a system you cannot represent in v0 (membranes, free-energy, REMD, plumed), emit an MDSpec for the closest reduced sub-protocol (typically: minimize → NVT → NPT → production) and add a warning describing what you dropped.
7. has_ligand=true requires the user to supply a topology — if you set has_ligand=true and the paper does not provide a topology path, emit system.source.topology=null and add a warning that the user must provide one before the spec can run.
"""
