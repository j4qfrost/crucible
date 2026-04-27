# Snapshot / restore.
#
# Trade-off chosen: shell out to `tar -czf` rather than use the Tar stdlib
# + CodecZlib. Pros: simpler, matches the project's subprocess-over-pure-
# Julia precedent (OpenMMBackend, OpenFFParameterizer). Cons: tar must be
# on PATH (always is on Unix); won't work on bare Windows. v0 is Linux/Mac
# only, so this is fine.
#
# A snapshot is a self-contained tarball of:
#   * crucible_manifest.json    — Crucible version, schema_version, file checksums
#   * spec.json                 — the MDSpec
#   * run_*.py / run_*.jl       — the rendered backend script(s)
#   * any *.log / *.csv / *.dcd / *.nc files in the workdir
#
# Trade-off on trajectory size: by default we include everything; the
# user can pass `--max-size MB` to truncate any single file (the file is
# replaced by a `<name>.truncated` placeholder noting the original size).

const _SNAPSHOT_MANIFEST = "crucible_manifest.json"

struct SnapshotManifest
    crucible_version::String
    schema_version::String
    created_at::String
    spec_sha256::String
    files::Vector{NamedTuple{(:path, :bytes, :sha256), Tuple{String,Int,String}}}
end

"""
    snapshot(workdir, archive; max_size_mb=nothing, spec_path="spec.json") -> String

Pack `workdir` into `archive` (a `.tar.gz`). Writes a manifest with
checksums + schema version so `restore` can detect drift.

`max_size_mb`: if set, files larger than this are replaced by a
`<name>.truncated` stub (size + sha256 still recorded). Useful for
trajectories on space-constrained transports.

Returns the absolute path to the created archive.
"""
function snapshot(workdir::AbstractString, archive::AbstractString;
                  max_size_mb::Union{Nothing,Real}=nothing,
                  spec_path::AbstractString="spec.json")::String
    isdir(workdir) || error("snapshot: workdir does not exist: $(workdir)")
    abs_workdir = abspath(workdir)
    abs_archive = abspath(archive)

    Sys.which("tar") === nothing && error("snapshot: 'tar' must be on PATH")

    # Build the manifest first; tar reads files post-truncation if any.
    spec_full = joinpath(abs_workdir, spec_path)
    spec_sha = isfile(spec_full) ? bytes2hex(SHA.sha256(read(spec_full))) : ""
    schema_v = isfile(spec_full) ? _read_schema_version(spec_full) : "unknown"

    files_info = NamedTuple{(:path, :bytes, :sha256), Tuple{String,Int,String}}[]
    truncated = String[]
    cap_bytes = max_size_mb === nothing ? typemax(Int) : Int(round(max_size_mb * 1024 * 1024))

    for (root, _dirs, fnames) in walkdir(abs_workdir)
        for fname in fnames
            full = joinpath(root, fname)
            full == joinpath(abs_workdir, _SNAPSHOT_MANIFEST) && continue
            rel = relpath(full, abs_workdir)
            n = filesize(full)
            if n > cap_bytes
                stub = full * ".truncated"
                open(stub, "w") do io
                    print(io, "TRUNCATED: original size = $(n) bytes; sha256 = ",
                              bytes2hex(SHA.sha256(read(full))))
                end
                push!(files_info, (path=rel * ".truncated", bytes=filesize(stub),
                                   sha256=bytes2hex(SHA.sha256(read(stub)))))
                push!(truncated, rel)
            else
                push!(files_info, (path=rel, bytes=n,
                                   sha256=bytes2hex(SHA.sha256(read(full)))))
            end
        end
    end

    manifest = SnapshotManifest(
        _crucible_version_string(),
        schema_v,
        _iso_now(),
        spec_sha,
        files_info,
    )
    manifest_path = joinpath(abs_workdir, _SNAPSHOT_MANIFEST)
    open(manifest_path, "w") do io
        print(io, JSON3.write(_manifest_to_dict(manifest)))
    end

    # Tar the workdir, excluding the originals of any files we truncated.
    mkpath(dirname(abs_archive))
    exclude_args = String["--exclude=./$rel" for rel in truncated]
    cmd = `tar -czf $abs_archive $exclude_args -C $abs_workdir .`
    try
        run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=true)
    catch err
        error("snapshot: tar failed: $(err)")
    end

    # Clean up truncation stubs we created (the originals stay).
    for rel in truncated
        rm(joinpath(abs_workdir, rel * ".truncated"); force=true)
    end
    rm(manifest_path; force=true)

    abs_archive
