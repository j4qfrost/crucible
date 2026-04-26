# PDFAdapter — extract text from a local PDF.
#
# v0 shells out to `pdftotext` (poppler-utils, available everywhere). A
# Pure-Julia fallback via PDFio.jl is a v0.5 task — pdftotext is more robust
# on real-world journal PDFs.

struct PDFAdapter <: InputAdapter
    pdftotext::String
end

PDFAdapter(; pdftotext::String="pdftotext") = PDFAdapter(pdftotext)

function ingest(a::PDFAdapter, path::AbstractString)::PaperRepr
    isfile(path) || error("PDFAdapter: file not found at $(path)")
    text = ""
    try
        text = read(`$(a.pdftotext) -layout $(path) -`, String)
    catch err
        error("PDFAdapter: pdftotext failed ($(err)). Install poppler-utils, or pass a different binary.")
    end
    PaperRepr(
        source_kind = :pdf,
        source_id   = abspath(path),
        body_text   = text,
        metadata    = Dict{String,Any}("byte_size" => filesize(path)),
    )
end
