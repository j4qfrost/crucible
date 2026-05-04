using Test
using Crucible
using Crucible.ATProto
using Dates

@testset "lexicon: venue round-trip" begin
    rec = build_venue(name="Lab", geo_lat=0.0, geo_lon=0.0, capacity=10)
    @test isempty(filter(v -> v.severity == :error, validate_record("venue", rec)))

    # missing required `geo`
    bad = Dict{String,Any}("name" => "x", "createdAt" => "2026-05-01T00:00:00.000Z",
                           "bookingPolicy" => "open")
    vios = validate_record("venue", bad)
    @test any(v -> v.severity == :error && occursin("geo", v.path), vios)

    # bad enum
    bad2 = Dict{String,Any}("name" => "x",
                            "geo" => Dict("lat" => 0, "lon" => 0),
                            "bookingPolicy" => "invalid",
                            "createdAt" => "2026-05-01T00:00:00.000Z")
    vios2 = validate_record("venue", bad2)
    @test any(v -> v.severity == :error && occursin("enum", v.message), vios2)

    # over-length name (will be truncated by builder; here we test the
    # validator's view on an explicit too-long string)
    bad3 = Dict{String,Any}("name" => repeat("x", 300),
                            "geo" => Dict("lat" => 0, "lon" => 0),
                            "bookingPolicy" => "open",
                            "createdAt" => "2026-05-01T00:00:00.000Z")
    vios3 = validate_record("venue", bad3)
    @test any(v -> v.severity == :error && occursin("maxLength", v.message), vios3)
end

@testset "lexicon: slot round-trip" begin
    rec = build_slot(venue_uri="at://did:plc:abc/app.hekate.venue/1",
                     start=DateTime(2026, 5, 1, 15, 0, 0),
                     end_=DateTime(2026, 5, 1, 16, 0, 0))
    @test isempty(filter(v -> v.severity == :error, validate_record("slot", rec)))

    # bad at-uri
    bad = Dict{String,Any}(rec...)
    bad["venue"] = "not-a-uri"
    vios = validate_record("slot", bad)
    @test any(v -> v.severity == :error && occursin("at-uri", v.message), vios)

    # bad enum on status
    bad2 = Dict{String,Any}(rec...)
    bad2["status"] = "frobbed"
    vios2 = validate_record("slot", bad2)
    @test any(v -> v.severity == :error && occursin("enum", v.message), vios2)
end

@testset "lexicon: recurrence round-trip" begin
    rec = build_recurrence(
        venue_uri="at://did:plc:abc/app.hekate.venue/1",
        rrule="FREQ=WEEKLY;BYDAY=FR",
        slot_duration_minutes=60,
        valid_from=DateTime(2026, 5, 1, 0, 0, 0),
    )
    @test isempty(filter(v -> v.severity == :error, validate_record("recurrence", rec)))

    # below-minimum slot duration
    bad = Dict{String,Any}(rec...)
    bad["slotDurationMinutes"] = 1
    vios = validate_record("recurrence", bad)
    @test any(v -> v.severity == :error && occursin("minimum", v.message), vios)
end

@testset "lexicon: event round-trip + bad datetime" begin
    rec = build_event(slot_uri="at://did:plc:abc/app.hekate.slot/1",
                      title="hi",
                      tags=["crucible"])
    @test isempty(filter(v -> v.severity == :error, validate_record("event", rec)))

    bad = Dict{String,Any}(rec...)
    bad["createdAt"] = "yesterday"
    vios = validate_record("event", bad)
    @test any(v -> v.severity == :error && occursin("datetime", v.message), vios)
end

@testset "lexicon: assert_valid! throws on errors" begin
    @test_throws ATProtoError build_event(slot_uri="bogus", title="hi")
end
