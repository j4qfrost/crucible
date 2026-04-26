# BioRxivAdapter — resolve a bioRxiv DOI to metadata + abstract.
#
# Uses the bioRxiv API directly (https://api.biorxiv.org/). Crucible can also
# be driven from a Pluto session that has the bioRxiv MCP server available;
# in that case prefer the MCP tool calls over this HTTP client (the MCP path
# already handles caching and rate-limiting). This adapter is the standalone
# fallback.

struct BioRxivAdapter <: InputAdapter
    api_url::String                   # https://api.biorxiv.org/details/biorxiv/{doi}
    timeout_s::Int
end

BioRxivAdapter(; api_url="https://api.biorxiv.org/details/biorxiv", timeout_s=30) =
    BioRxivAdapter(api_url, timeout_s)

function ingest(a::BioRxivAdapter, doi::AbstractString)::PaperRepr
    d = strip(String(doi))
    url = string(a.api_url, "/", d)
    title = nothing
    abs_text = nothing
    body_text = ""
    try
        resp = HTTP.get(url; readtimeout=a.timeout_s)
        parsed = JSON3.read(String(resp.body))
        if !isempty(parsed.collection)
            entry = parsed.collection[1]
            title = String(get(entry, :title, ""))
            abs_text = String(get(entry, :abstract, ""))
            body_text = abs_text
        end
    catch err
        @warn "BioRxivAdapter: API fetch failed" error=err
    end
    PaperRepr(
        source_kind   = :biorxiv,
        source_id     = d,
        title         = title,
        abstract_text = abs_text,
        body_text     = body_text,
        metadata      = Dict{String,Any}(
            "note" => "Prefer the bioRxiv MCP server when running inside an MCP-capable session.",
        ),
    )
end
