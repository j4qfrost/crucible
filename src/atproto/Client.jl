# XRPC client for Bluesky-compatible PDSes. App-password session auth, no
# proactive refresh — on 401 we re-create the session and retry once.
#
# HTTP transport goes through _http_post / _http_get, which read a Ref{Function}
# so tests can inject a stub without monkey-patching HTTP.jl globally.

mutable struct Session
    pds_url::String
    did::String
    handle::String
    access_jwt::String
    refresh_jwt::String
    expires_hint::Dates.DateTime
end

# Test seam. Default points at HTTP.jl; tests may set it to a stub via
# set_http_transport!. The shape mirrors HTTP.post / HTTP.get just enough for
# our use.
const _http_post_ref = Ref{Function}((url, headers, body; kwargs...) ->
    HTTP.post(url, headers, body; status_exception=false, kwargs...))
const _http_get_ref = Ref{Function}((url, headers; kwargs...) ->
    HTTP.get(url, headers; status_exception=false, kwargs...))

function set_http_transport!(; post=nothing, get=nothing)
    post !== nothing && (_http_post_ref[] = post)
    get !== nothing && (_http_get_ref[] = get)
    nothing
end

function reset_http_transport!()
    _http_post_ref[] = (url, headers, body; kwargs...) ->
        HTTP.post(url, headers, body; status_exception=false, kwargs...)
    _http_get_ref[] = (url, headers; kwargs...) ->
        HTTP.get(url, headers; status_exception=false, kwargs...)
    nothing
end

function _xrpc_url(pds_url::AbstractString, method::AbstractString)
    rstrip(String(pds_url), '/') * "/xrpc/" * String(method)
end

function _post_xrpc(pds_url::AbstractString, method::AbstractString,
                   body::AbstractDict; auth::Union{Nothing,AbstractString}=nothing,
                   timeout_s::Int=30)
    url = _xrpc_url(pds_url, method)
    headers = Pair{String,String}["content-type" => "application/json"]
    auth !== nothing && push!(headers, "authorization" => "Bearer " * String(auth))
    payload = JSON3.write(body)
    resp = _http_post_ref[](url, headers, payload; readtimeout=timeout_s)
    status = Int(resp.status)
    body_str = String(resp.body)
    status, body_str
end

function _get_xrpc(pds_url::AbstractString, method::AbstractString,
                   query::AbstractDict; auth::Union{Nothing,AbstractString}=nothing,
                   timeout_s::Int=30)
    parts = String[]
    for (k, v) in query
        v === nothing && continue
        push!(parts, string(HTTP.escapeuri(String(k)), "=", HTTP.escapeuri(string(v))))
    end
    qs = isempty(parts) ? "" : "?" * join(parts, "&")
    url = _xrpc_url(pds_url, method) * qs
    headers = Pair{String,String}[]
    auth !== nothing && push!(headers, "authorization" => "Bearer " * String(auth))
    resp = _http_get_ref[](url, headers; readtimeout=timeout_s)
    status = Int(resp.status)
    body_str = String(resp.body)
    status, body_str
end

"""
    create_session(cfg) -> Session

Exchange handle + app-password for an access JWT via
`com.atproto.server.createSession`. Throws ATProtoError on non-2xx.
"""
function create_session(cfg::HekateConfig)::Session
    isempty(cfg.handle) && throw(ATProtoError(0, "createSession", "",
        "ConfigError", "CRUCIBLE_HEKATE_PUBLISHER_HANDLE is empty"))
    isempty(cfg.app_password) && throw(ATProtoError(0, "createSession", "",
        "ConfigError", "CRUCIBLE_HEKATE_PUBLISHER_APP_PASSWORD is empty"))

    body = Dict{String,Any}(
        "identifier" => cfg.handle,
        "password" => cfg.app_password,
    )
    status, resp_body = _post_xrpc(cfg.pds_url, "com.atproto.server.createSession", body)
    if status < 200 || status >= 300
        throw(ATProtoError(status, "createSession", resp_body))
    end

    parsed = JSON3.read(resp_body, Dict{String,Any})
    Session(
        cfg.pds_url,
        String(parsed["did"]),
        String(get(parsed, "handle", cfg.handle)),
        String(parsed["accessJwt"]),
        String(parsed["refreshJwt"]),
        Dates.now(Dates.UTC) + Dates.Hour(1),
    )
end

