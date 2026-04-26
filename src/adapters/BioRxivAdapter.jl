# BioRxivAdapter — resolve a bioRxiv DOI to metadata + abstract + (optional)
# full-text PDF.
#
# Uses the bioRxiv API directly (https://api.biorxiv.org/) for metadata and
# https://www.biorxiv.org/content/<doi>.full.pdf for the body. When pdftotext
# is on PATH, `download_pdf` defaults to true. Crucible can also be driven
# from a Pluto session with the bioRxiv MCP server attached — in that case
# prefer the MCP tool calls (already cached + rate-limited).

struct BioRxivAdapter <: InputAdapter
    api_url::String
    pdf_url_template::String
    timeout_s::Int
    download_pdf::Bool
    pdftotext::String
end

BioRxivAdapter(; api_url="https://api.biorxiv.org/details/biorxiv",
               pdf_url_template="https://www.biorxiv.org/content/{doi}.full.pdf",
               timeout_s=30,
               download_pdf=Sys.which("pdftotext") !== nothing,
               pdftotext="pdftotext") =
    BioRxivAdapter(api_url, pdf_url_template, timeout_s, download_pdf, pdftotext)

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

    metadata = Dict{String,Any}(
        "note" => "Prefer the bioRxiv MCP server when running inside an MCP-capable session.",
    )

    if a.download_pdf
        pdf_url = replace(a.pdf_url_template, "{doi}" => d)
        metadata["pdf_url"] = pdf_url
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
            @warn "BioRxivAdapter: PDF download/extract failed; falling back to abstract" error=err
            metadata["pdf_download_error"] = string(err)
        end
    end

    PaperRepr(
        source_kind   = :biorxiv,
        source_id     = d,
        title         = title,
        abstract_text = abs_text,
        body_text     = body_text,
        metadata      = metadata,
    )
end
