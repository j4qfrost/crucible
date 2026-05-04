# Gate-5 hook entry point. Default behaviour is dry-run (build + validate +
# log); only when CRUCIBLE_HEKATE_PUBLISH_EVENTS=1 do we actually call
# createRecord.
#
# Per Hekate's CLAUDE.md and ADR 0002, the app.hekate.event lexicon is not
# frozen yet — keep this gate firmly closed until ADR 0002 closes.

struct ReviewSessionRequest
    paper_title::String
    paper_summary::String
    report_url::Union{Nothing,String}
    tags::Vector{String}
    workdir::Union{Nothing,String}
end

ReviewSessionRequest(; paper_title="", paper_summary="", report_url=nothing,
                     tags=String[], workdir=nothing) =
    ReviewSessionRequest(String(paper_title), String(paper_summary),
                         report_url === nothing ? nothing : String(report_url),
                         String[String(t) for t in tags],
                         workdir === nothing ? nothing : String(workdir))

# Result envelope. mode is one of (:dry_run, :live). errors is non-empty when
# we tried to publish live and something failed (validation, HTTP, etc.); the
# caller should still treat the simulation as having succeeded.
struct PublishResult
    mode::Symbol
    record::Dict{String,Any}
    uri::Union{Nothing,String}
    cid::Union{Nothing,String}
    errors::Vector{String}
end

"""
    publish_review_session(req; cfg=load_config())

Build an app.hekate.event record from the given review-session request,
validate it locally, and either dry-run-log it (default) or createRecord
it on the configured PDS. Errors are caught and demoted to warnings so
that a publish failure never masks a successful simulation.
"""
function publish_review_session(req::ReviewSessionRequest;
                                cfg::HekateConfig=load_config())::PublishResult
    errors = String[]

    # Resolve next open slot. Live path needs a slot AT-URI; dry-run can use
    # a placeholder so the user can still see what would be published.
    slot_uri = nothing
    if is_publish_ready(cfg)
        try
            session = create_session(cfg)
            slot_uri = resolve_next_open_slot(session, cfg)
        catch err
            push!(errors, "slot resolution failed: $(_short_error(err))")
        end
    end

    if slot_uri === nothing
        slot_uri = string("at://", cfg.venue_at_uri === nothing ? "did:plc:UNKNOWN" :
                          _did_from_uri(cfg.venue_at_uri),
                          "/app.hekate.slot/dryrun-no-open-slot")
    end

    title = _build_title(req)
    description = _build_description(req)
    tags = _build_tags(req, cfg)

    record = try
        build_event(;
            slot_uri=slot_uri,
            title=title,
            description=description,
            tags=tags,
            visibility="public",
            external_url=req.report_url === nothing ? _workdir_url(req.workdir) : req.report_url,
        )
    catch err
        push!(errors, "record build failed: $(_short_error(err))")
        # Return a dry-run result so the caller doesn't see an exception.
        return PublishResult(:dry_run, Dict{String,Any}(), nothing, nothing, errors)
    end

    # If we couldn't resolve a real slot (or the gate is closed), stop here.
    if !is_publish_ready(cfg) || startswith(slot_uri, "at://did:plc:UNKNOWN") ||
       occursin("dryrun-no-open-slot", slot_uri)
        if !is_publish_ready(cfg)
            @info "[hekate dry-run] would publish app.hekate.event (set CRUCIBLE_HEKATE_PUBLISH_EVENTS=1 + bootstrap to enable)" record=record
        else
            @info "[hekate dry-run] would publish app.hekate.event (no open slot — run `crucible hekate create-slot` first)" record=record
            push!(errors, "no open slot available for recurrence $(cfg.recurrence_at_uri)")
        end
        return PublishResult(:dry_run, record, nothing, nothing, errors)
    end

    # Live path.
    try
        session = create_session(cfg)
        result = create_record(session, "app.hekate.event", record)
        @info "[hekate] published app.hekate.event" uri=result.uri cid=result.cid
        return PublishResult(:live, record, result.uri, result.cid, errors)
    catch err
        push!(errors, "createRecord failed: $(_short_error(err))")
        @warn "[hekate] publish failed; demoting to dry-run" error=_short_error(err)
        return PublishResult(:dry_run, record, nothing, nothing, errors)
    end
end

"""
    publish_review_session_from_run(spec_json, workdir, paper_title, report_url)

Convenience wrapper used from `cmd_run`. Recovers paper title fall-backs and
spec-derived tags, then delegates to `publish_review_session`. Catches every
exception so a publish failure can never mask a successful simulation.
"""
function publish_review_session_from_run(spec_json::AbstractString,
                                         workdir::AbstractString,
                                         paper_title::AbstractString,
                                         report_url::AbstractString)
    try
        spec = Crucible.spec_from_json(String(spec_json))
        title = if !isempty(paper_title)
            String(paper_title)
        elseif !isempty(strip(spec.notes))
            first(split(spec.notes, "\n"))
        else
            "Crucible review"
        end

        summary = try
            Crucible._explain_spec(spec)
        catch
            "Crucible run."
        end

        tags = _spec_tags(spec)

        req = ReviewSessionRequest(;
            paper_title=String(title),
            paper_summary=String(summary),
            report_url=isempty(report_url) ? nothing : String(report_url),
            tags=tags,
            workdir=String(workdir),
        )
        return publish_review_session(req)
    catch err
        @warn "[hekate] publish hook failed (caught at boundary)" error=_short_error(err)
        return PublishResult(:dry_run, Dict{String,Any}(), nothing, nothing,
                             String["hook boundary error: $(_short_error(err))"])
    end
