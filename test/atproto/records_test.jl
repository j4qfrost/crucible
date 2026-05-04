using Test
using Crucible
using Crucible.ATProto
using Dates
import JSON3

# Deterministic builders take a `created_at` so JSON output is stable.
const FIXED_TS = "2026-05-01T15:00:00.000Z"

@testset "records: venue shape" begin
    rec = build_venue(name="Crucible Lab",
                      geo_lat=0.0, geo_lon=0.0,
                      capacity=20,
                      booking_policy="review",
                      description="virtual",
                      amenities=["av-equipment", "projector"],
                      created_at=FIXED_TS)
    @test rec["name"] == "Crucible Lab"
    @test rec["geo"]["lat"] == 0.0
    @test rec["bookingPolicy"] == "review"
    @test rec["createdAt"] == FIXED_TS
    @test rec["amenities"] == ["av-equipment", "projector"]
    # round-trips through JSON3 cleanly
    s = JSON3.write(rec)
    parsed = JSON3.read(s, Dict{String,Any})
    @test parsed["name"] == rec["name"]
end

@testset "records: event shape with cap on tags" begin
    too_many = String[string("tag", i) for i in 1:30]
    rec = build_event(slot_uri="at://did:plc:abc/app.hekate.slot/1",
                      title="t",
                      tags=too_many,
                      created_at=FIXED_TS)
    @test length(rec["tags"]) == 16  # capped at lexicon maxLength=16
    @test rec["tags"][1] == "tag1"
end

@testset "records: title truncation" begin
    long_title = repeat("z", 500)
    rec = build_event(slot_uri="at://did:plc:abc/app.hekate.slot/1",
                      title=long_title,
                      created_at=FIXED_TS)
    @test length(rec["title"]) == 240
end

@testset "records: description truncation" begin
    rec = build_venue(name="x", description=repeat("y", 5000), created_at=FIXED_TS)
    @test length(rec["description"]) == 3000
end
