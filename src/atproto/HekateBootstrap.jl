# One-time bootstrap: author a venue + recurrence under the bot DID and cache
# the resulting AT-URIs to ~/.config/crucible/hekate.toml.
#
# Venue and recurrence lexicons are frozen (per Hekate's CLAUDE.md), so this
# is safe to publish without the CRUCIBLE_HEKATE_PUBLISH_EVENTS gate.

const _DEFAULT_RRULE = "FREQ=WEEKLY;BYDAY=FR;BYHOUR=15;BYMINUTE=0"

"""
    bootstrap_venue!(cfg; name, lat, lon, capacity, rrule, duration_min, dry_run)

Author the venue + recurrence records and persist URIs to TOML. Returns a
NamedTuple with `:venue_uri` and `:recurrence_uri`. With `dry_run=true`,
builds and validates the records but skips the HTTP calls.
"""
function bootstrap_venue!(cfg::HekateConfig;
    name::AbstractString="Crucible Lab",
    lat::Real=0.0,
    lon::Real=0.0,
    capacity::Integer=20,
    rrule::AbstractString=_DEFAULT_RRULE,
    duration_min::Integer=60,
    description::AbstractString="Virtual review venue for Crucible paper-transpile sessions. Geo coordinates are placeholders; sessions occur over video.",
    booking_policy::AbstractString="review",
    dry_run::Bool=false,
)::NamedTuple{(:venue_uri, :recurrence_uri), Tuple{String, String}}
    venue_record = build_venue(;
        name=name, geo_lat=lat, geo_lon=lon,
        capacity=capacity, booking_policy=booking_policy,
        description=description,
        amenities=["av-equipment", "projector"],
    )

    if dry_run
        @info "[hekate dry-run] would publish app.hekate.venue" record=venue_record
    end

    if !dry_run
        isempty(cfg.handle) && error("CRUCIBLE_HEKATE_PUBLISHER_HANDLE is empty; refuse to bootstrap")
        isempty(cfg.app_password) && error("CRUCIBLE_HEKATE_PUBLISHER_APP_PASSWORD is empty; refuse to bootstrap")
    end

    venue_uri = if dry_run
        "at://did:plc:DRYRUN/app.hekate.venue/dryrun"
    else
        s = create_session(cfg)
        result = create_record(s, "app.hekate.venue", venue_record)
        result.uri
    end

    recurrence_record = build_recurrence(;
        venue_uri=venue_uri,
        rrule=rrule,
        slot_duration_minutes=duration_min,
        valid_from=Dates.now(Dates.UTC),
        title="Crucible weekly paper review",
    )

    if dry_run
        @info "[hekate dry-run] would publish app.hekate.recurrence" record=recurrence_record
        return (venue_uri="at://did:plc:DRYRUN/app.hekate.venue/dryrun",
                recurrence_uri="at://did:plc:DRYRUN/app.hekate.recurrence/dryrun")
    end

    # Re-use the session created above. We re-create only because dry_run
    # branched away; in the live path we still have it.
    s = create_session(cfg)
    rec_result = create_record(s, "app.hekate.recurrence", recurrence_record)
    recurrence_uri = rec_result.uri

    save_bootstrap!(cfg, venue_uri, recurrence_uri)

    (venue_uri=venue_uri, recurrence_uri=recurrence_uri)
end

"""
    create_slot!(cfg; start, duration_min)

Author a single `app.hekate.slot` record under the cached venue + recurrence.
This is a manual stop-gap until Hekate's M1 indexer expands recurrences into
slots automatically.
"""
function create_slot!(cfg::HekateConfig;
    start::Union{Nothing,Dates.DateTime}=nothing,
    duration_min::Integer=60,
)::String
    cfg.venue_at_uri === nothing && error("no venue at-uri cached; run `crucible hekate bootstrap-venue` first")
    cfg.recurrence_at_uri === nothing && error("no recurrence at-uri cached; run `crucible hekate bootstrap-venue` first")

    start_dt = start === nothing ? _next_friday_1500_utc() : start
    end_dt = start_dt + Dates.Minute(duration_min)

    record = build_slot(;
        venue_uri=cfg.venue_at_uri,
        recurrence_uri=cfg.recurrence_at_uri,
        start=start_dt,
        end_=end_dt,
        status="open",
    )

    s = create_session(cfg)
    result = create_record(s, "app.hekate.slot", record)
    result.uri
end

# Compute the next Friday at 15:00 UTC. If today is Friday and it's before
# 15:00, returns today; otherwise the following Friday.
function _next_friday_1500_utc()
    now_utc = Dates.now(Dates.UTC)
    today = Dates.Date(now_utc)
    days_ahead = (Dates.Friday - Dates.dayofweek(today) + 7) % 7
    target_date = today + Dates.Day(days_ahead)
    target = Dates.DateTime(target_date) + Dates.Hour(15)
    if days_ahead == 0 && now_utc >= target
        target += Dates.Day(7)
    end
    target
end
