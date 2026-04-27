using Test
using Crucible
import HTTP
import JSON3

# Heavy-lift v1: HTTP web frontend smoke test.
#
# We test the router handler function directly with HTTP.Request objects.
# This avoids socket binding, port allocation, and async timing — the
# router is pure (request → response) so it's the right level to test.

function _req(method::AbstractString, target::AbstractString,
              body::Union{Nothing,AbstractString}=nothing)
    headers = Pair{String,String}["content-type" => "application/json"]
    HTTP.Request(method, target, headers, body === nothing ? UInt8[] : Vector{UInt8}(body))
end

@testset "WebRenderer emits standalone HTML" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    spec = Crucible.spec_from_json(read(fixture, String))
    html = render(WebRenderer(), spec)
    @test occursin("<html>", html)
    @test occursin("MDSpec", html)
    @test occursin("amber14sb", html)
end

@testset "router serves index HTML" begin
    res = Crucible._router(_req("GET", "/"))
    @test res.status == 200
    body = String(res.body)
    @test occursin("Crucible", body)
    @test occursin("<textarea", body)
end

@testset "router /health returns ok JSON" begin
    res = Crucible._router(_req("GET", "/health"))
    @test res.status == 200
    obj = JSON3.read(String(res.body))
    @test String(obj.status) == "ok"
end

@testset "router /api/validate accepts spec and returns report" begin
    spec_json = read(joinpath(@__DIR__, "fixtures", "known_good_spec.json"), String)
    body = JSON3.write(Dict("spec_json" => spec_json, "backend" => "openmm"))
    res = Crucible._router(_req("POST", "/api/validate", body))
    @test res.status == 200
    obj = JSON3.read(String(res.body))
    @test obj.ok == true
    @test String(obj.backend) == "openmm"
end

@testset "router /api/render returns Python script for openmm" begin
    spec_json = read(joinpath(@__DIR__, "fixtures", "known_good_spec.json"), String)
    body = JSON3.write(Dict("spec_json" => spec_json, "backend" => "openmm"))
    res = Crucible._router(_req("POST", "/api/render", body))
    @test res.status == 200
    obj = JSON3.read(String(res.body))
    @test obj.ok == true
    @test occursin("from openmm", String(obj.script))
end

@testset "router /api/transpile via recorded provider" begin
    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    body = JSON3.write(Dict(
        "paper_text" => "ignored",
        "provider"   => Dict("kind" => "recorded", "fixture" => fixture),
    ))
    res = Crucible._router(_req("POST", "/api/transpile", body))
    @test res.status == 200
    obj = JSON3.read(String(res.body))
    @test obj.ok == true
    @test String(obj.provider) == "recorded"
    @test !isempty(String(obj.spec_json))
end

@testset "router /api/advise responds with cloud recommendation" begin
    spec_json = read(joinpath(@__DIR__, "fixtures", "known_good_spec.json"), String)
    body = JSON3.write(Dict("spec_json" => spec_json, "budget_hours" => 6.0))
    res = Crucible._router(_req("POST", "/api/advise", body))
    @test res.status == 200
    obj = JSON3.read(String(res.body))
    @test obj.ok == true
end

@testset "router /api/lint returns findings + coverage" begin
    spec_json = read(joinpath(@__DIR__, "fixtures", "known_good_spec.json"), String)
    body = JSON3.write(Dict("spec_json" => spec_json))
    res = Crucible._router(_req("POST", "/api/lint", body))
    @test res.status == 200
    obj = JSON3.read(String(res.body))
    @test obj.ok == true
    @test haskey(obj, :findings)
    @test haskey(obj, :coverage)
    @test haskey(obj.coverage, :score)
end

@testset "router /api/coverage returns provenance score" begin
    spec_json = read(joinpath(@__DIR__, "fixtures", "known_good_spec.json"), String)
    body = JSON3.write(Dict("spec_json" => spec_json))
    res = Crucible._router(_req("POST", "/api/coverage", body))
    @test res.status == 200
    obj = JSON3.read(String(res.body))
    @test obj.ok == true
    @test haskey(obj, :score)
    @test haskey(obj, :total_numeric_fields)
end

@testset "router GET /api/templates lists names" begin
    res = Crucible._router(_req("GET", "/api/templates"))
    @test res.status == 200
    obj = JSON3.read(String(res.body))
    @test obj.ok == true
    @test "vanilla" in obj.templates
end

@testset "router GET /api/templates/<name> returns spec_json" begin
    res = Crucible._router(_req("GET", "/api/templates/vanilla"))
    @test res.status == 200
    obj = JSON3.read(String(res.body))
    @test obj.ok == true
    @test obj.name == "vanilla"
    @test occursin("schema_version", String(obj.spec_json))
end

@testset "router GET /api/templates/<bad> returns 404" begin
    res = Crucible._router(_req("GET", "/api/templates/no_such_template"))
    @test res.status == 404
end

@testset "MarkdownRenderer renders LintReport" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    spec = Crucible.spec_from_json(read(fixture, String))
    rep = lint(spec)
    md = render(MarkdownRenderer(), rep)
    @test occursin("## Lint", md)
    @test occursin("Provenance coverage", md)
end

@testset "MarkdownRenderer renders CoverageReport" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    spec = Crucible.spec_from_json(read(fixture, String))
    cov = provenance_coverage(spec)
    md = render(MarkdownRenderer(), cov)
    @test occursin("Quality score", md)
    @test occursin("Coverage", md)
end

@testset "router unknown path returns 404" begin
    res = Crucible._router(_req("GET", "/no/such/path"))
    @test res.status == 404
end

@testset "router /api/validate rejects empty body" begin
    res = Crucible._router(_req("POST", "/api/validate"))
    @test res.status == 400
    obj = JSON3.read(String(res.body))
    @test obj.ok == false
end
