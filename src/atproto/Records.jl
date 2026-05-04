# Typed builders that produce Dict{String,Any} ready for createRecord. Each
# fills createdAt with now(UTC) when not provided and runs the lexicon
# validator. Returned dicts may be passed straight to Client.create_record.

const _ISO_FORMAT = dateformat"yyyy-mm-ddTHH:MM:SS.sssZ"

function _now_iso()
    Dates.format(Dates.now(Dates.UTC), _ISO_FORMAT)
end

function _datetime_iso(dt::Dates.DateTime)
    Dates.format(dt, _ISO_FORMAT)
end

function _truncate(s::AbstractString, max_len::Int)
    s = String(s)
    length(s) <= max_len ? s : first(s, max_len)
end

"""
    build_venue(; name, geo_lat, geo_lon, ...)

Build an `app.hekate.venue` record. `name` is required; `geo_lat`/`geo_lon`
default to (0, 0) for virtual venues. Validates the result against the
vendored lexicon and throws ATProtoError on failure.
"""
function build_venue(;
    name::AbstractString,
    geo_lat::Real=0.0,
    geo_lon::Real=0.0,
    altitude_meters::Union{Nothing,Real}=nothing,
    address_text::Union{Nothing,AbstractString}=nothing,
    capacity::Union{Nothing,Integer}=nothing,
    amenities::Vector{<:AbstractString}=String[],
    booking_policy::AbstractString="open",
    description::Union{Nothing,AbstractString}=nothing,
    contact_url::Union{Nothing,AbstractString}=nothing,
    contact_email::Union{Nothing,AbstractString}=nothing,
    created_at::Union{Nothing,AbstractString}=nothing,
)::Dict{String,Any}
    geo = Dict{String,Any}("lat" => Float64(geo_lat), "lon" => Float64(geo_lon))
    altitude_meters !== nothing && (geo["altitudeMeters"] = Float64(altitude_meters))

    rec = Dict{String,Any}(
        "name" => _truncate(name, 240),
        "geo" => geo,
        "bookingPolicy" => String(booking_policy),
        "createdAt" => created_at === nothing ? _now_iso() : String(created_at),
    )

    description !== nothing && (rec["description"] = _truncate(description, 3000))
    capacity !== nothing && (rec["capacity"] = Int(capacity))

    if !isempty(amenities)
        capped = first(amenities, min(32, length(amenities)))
        rec["amenities"] = [_truncate(String(a), 64) for a in capped]
    end

    if address_text !== nothing
        rec["address"] = Dict{String,Any}("text" => _truncate(address_text, 500))
    end

    if contact_url !== nothing || contact_email !== nothing
        contact = Dict{String,Any}()
        contact_url !== nothing && (contact["url"] = String(contact_url))
        contact_email !== nothing && (contact["email"] = String(contact_email))
        rec["contact"] = contact
    end

    assert_valid!("venue", rec)
    rec
end

"""
    build_recurrence(; venue_uri, rrule, slot_duration_minutes, valid_from, ...)

Build an `app.hekate.recurrence` record. `valid_from` is a `DateTime` (UTC).
"""
function build_recurrence(;
    venue_uri::AbstractString,
    rrule::AbstractString,
    slot_duration_minutes::Integer,
    valid_from::Dates.DateTime,
    valid_until::Union{Nothing,Dates.DateTime}=nothing,
    title::Union{Nothing,AbstractString}=nothing,
    created_at::Union{Nothing,AbstractString}=nothing,
)::Dict{String,Any}
    rec = Dict{String,Any}(
        "venue" => String(venue_uri),
        "rrule" => String(rrule),
        "slotDurationMinutes" => Int(slot_duration_minutes),
        "validFrom" => _datetime_iso(valid_from),
        "createdAt" => created_at === nothing ? _now_iso() : String(created_at),
    )
    valid_until !== nothing && (rec["validUntil"] = _datetime_iso(valid_until))
    title !== nothing && (rec["title"] = _truncate(title, 240))

    assert_valid!("recurrence", rec)
    rec
end

"""
    build_slot(; venue_uri, start, end_, ...)

Build an `app.hekate.slot` record. The reserved word `end` is exposed as
the keyword `end_`.
"""
function build_slot(;
    venue_uri::AbstractString,
    start::Dates.DateTime,
    end_::Dates.DateTime,
    recurrence_uri::Union{Nothing,AbstractString}=nothing,
    status::AbstractString="open",
    notes::Union{Nothing,AbstractString}=nothing,
    created_at::Union{Nothing,AbstractString}=nothing,
)::Dict{String,Any}
    rec = Dict{String,Any}(
        "venue" => String(venue_uri),
        "start" => _datetime_iso(start),
        "end" => _datetime_iso(end_),
        "status" => String(status),
        "createdAt" => created_at === nothing ? _now_iso() : String(created_at),
    )
    recurrence_uri !== nothing && (rec["recurrence"] = String(recurrence_uri))
    notes !== nothing && (rec["notes"] = _truncate(notes, 1000))

    assert_valid!("slot", rec)
    rec
end

"""
    build_event(; slot_uri, title, ...)

Build an `app.hekate.event` record. Reminder: per Hekate's CLAUDE.md, do not
publish event records to a non-test PDS until ADR 0002 closes. This builder
is safe (it just produces a Dict + validates); the gate is in HekatePublisher.
"""
function build_event(;
    slot_uri::AbstractString,
    title::AbstractString,
    description::Union{Nothing,AbstractString}=nothing,
    tags::Vector{<:AbstractString}=String[],
    visibility::AbstractString="public",
    capacity_cap::Union{Nothing,Integer}=nothing,
    external_url::Union{Nothing,AbstractString}=nothing,
    created_at::Union{Nothing,AbstractString}=nothing,
)::Dict{String,Any}
    rec = Dict{String,Any}(
        "slot" => String(slot_uri),
        "title" => _truncate(title, 240),
        "visibility" => String(visibility),
        "createdAt" => created_at === nothing ? _now_iso() : String(created_at),
    )

    description !== nothing && (rec["description"] = _truncate(description, 10000))

    if !isempty(tags)
        capped = first(tags, min(16, length(tags)))
        rec["tags"] = [_truncate(String(t), 64) for t in capped]
    end

    capacity_cap !== nothing && (rec["capacityCap"] = Int(capacity_cap))
    external_url !== nothing && (rec["externalUrl"] = _truncate(external_url, 512))

    assert_valid!("event", rec)
    rec
end
