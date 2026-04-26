# ArxivAdapter — fetch metadata + PDF text for an arXiv ID.
#
# Uses the arXiv export API for metadata and the standard PDF URL for the
# body. We do NOT download the PDF in v0 — we surface the URL and the
# abstract text. The user can pipe the PDF through PDFAdapter if they want
# the full body.

struct ArxivAdapter <: InputAdapter
    api_url::String                   # https://export.arxiv.org/api/query
    timeout_s::Int
end

ArxivAdapter(; api_url="https://export.arxiv.org/api/query", timeout_s=30) =
    ArxivAdapter(api_url, timeout_s)

function ingest(a::ArxivAdapter, arxiv_id::AbstractString)::PaperRepr
    id = strip(String(arxiv_id))
    abs_text = nothing
    title = nothing
    try
        url = string(a.api_url, "?id_list=", id)
        resp = HTTP.get(url; readtimeout=a.timeout_s)
        body = String(resp.body)
        title = _extract_xml_field(body, "title")
        abs_text = _extract_xml_field(body, "summary")
    catch err
        @warn "ArxivAdapter: metadata fetch failed; returning what we have" error=err
    end
    pdf_url = "https://arxiv.org/pdf/$(id).pdf"
    body_text = abs_text === nothing ? "" : abs_text
    PaperRepr(
        source_kind   = :arxiv,
        source_id     = id,
        title         = title,
        abstract_text = abs_text,
        body_text     = body_text,
        metadata      = Dict{String,Any}("pdf_url" => pdf_url),
    )
end

function _extract_xml_field(xml::AbstractString, field::AbstractString)
    # Cheap hand-rolled extractor — the arXiv API returns Atom XML and we
    # only need the first <title> and <summary> after the entry tag.
    pattern = Regex("<entry>.*?<$(field)>(.*?)</$(field)>", "s")
    m = match(pattern, xml)
    m === nothing && return nothing
    String(strip(m.captures[1]))
end
