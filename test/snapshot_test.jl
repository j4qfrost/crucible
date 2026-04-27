using Test
using Crucible

# v1.5.2+ polish: snapshot / restore round-trip.

@testset "snapshot+restore round-trips a workdir end-to-end" begin
    Sys.which("tar") === nothing && (@info "tar not on PATH; skipping"; @test true; return)
    workdir = mktempdir(prefix="crucible-snap-")
    try
        write(joinpath(workdir, "spec.json"),
              Crucible.spec_to_json(get_template(:vanilla)))
        write(joinpath(workdir, "run_openmm.py"), "# fake script\nprint('hi')\n")
        write(joinpath(workdir, "stdout.log"), "demo log line\n")
        archive = tempname() * ".tar.gz"
        snapshot(workdir, archive)
        @test isfile(archive)
        @test filesize(archive) > 100

        dest = mktempdir(prefix="crucible-restore-")
        try
            _, manifest = restore(archive, dest)
            @test isfile(joinpath(dest, "spec.json"))
            @test isfile(joinpath(dest, "run_openmm.py"))
            @test isfile(joinpath(dest, "stdout.log"))
            @test manifest.schema_version == "0.3.0"
            @test length(manifest.files) >= 3
            @test all(!isempty(f.sha256) for f in manifest.files)
        finally
            rm(dest; recursive=true, force=true)
        end
        rm(archive; force=true)
    finally
        rm(workdir; recursive=true, force=true)
    end
end

@testset "restore detects sha256 drift" begin
    Sys.which("tar") === nothing && (@test true; return)
    workdir = mktempdir(prefix="crucible-snap-drift-")
    try
        write(joinpath(workdir, "spec.json"),
              Crucible.spec_to_json(get_template(:vanilla)))
        archive = tempname() * ".tar.gz"
        snapshot(workdir, archive)
        # Tamper the archive by extracting + corrupting + repacking.
        scratch = mktempdir()
        try
            run(pipeline(`tar -xzf $archive -C $scratch`; stdout=devnull, stderr=devnull); wait=true)
            write(joinpath(scratch, "spec.json"), "TAMPERED")
            run(pipeline(`tar -czf $archive -C $scratch .`; stdout=devnull, stderr=devnull); wait=true)
        finally
            rm(scratch; recursive=true, force=true)
        end
        dest = mktempdir()
        try
            err = try
                restore(archive, dest; verify=true)
                nothing
            catch e
                e
            end
            @test err !== nothing
            @test occursin("sha256 mismatch", err.msg) || occursin("mismatch", err.msg)
        finally
            rm(dest; recursive=true, force=true)
            rm(archive; force=true)
        end
    finally
        rm(workdir; recursive=true, force=true)
    end
end

@testset "snapshot truncates files above max-size-mb" begin
    Sys.which("tar") === nothing && (@test true; return)
    workdir = mktempdir(prefix="crucible-snap-trunc-")
    try
        write(joinpath(workdir, "spec.json"),
              Crucible.spec_to_json(get_template(:vanilla)))
        # 200 KB file
        write(joinpath(workdir, "huge.dcd"), repeat("X", 200_000))
        archive = tempname() * ".tar.gz"
        snapshot(workdir, archive; max_size_mb=0.05)   # 50 KB cap
        dest = mktempdir()
        try
            _, manifest = restore(archive, dest)
            # huge.dcd shouldn't be in the archive; huge.dcd.truncated should.
            @test !isfile(joinpath(dest, "huge.dcd"))
            @test isfile(joinpath(dest, "huge.dcd.truncated"))
            stub = read(joinpath(dest, "huge.dcd.truncated"), String)
            @test occursin("TRUNCATED", stub)
            @test occursin("200000", stub)
        finally
            rm(dest; recursive=true, force=true)
            rm(archive; force=true)
        end
    finally
        rm(workdir; recursive=true, force=true)
    end
end

@testset "restore errors when archive lacks manifest" begin
    Sys.which("tar") === nothing && (@test true; return)
    bare = mktempdir(prefix="crucible-bare-")
    try
        write(joinpath(bare, "random.txt"), "no manifest")
        archive = tempname() * ".tar.gz"
        run(pipeline(`tar -czf $archive -C $bare .`; stdout=devnull, stderr=devnull); wait=true)
        dest = mktempdir()
        try
            @test_throws ErrorException restore(archive, dest)
        finally
            rm(dest; recursive=true, force=true)
            rm(archive; force=true)
        end
    finally
        rm(bare; recursive=true, force=true)
    end
end
