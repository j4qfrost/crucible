# Schema-version migrations — carry forward old MDSpec JSON when the
# wire format changes. Hard contract: every schema bump adds an entry to
# `_MIGRATIONS` mapping (from_version, to_version) -> transformer function.
#
# Why: the option-3 fine-tune flywheel collects transcripts over months /
# years. When `schema_version` bumps from 0.1.0 -> 0.2.0, historical
# transcripts must still be loadable for training. Migrations stay
# append-only; we never break old wire formats, we just translate them.

const _MIGRATIONS = Dict{Tuple{String,String},Function}()

"""
    register_migration!(from::String, to::String, f::Function)

Register a transformation from one schema version to the next. `f` takes
a `Dict{String,Any}` (parsed JSON) and returns a `Dict{String,Any}`
matching `to`'s schema.
"""
function register_migration!(from::AbstractString, to::AbstractString, f::Function)
    _MIGRATIONS[(String(from), String(to))] = f
    nothing
end

"""
    migrate_spec_json(json::AbstractString; target = current_schema_version()) -> String

Walk the registered migrations from the input's `schema_version` to
`target`. Returns the migrated JSON. Errors if no path exists.
"""
function migrate_spec_json(json::AbstractString;
                           target::AbstractString = "0.1.0")::String
    obj = JSON3.read(json, Dict)
    src_version = String(get(obj, "schema_version", "unknown"))
    if src_version == target
        return json
    end
    # Linear path: only forward migrations supported. Build a chain.
    chain = _migration_chain(src_version, target)
    isempty(chain) && error("no migration path from $(src_version) to $(target)")
    for step in chain
        f = _MIGRATIONS[step]
        obj = f(obj)
        obj["schema_version"] = step[2]
    end
    JSON3.write(obj)
end

function _migration_chain(from::AbstractString, to::AbstractString)
    # Greedy forward walk: from current, look for any (from, *) edge whose
    # target moves us toward `to`. Since schema_version is semver-ish and
    # we only support forward migrations, we just walk all edges starting at
    # `from` and pick the longest chain that ends at `to`.
    chain = Tuple{String,String}[]
    cursor = String(from)
    visited = Set{String}([cursor])
    while cursor != to
        next_step = nothing
        for ((src, dst), _) in _MIGRATIONS
            if src == cursor && !(dst in visited)
                next_step = (src, dst)
                break
            end
        end
        next_step === nothing && return Tuple{String,String}[]
        push!(chain, next_step)
        cursor = next_step[2]
        push!(visited, cursor)
    end
    chain
end

# -----------------------------------------------------------------------------
# Bootstrap migrations: identity for the current version. When 0.2.0 lands,
# add `register_migration!("0.1.0", "0.2.0", spec_v0_1_to_v0_2)` here.

# (No migrations registered yet — schema is at 0.1.0 baseline.)
