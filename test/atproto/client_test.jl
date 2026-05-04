using Test
using Crucible
using Crucible.ATProto
import JSON3

# Stub HTTP transport. Records each call so we can inspect after.

mutable struct StubTransport
    queue::Vector{Any}    # responses to hand back, in order
    calls::Vector{Any}    # records of (kind, url, headers, body) triples
end

StubTransport() = StubTransport(Any[], Any[])

# Mock response object — duck-types HTTP.Response.
mutable struct StubResp
    status::Int
    body::Vector{UInt8}
end
StubResp(status::Int, body::AbstractString) = StubResp(status, Vector{UInt8}(String(body)))

function make_post(t::StubTransport)
    (url, headers, body; kwargs...) -> begin
        push!(t.calls, (:post, url, headers, body))
        isempty(t.queue) && error("stub queue empty for $(url)")
        popfirst!(t.queue)
    end
end

function make_get(t::StubTransport)
    (url, headers; kwargs...) -> begin
        push!(t.calls, (:get, url, headers, nothing))
        isempty(t.queue) && error("stub queue empty for $(url)")
        popfirst!(t.queue)
    end
end

const SESSION_OK = """{"did":"did:plc:test","handle":"crucible-bot.test","accessJwt":"jwt-a","refreshJwt":"jwt-r"}"""
const CREATE_RECORD_OK = """{"uri":"at://did:plc:test/app.hekate.event/abc","cid":"bafy"}"""

@testset "client: createSession returns session" begin
    t = StubTransport()
    push!(t.queue, StubResp(200, SESSION_OK))
    set_http_transport!(post=make_post(t))
    cfg = HekateConfig(
        "https://test", "crucible-bot.test", "secret",
        true, "at://did:plc:test/app.hekate.venue/v",
        "at://did:plc:test/app.hekate.recurrence/r",
        "/tmp/hekate.toml", String["crucible"],
    )
    s = create_session(cfg)
    @test s.did == "did:plc:test"
    @test s.access_jwt == "jwt-a"
    @test length(t.calls) == 1
    reset_http_transport!()
end

@testset "client: createRecord includes Authorization header" begin
    t = StubTransport()
    push!(t.queue, StubResp(200, SESSION_OK))
    push!(t.queue, StubResp(200, CREATE_RECORD_OK))
    set_http_transport!(post=make_post(t))
    cfg = HekateConfig(
        "https://test", "crucible-bot.test", "secret",
        true, "at://did:plc:test/app.hekate.venue/v",
        "at://did:plc:test/app.hekate.recurrence/r",
        "/tmp/hekate.toml", String["crucible"],
    )
    s = create_session(cfg)
    rec = build_event(slot_uri="at://did:plc:test/app.hekate.slot/x", title="t")
    result = create_record(s, "app.hekate.event", rec)
    @test result.uri == "at://did:plc:test/app.hekate.event/abc"
    # The second call must include Authorization: Bearer jwt-a
    second_call = t.calls[2]
    headers = second_call[3]
    auth_pair = first(filter(p -> p.first == "authorization", headers))
    @test occursin("Bearer jwt-a", auth_pair.second)
    reset_http_transport!()
end

@testset "client: ATProtoError parses AT Proto error body" begin
    t = StubTransport()
    push!(t.queue, StubResp(401, """{"error":"AuthMissing","message":"bad token"}"""))
    set_http_transport!(post=make_post(t))
    cfg = HekateConfig(
        "https://test", "crucible-bot.test", "secret",
        true, nothing, nothing,
        "/tmp/hekate.toml", String[],
    )
    err = try
        create_session(cfg)
        nothing
    catch e
        e
    end
    @test err isa ATProtoError
    @test err.status == 401
    @test err.error_code == "AuthMissing"
    @test err.message == "bad token"
    # showerror produces something readable
    io = IOBuffer()
    showerror(io, err)
    s = String(take!(io))
    @test occursin("AuthMissing", s)
    @test occursin("bad token", s)
    reset_http_transport!()
end

@testset "client: createRecord 401 retries once" begin
    t = StubTransport()
    push!(t.queue, StubResp(401, """{"error":"AuthMissing"}"""))  # first createRecord
    push!(t.queue, StubResp(200, SESSION_OK))                      # re-createSession
    push!(t.queue, StubResp(200, CREATE_RECORD_OK))                # createRecord retry
    set_http_transport!(post=make_post(t))

    cfg = HekateConfig(
        "https://test", "crucible-bot.test", "secret",
        true, "at://did:plc:test/app.hekate.venue/v",
        "at://did:plc:test/app.hekate.recurrence/r",
        "/tmp/hekate.toml", String["crucible"],
    )
    # Pre-seed a session so the wrapper hits createRecord first (which 401s)
    initial = Session("https://test", "did:plc:test", "crucible-bot.test",
                      "stale-jwt", "stale-refresh", Crucible.ATProto.Dates.now(Crucible.ATProto.Dates.UTC))
    sref = Ref{Union{Nothing,Session}}(initial)
    rec = build_event(slot_uri="at://did:plc:test/app.hekate.slot/x", title="t")
    result = create_record(cfg, sref, "app.hekate.event", rec)
    @test result.uri == "at://did:plc:test/app.hekate.event/abc"
    @test length(t.calls) == 3
    reset_http_transport!()
end
