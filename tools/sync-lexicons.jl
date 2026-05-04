#!/usr/bin/env julia
# Vendor app.hekate.* lexicons from the hekate repo into src/atproto/schemas/.
#
# Usage:
#   julia --project tools/sync-lexicons.jl
#   julia --project tools/sync-lexicons.jl --source ~/Projects/hekate/lexicons/app/hekate
#   julia --project tools/sync-lexicons.jl --force   # overwrite even if SHA differs
#
# Writes <name>.json plus <name>.json.sha256 next to each schema. Refuses to
# overwrite when an existing receipt does not match the file on disk, so a
# stale local edit is not silently clobbered (pass --force to override).
#
# rsvp.json is intentionally skipped — Crucible authors event records but does
# not RSVP to its own announcements.

using SHA

const NAMES = ("venue", "slot", "recurrence", "event")

function parse_args(args)
    out = Dict{String,String}()
    flags = Set{String}()
    i = 1
    while i <= length(args)
        a = args[i]
        if a == "--source"
            out["source"] = args[i+1]; i += 2
        elseif a == "--dest"
            out["dest"] = args[i+1]; i += 2
        elseif a == "--force"
            push!(flags, "force"); i += 1
        elseif a in ("-h", "--help")
            push!(flags, "help"); i += 1
        else
            error("unknown arg: $(a)")
        end
    end
    out, flags
end

function sha256_hex(bytes)
    bytes2hex(sha256(bytes))
end

function main(args=ARGS)
    opts, flags = parse_args(args)
    if "help" in flags
        println(read(@__FILE__, String) |> s -> first(split(s, "\n\n"), 1)[1])
        return 0
    end

    source = get(opts, "source", joinpath(homedir(), "Projects", "hekate",
                                          "lexicons", "app", "hekate"))
    dest = get(opts, "dest", joinpath(@__DIR__, "..", "src", "atproto", "schemas"))

    isdir(source) || error("source dir not found: $(source)")
    isdir(dest) || mkpath(dest)

    println("source: $(source)")
    println("dest:   $(dest)")
    println()

    changed = String[]
    for name in NAMES
        src_path = joinpath(source, "$(name).json")
        isfile(src_path) || error("missing source schema: $(src_path)")

        bytes = read(src_path)
        new_sha = sha256_hex(bytes)

        dest_json = joinpath(dest, "$(name).json")
        dest_sha = joinpath(dest, "$(name).json.sha256")

        # Refuse to overwrite a local edit that doesn't match its receipt.
        if isfile(dest_json) && isfile(dest_sha) && !("force" in flags)
            existing_bytes = read(dest_json)
            # Receipt format is "<hex>  <name>" (sha256sum-compatible). Take
            # only the leading hex token so we compare apples to apples.
            existing_sha_recorded = String(first(split(strip(read(dest_sha, String)))))
            existing_sha_actual = sha256_hex(existing_bytes)
            if existing_sha_recorded != existing_sha_actual
                error("$(dest_json) has been edited locally (sha mismatch). Pass --force to overwrite.")
            end
        end

        if isfile(dest_json) && sha256_hex(read(dest_json)) == new_sha
            println("  $(name).json  unchanged")
            continue
        end

        write(dest_json, bytes)
        write(dest_sha, new_sha * "  " * "$(name).json\n")
        push!(changed, "$(name).json")
        println("  $(name).json  updated  ($(new_sha[1:12])…)")
    end

    println()
    if isempty(changed)
        println("no changes.")
    else
        println("$(length(changed)) file(s) updated. Review and commit:")
        for f in changed
            println("  $(joinpath(dest, f))")
        end
    end
    0
end

if abspath(PROGRAM_FILE) == @__FILE__
    exit(main())
end