end

"""
    restore(archive, dest; verify=true) -> Tuple{String, SnapshotManifest}

Unpack `archive` into `dest` (created if absent). When `verify=true`,
re-checks every file's sha256 against the manifest and errors on drift.
Returns `(dest_dir, manifest)`.
"""
function restore(archive::AbstractString, dest::AbstractString;
                 verify::Bool=true)
    isfile(archive) || error("restore: archive not found: $(archive)")
    Sys.which("tar") === nothing && error("restore: 'tar' must be on PATH")
    isdir(dest) || mkpath(dest)
    abs_archive = abspath(archive)
    abs_dest = abspath(dest)
    cmd = `tar -xzf $abs_archive -C $abs_dest`
    try
        run(pipeline(cmd; stdout=devnull, stderr=devnull); wait=true)
    catch err
        error("restore: tar -x failed: $(err)")
    end
    manifest_path = joinpath(abs_dest, _SNAPSHOT_MANIFEST)
    isfile(manifest_path) ||
        error("restore: archive contains no $(_SNAPSHOT_MANIFEST) — not a Crucible snapshot")
    manifest = _manifest_from_dict(JSON3.read(read(manifest_path, String), Dict))

    if verify
        for f in manifest.files
            full = joinpath(abs_dest, f.path)
            if !isfile(full)
                error("restore: missing file $(f.path)")
            end
            actual = bytes2hex(SHA.sha256(read(full)))
            if actual != f.sha256
                error("restore: sha256 mismatch on $(f.path)\n  expected: $(f.sha256)\n  actual:   $(actual)")
            end
        end
    end

    abs_dest, manifest
end

# -----------------------------------------------------------------------------
# Internals

function _read_schema_version(spec_path::AbstractString)
    try
        obj = JSON3.read(read(spec_path, String), Dict)
        return String(get(obj, "schema_version", "unknown"))
    catch
        return "unknown"
    end
end

function _crucible_version_string()
    # Pull from the package's Project.toml so a release bump propagates.
    try
        proj = TOML.parsefile(joinpath(@__DIR__, "..", "..", "Project.toml"))
        return String(get(proj, "version", "unknown"))
    catch
        return "unknown"
    end
end

function _iso_now()
    # Avoid pulling Dates if it's not already loaded — it is, since
    # DuckDB pulls it transitively. Defensive fallback to a string.
    try
        return string(Dates.now(Dates.UTC))
    catch
        return "unknown"
    end
end

function _manifest_to_dict(m::SnapshotManifest)
    Dict{String,Any}(
        "crucible_version" => m.crucible_version,
        "schema_version"   => m.schema_version,
        "created_at"       => m.created_at,
        "spec_sha256"      => m.spec_sha256,
        "files" => [Dict("path" => f.path, "bytes" => f.bytes,
                         "sha256" => f.sha256) for f in m.files],
    )
end

function _manifest_from_dict(d)
    files = NamedTuple{(:path, :bytes, :sha256), Tuple{String,Int,String}}[]
    for f in d["files"]
        push!(files, (path=String(f["path"]), bytes=Int(f["bytes"]),
                      sha256=String(f["sha256"])))
    end
    SnapshotManifest(
        String(get(d, "crucible_version", "unknown")),
        String(get(d, "schema_version", "unknown")),
        String(get(d, "created_at", "unknown")),
        String(get(d, "spec_sha256", "")),
        files,
    )
end
