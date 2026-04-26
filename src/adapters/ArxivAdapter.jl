# ArxivAdapter — fetch metadata + PDF text for an arXiv ID.
#
# Uses the arXiv export API for metadata. When `download_pdf=true` (default
# when `pdftotext` is on PATH) and the network is reachable, the adapter
# downloads the PDF and runs pdftotext to populate body_text. Falls back
# gracefully to abstract-only when either is unavailable.

struct ArxivAdapter <: InputAdapter
    api_url::String
    timeout_s::Int
    download_pdf::Bool
    pdftotext::String
end

ArxivAdapter(; api_url="https://export.arxiv.org/api/query",
              timeout_s=30,
              download_pdf=Sys.which("pdftotext") !== nothing,
              pdftotext="pdftotext") =
    ArxivAdapter(api_url, timeout_s, download_pdf, pdftotext)

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
    metadata = Dict{String,Any}("pdf_url" => pdf_url)

    if a.download_pdf
        try
            pdf_resp = HTTP.get(pdf_url; readtimeout=a.timeout_s)
            tmp_path, tmp_io = mktemp(; cleanup=false)
            try
                write(tmp_io, pdf_resp.body)
                close(tmp_io)
                full_text = read(`$(a.pdftotext) -layout $(tmp_path) -`, String)
                if !isempty(full_text)
                    body_text = full_text
                    metadata["pdf_bytes"] = length(pdf_resp.body)
                end
            finally
                rm(tmp_path; force=true)
            end
        catch err
            @warn "ArxivAdapter: PDF download/extract failed; falling back to abstract" error=err
            metadata["pdf_download_error"] = string(err)
        end
    end

    PaperRepr(
        source_kind   = :arxiv,
        source_id     = id,
        title         = title,
        abstract_text = abs_text,
        body_text     = body_text,
        metadata      = metadata,
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
