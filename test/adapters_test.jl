using Test
using Crucible

@testset "PDFAdapter (skipped without pdftotext)" begin
    if Sys.which("pdftotext") === nothing
        @info "pdftotext not on PATH; skipping PDFAdapter tests"
        @test true
        return
    end
    fixture = joinpath(@__DIR__, "fixtures", "sample_methods.pdf")
    @test isfile(fixture)
    paper = ingest(PDFAdapter(), fixture)
    @test paper.source_kind == :pdf
    @test paper.source_id == abspath(fixture)
    # The fixture's text should round-trip through pdftotext
    @test occursin("AMBER ff14SB", paper.body_text)
    @test occursin("TIP3P", paper.body_text)
    @test occursin("100 ns", paper.body_text)
    @test paper.metadata["byte_size"] > 100
end

@testset "NotesAdapter pass-through" begin
    s = "free-form methods text"
    p = ingest(NotesAdapter(), s)
    @test p.source_kind == :notes
    @test p.body_text == s
    @test p.source_id == "<inline>"
end

@testset "BioRxivAdapter request shape (offline-tolerant)" begin
    a = BioRxivAdapter(api_url="http://localhost:1/should-fail",
                       pdf_url_template="http://localhost:1/should-fail/{doi}",
                       timeout_s=1, download_pdf=false)
    p = ingest(a, "10.1101/2024.01.01.123456")
    @test p.source_kind == :biorxiv
    @test p.source_id == "10.1101/2024.01.01.123456"
    @test occursin("MCP server", p.metadata["note"])
end

@testset "ArxivAdapter request shape (offline-tolerant)" begin
    # We don't hit the network in CI; just verify the adapter constructs
    # cleanly and ingest handles a network failure without throwing.
    # Force download_pdf=false so the adapter doesn't try to fetch when
    # poppler is available locally.
    a = ArxivAdapter(api_url="http://localhost:1/should-fail",
                     timeout_s=1, download_pdf=false)
    p = ingest(a, "1234.56789")
    @test p.source_kind == :arxiv
    @test p.source_id == "1234.56789"
    @test occursin("arxiv.org/pdf/1234.56789.pdf", p.metadata["pdf_url"])
end