"""
    create_record(session, collection, record; rkey=nothing) -> (uri, cid)

POST `com.atproto.repo.createRecord`. Does NOT retry on 401 — use the
HekateConfig variant for that.
"""
function create_record(s::Session, collection::AbstractString,
                       record::AbstractDict; rkey::Union{Nothing,AbstractString}=nothing)
    body = Dict{String,Any}(
        "repo" => s.did,
        "collection" => String(collection),
        "record" => record,
    )
    rkey !== nothing && (body["rkey"] = String(rkey))
    status, resp_body = _post_xrpc(s.pds_url, "com.atproto.repo.createRecord",
                                   body; auth=s.access_jwt)
    if status < 200 || status >= 300
        throw(ATProtoError(status, "createRecord:$(collection)", resp_body))
    end
    parsed = JSON3.read(resp_body, Dict{String,Any})
    (uri = String(parsed["uri"]), cid = String(parsed["cid"]))
end

"""
    create_record(cfg, session_ref, collection, record; rkey=nothing) -> (uri, cid)

createRecord with one-time 401 retry. `session_ref::Ref{Union{Nothing,Session}}`
caches the active session; on 401 we drop it and re-create.
"""
function create_record(cfg::HekateConfig, session_ref::Ref,
                       collection::AbstractString, record::AbstractDict;
                       rkey::Union{Nothing,AbstractString}=nothing)
    if session_ref[] === nothing
        session_ref[] = create_session(cfg)
    end
    try
        return create_record(session_ref[]::Session, collection, record; rkey=rkey)
    catch err
        if err isa ATProtoError && err.status == 401
            session_ref[] = create_session(cfg)
            return create_record(session_ref[]::Session, collection, record; rkey=rkey)
        end
        rethrow()
    end
end

"""
    get_record(session, at_uri) -> Dict

Fetch a record by its AT-URI via `com.atproto.repo.getRecord`.
"""
function get_record(s::Session, at_uri::AbstractString)
    m = match(r"^at://([^/]+)/([^/]+)/([^/]+)$", String(at_uri))
    m === nothing && throw(ATProtoError(0, "getRecord", "",
        "InvalidURI", "not a valid at-uri: $(at_uri)"))
    repo, collection, rkey = m.captures
    query = Dict{String,Any}("repo" => repo, "collection" => collection, "rkey" => rkey)
    status, resp_body = _get_xrpc(s.pds_url, "com.atproto.repo.getRecord",
                                  query; auth=s.access_jwt)
    if status < 200 || status >= 300
        throw(ATProtoError(status, "getRecord:$(collection)", resp_body))
    end
    JSON3.read(resp_body, Dict{String,Any})
end

"""
    list_records(session, did, collection; limit=50, cursor=nothing)

Wrap `com.atproto.repo.listRecords`. Returns a NamedTuple with `:records` and
`:cursor` keys.
"""
function list_records(s::Session, did::AbstractString, collection::AbstractString;
                      limit::Integer=50, cursor::Union{Nothing,AbstractString}=nothing)
    query = Dict{String,Any}(
        "repo" => String(did),
        "collection" => String(collection),
        "limit" => Int(limit),
    )
    cursor !== nothing && (query["cursor"] = String(cursor))
    status, resp_body = _get_xrpc(s.pds_url, "com.atproto.repo.listRecords",
                                  query; auth=s.access_jwt)
    if status < 200 || status >= 300
        throw(ATProtoError(status, "listRecords:$(collection)", resp_body))
    end
    parsed = JSON3.read(resp_body, Dict{String,Any})
    records = get(parsed, "records", Any[])
    next_cursor = get(parsed, "cursor", nothing)
    (records = records, cursor = next_cursor === nothing ? nothing : String(next_cursor))
end

"""
    delete_record(session, collection, rkey)

Wrap `com.atproto.repo.deleteRecord`. Used by tests for cleanup.
"""
function delete_record(s::Session, collection::AbstractString, rkey::AbstractString)
    body = Dict{String,Any}(
        "repo" => s.did,
        "collection" => String(collection),
        "rkey" => String(rkey),
    )
    status, resp_body = _post_xrpc(s.pds_url, "com.atproto.repo.deleteRecord",
                                   body; auth=s.access_jwt)
    if status < 200 || status >= 300
        throw(ATProtoError(status, "deleteRecord:$(collection)", resp_body))
    end
    nothing
end