end

# ----- helpers --------------------------------------------------------------

function _short_error(err)
    io = IOBuffer()
    showerror(io, err)
    s = String(take!(io))
    length(s) > 240 ? first(s, 240) : s
end

function _did_from_uri(at_uri::AbstractString)
    m = match(r"^at://([^/]+)/", String(at_uri))
    m === nothing ? "did:plc:UNKNOWN" : String(m.captures[1])
end

function _workdir_url(workdir::Union{Nothing,AbstractString})
    workdir === nothing && return nothing
    "file://" * String(workdir)
end

function _build_title(req::ReviewSessionRequest)
    title = isempty(req.paper_title) ? "Crucible review" : "Crucible review: $(req.paper_title)"
    length(title) > 240 ? first(title, 240) : title
end

function _build_description(req::ReviewSessionRequest)
    body = isempty(req.paper_summary) ? "Crucible run." : req.paper_summary
    footer = req.report_url !== nothing ? "Run artifact: $(req.report_url)" :
             req.workdir !== nothing ? "Run artifact: file://$(req.workdir)" : ""
    full = isempty(footer) ? body : "$(body)\n\n$(footer)"
    length(full) > 10000 ? first(full, 10000) : full
end

function _build_tags(req::ReviewSessionRequest, cfg::HekateConfig)
    seen = Set{String}()
    out = String[]
    for t in vcat(cfg.default_tags, req.tags)
        s = String(strip(t))
        isempty(s) && continue
        if !(s in seen)
            push!(seen, s)
            push!(out, s)
            length(out) >= 16 && break
        end
    end
    out
end

# Best-effort tag extraction from a spec. Returns empty if any access fails.
function _spec_tags(spec)
    tags = String[]
    try
        if hasproperty(spec, :system) && hasproperty(spec.system, :solvent) &&
           spec.system.solvent.membrane !== nothing
            push!(tags, "membrane")
        end
        if hasproperty(spec, :protocol)
            for stage in spec.protocol
                # symbolic short-hand check by type name (works regardless of
                # the FEPStage / REMDStage / MetadynamicsStage struct identity)
                tname = lowercase(String(nameof(typeof(stage))))
                if occursin("fep", tname); push!(tags, "fep"); end
                if occursin("remd", tname); push!(tags, "remd"); end
                if occursin("metadynamics", tname); push!(tags, "metadynamics"); end
            end
        end
        if hasproperty(spec, :force_field)
            ff = String(spec.force_field.protein)
            if startswith(ff, "martini")
                push!(tags, "coarse-grained")
            end
        end
    catch
        # swallow — tags are optional
    end
    unique!(tags)
    tags
end

"""
    resolve_next_open_slot(session, cfg) -> Union{Nothing,String}

List the bot DID's `app.hekate.slot` records, filter to open slots in our
recurrence whose `start` is in the future, and return the earliest one.
"""
function resolve_next_open_slot(session::Session, cfg::HekateConfig;
                                now_utc::Dates.DateTime=Dates.now(Dates.UTC))
    cfg.recurrence_at_uri === nothing && return nothing

    candidates = Tuple{Dates.DateTime, String}[]
    cursor = nothing
    pages = 0
    while pages < 10
        result = list_records(session, session.did, "app.hekate.slot";
                              limit=100, cursor=cursor)
        for entry in result.records
            value = get(entry, "value", nothing)
            value === nothing && continue
            status = String(get(value, "status", ""))
            recurrence = String(get(value, "recurrence", ""))
            start_str = String(get(value, "start", ""))

            status == "open" || continue
            recurrence == cfg.recurrence_at_uri || continue
            isempty(start_str) && continue

            dt = try
                _parse_iso(start_str)
            catch
                continue
            end
            dt === nothing && continue
            dt > now_utc || continue

            uri = String(get(entry, "uri", ""))
            isempty(uri) && continue
            push!(candidates, (dt, uri))
        end
        cursor = result.cursor
        cursor === nothing && break
        pages += 1
    end

    isempty(candidates) && return nothing
    sort!(candidates; by=t -> t[1])
    candidates[1][2]
end

function _parse_iso(s::AbstractString)
    s = String(s)
    body = s
    m = match(r"^(.+?)(Z|[+-]\d{2}:?\d{2})$", s)
    m !== nothing && (body = m.captures[1])
    for fmt in ("yyyy-mm-ddTHH:MM:SS.sss", "yyyy-mm-ddTHH:MM:SS.s", "yyyy-mm-ddTHH:MM:SS")
        try
            return Dates.DateTime(body, Dates.DateFormat(fmt))
        catch
        end
    end
    nothing
end
