# Input adapters normalize a paper source (PDF, arXiv ID, bioRxiv DOI, raw
# notes) into a common PaperRepr that the LLM provider consumes.

abstract type InputAdapter end

struct PaperRepr
    source_kind::Symbol               # :pdf | :arxiv | :biorxiv | :notes
    source_id::String                 # path / arXiv ID / DOI / "<inline>"
    title::Union{Nothing,String}
    abstract_text::Union{Nothing,String}
    body_text::String                 # the full extracted text the LLM will read
    metadata::Dict{String,Any}
end

PaperRepr(; source_kind, source_id, title=nothing, abstract_text=nothing,
            body_text, metadata=Dict{String,Any}()) =
    PaperRepr(source_kind, source_id, title, abstract_text, body_text, metadata)

"""
    ingest(adapter, source) -> PaperRepr

Each adapter knows how to interpret `source` (a path, an ID, etc.).
"""
function ingest(a::InputAdapter, source)::PaperRepr
    error("ingest not implemented for $(typeof(a))")
end
