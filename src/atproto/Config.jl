# HekateConfig: env-var + TOML overlay. The app password is env-only; bootstrap
# never writes it back to disk.

struct HekateConfig
    pds_url::String
    handle::String
    app_password::String
    publish_events::Bool
    venue_at_uri::Union{Nothing,String}
    recurrence_at_uri::Union{Nothing,String}
    config_path::String
    default_tags::Vector{String}
end

function default_config_path()
    base = get(ENV, "XDG_CONFIG_HOME", joinpath(homedir(), ".config"))
    joinpath(base, "crucible", "hekate.toml")
end

function _truthy(s::AbstractString)
    s in ("1", "true", "TRUE", "yes", "YES", "on", "ON")
end

function _split_tags(s::AbstractString)
    [strip(t) for t in split(s, ",") if !isempty(strip(t))]
end

function load_config(; config_path::AbstractString=get(ENV, "CRUCIBLE_HEKATE_CONFIG_PATH", default_config_path()))::HekateConfig
    toml_data = Dict{String,Any}()
    if isfile(config_path)
        try
            toml_data = TOML.parsefile(config_path)
        catch err
            @warn "failed to parse hekate config; ignoring" path=config_path err=string(err)
        end
    end

    pub = get(toml_data, "publisher", Dict{String,Any}())
    venue = get(toml_data, "venue", Dict{String,Any}())
    recurrence = get(toml_data, "recurrence", Dict{String,Any}())

    pds_url = get(ENV, "CRUCIBLE_HEKATE_PDS_URL",
                  get(pub, "pds_url", "https://bsky.social"))
    handle = get(ENV, "CRUCIBLE_HEKATE_PUBLISHER_HANDLE",
                 get(pub, "handle", ""))
    app_password = get(ENV, "CRUCIBLE_HEKATE_PUBLISHER_APP_PASSWORD", "")

    publish_events = _truthy(get(ENV, "CRUCIBLE_HEKATE_PUBLISH_EVENTS", "0"))

    venue_uri = get(ENV, "CRUCIBLE_HEKATE_VENUE_AT_URI",
                    get(venue, "at_uri", ""))
    recurrence_uri = get(ENV, "CRUCIBLE_HEKATE_RECURRENCE_AT_URI",
                         get(recurrence, "at_uri", ""))

    default_tags_raw = get(ENV, "CRUCIBLE_HEKATE_DEFAULT_TAGS",
                           "crucible,drug-discovery,molecular-dynamics")
    default_tags = _split_tags(default_tags_raw)

    HekateConfig(
        String(pds_url),
        String(handle),
        String(app_password),
        publish_events,
        isempty(venue_uri) ? nothing : String(venue_uri),
        isempty(recurrence_uri) ? nothing : String(recurrence_uri),
        String(config_path),
        default_tags,
    )
end

function is_publish_ready(cfg::HekateConfig)
    cfg.publish_events &&
        !isempty(cfg.handle) &&
        !isempty(cfg.app_password) &&
        cfg.venue_at_uri !== nothing &&
        cfg.recurrence_at_uri !== nothing
end

# save_bootstrap! persists URIs (and pds_url + handle) to TOML. Never writes
# the app password — that stays in the environment.
function save_bootstrap!(cfg::HekateConfig, venue_uri::AbstractString, recurrence_uri::AbstractString)
    path = cfg.config_path
    isdir(dirname(path)) || mkpath(dirname(path))

    payload = Dict{String,Any}(
        "publisher" => Dict{String,Any}(
            "handle" => cfg.handle,
            "pds_url" => cfg.pds_url,
        ),
        "venue" => Dict{String,Any}("at_uri" => String(venue_uri)),
        "recurrence" => Dict{String,Any}("at_uri" => String(recurrence_uri)),
    )

    open(path, "w") do io
        TOML.print(io, payload; sorted=true)
    end
    path
end
