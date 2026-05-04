using Test
using Crucible
using Crucible.ATProto
using Dates
import JSON3

mutable struct PubStub
    queue::Vector{Any}
    calls::Vector{Any}
end
PubStub() = PubStub(Any[], Any[])

mutable struct PubResp
    status::Int
    body::Vector{UInt8}
end
PubResp(s::Int, b::AbstractString) = PubResp(s, Vector{UInt8}(String(b)))

function _post_stub(p::PubStub)
    (url, headers, body; kwargs...) -> begin
        push!(p.calls, (:post, url, body))
        isempty(p.queue) && error("queue empty for $(url)")
        popfirst!(p.queue)
    end
end
function _get_stub(p::PubStub)
    (url, headers; kwargs...) -> begin
        push!(p.calls, (:get, url, nothing))
        isempty(p.queue) && error("queue empty for $(url)")
        popfirst!(p.queue)
    end
end

const SESS_OK = """{"did":"did:plc:test","handle":"bot","accessJwt":"j","refreshJwt":"r"}"""
function _slot_record(start_dt::DateTime, recurrence_uri::String, status::String="open")
    Dict(
        "uri" => "at://did:plc:test/app.hekate.slot/$(rand(UInt32))",
        "cid" => "bafy",
        "value" => Dict(
            "venue" => "at://did:plc:test/app.hekate.venue/v",
            "recurrence" => recurrence_uri,
            "start" => Dates.format(start_dt, dateformat"yyyy-mm-ddTHH:MM:SS.sssZ"),
            "end" => Dates.format(start_dt + Hour(1), dateformat"yyyy-mm-ddTHH:MM:SS.sssZ"),
            "status" => status,
            "createdAt" => "2026-05-01T00:00:00.000Z",
        ),
    )
end

const CFG_OFF = HekateConfig(
    "https://test", "", "",  # no handle/password → not publish-ready
    false, nothing, nothing,
    "/tmp/hekate.toml", String["crucible"],
)
const CFG_ON = HekateConfig(
    "https://test", "bot", "secret",
    true,
    "at://did:plc:test/app.hekate.venue/v",
    "at://did:plc:test/app.hekate.recurrence/r",
    "/tmp/hekate.toml", String["crucible"],
)

@testset "publisher: dry-run when publish_events=false (no HTTP calls)" begin
    p = PubStub()
    set_http_transport!(post=_post_stub(p), get=_get_stub(p))
    req = ReviewSessionRequest(paper_title="paper", paper_summary="summary",
                               tags=String["test"])
    result = publish_review_session(req; cfg=CFG_OFF)
    @test result.mode == :dry_run
    @test result.uri === nothing
    @test isempty(p.calls)
    @test haskey(result.record, "title")
    @test result.record["title"] == "Crucible review: paper"
    reset_http_transport!()
end

@testset "publisher: live path with stubbed slot resolution + createRecord" begin
    p = PubStub()
    # 1) createSession for slot resolution
    push!(p.queue, PubResp(200, SESS_OK))
    # 2) listRecords for slots (one open slot in the future)
    future = Dates.now(Dates.UTC) + Day(7)
    slot_payload = JSON3.write(Dict(
        "records" => [_slot_record(future, "at://did:plc:test/app.hekate.recurrence/r", "open")],
    ))
    push!(p.queue, PubResp(200, slot_payload))
    # 3) createSession again for createRecord
    push!(p.queue, PubResp(200, SESS_OK))
    # 4) createRecord
    push!(p.queue, PubResp(200, """{"uri":"at://did:plc:test/app.hekate.event/eid","cid":"bafy"}"""))
    set_http_transport!(post=_post_stub(p), get=_get_stub(p))

    req = ReviewSessionRequest(paper_title="paper", paper_summary="summary",
                               tags=String["test"])
    result = publish_review_session(req; cfg=CFG_ON)
    @test result.mode == :live
    @test result.uri == "at://did:plc:test/app.hekate.event/eid"
    @test isempty(result.errors)
    reset_http_transport!()
end

@testset "publisher: no open slots demotes to dry-run" begin
    p = PubStub()
    push!(p.queue, PubResp(200, SESS_OK))
    push!(p.queue, PubResp(200, JSON3.write(Dict("records" => []))))
    set_http_transport!(post=_post_stub(p), get=_get_stub(p))

    req = ReviewSessionRequest(paper_title="paper")
    result = publish_review_session(req; cfg=CFG_ON)
    @test result.mode == :dry_run
    @test any(e -> occursin("no open slot", e), result.errors)
    reset_http_transport!()
end

@testset "publisher: createRecord 5xx demotes to dry-run with errors" begin
    p = PubStub()
    push!(p.queue, PubResp(200, SESS_OK))
    future = Dates.now(Dates.UTC) + Day(7)
    push!(p.queue, PubResp(200, JSON3.write(Dict(
        "records" => [_slot_record(future, "at://did:plc:test/app.hekate.recurrence/r", "open")],
    ))))
    push!(p.queue, PubResp(200, SESS_OK))
    push!(p.queue, PubResp(503, """{"error":"Unavailable","message":"try later"}"""))
    set_http_transport!(post=_post_stub(p), get=_get_stub(p))

    req = ReviewSessionRequest(paper_title="paper")
    result = publish_review_session(req; cfg=CFG_ON)
    @test result.mode == :dry_run
    @test any(e -> occursin("createRecord failed", e), result.errors)
    reset_http_transport!()
end
