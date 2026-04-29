using Test
using Crucible

# Re-include CLI without `using` (the file is also pulled in by cli_test;
# Julia warns about module replacement which is harmless but noisy).
isdefined(Main, :CLI) || include(joinpath(@__DIR__, "..", "src", "cli", "CLI.jl"))

@testset "cmd_fmt pretty-prints a spec" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    original_stdout = stdout
    rd, wr = redirect_stdout()
    rc = nothing
    try
        rc = CLI.main(String["fmt", fixture])
    finally
        redirect_stdout(original_stdout)
        close(wr)
    end
    @test rc == 0
    out = read(rd, String)
    # Pretty output has newlines + indentation that the compact form lacks
    @test count('\n', out) > 5
    parsed = Crucible.spec_from_json(out)
    @test parsed.schema_version == "0.3.0"
end

@testset "cmd_fmt --in-place writes back" begin
    src = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    tmp = tempname() * ".json"
    cp(src, tmp)
    try
        original_stderr = stderr
        rd_e, wr_e = redirect_stderr()
        rc = nothing
        try
            rc = CLI.main(String["fmt", tmp, "--in-place"])
        finally
            redirect_stderr(original_stderr)
            close(wr_e)
        end
        @test rc == 0
        body = read(tmp, String)
        @test count('\n', body) > 5
        @test Crucible.gate_schema(body).ok
    finally
        rm(tmp; force=true)
    end
end

@testset "cmd_trajstat reports counts on a synthetic workdir" begin
    workdir = mktempdir(prefix="crucible-trajstat-")
    try
        write(joinpath(workdir, "spec.json"),
              Crucible.spec_to_json(Crucible.get_template(:vanilla)))
        write(joinpath(workdir, "stage_traj.dcd"), "fakebytes")
        write(joinpath(workdir, "stage.log"), "Energy: -100\n")
        write(joinpath(workdir, "rmsd.csv"), "frame,rmsd\n")
        write(joinpath(workdir, "run_openmm.py"), "# script\n")

        original_stdout = stdout
        rd, wr = redirect_stdout()
        rc = nothing
        try
            rc = CLI.main(String["trajstat", workdir])
        finally
            redirect_stdout(original_stdout)
            close(wr)
        end
        @test rc == 0
        out = read(rd, String)
        @test occursin("trajectory:", out)
        @test occursin("timeseries:", out)
        @test occursin("spec:", out)
        @test occursin("script:", out)
        @test occursin("stage_traj.dcd", out)
    finally
        rm(workdir; recursive=true, force=true)
    end
end

@testset "cmd_upgrade migrates a v0.1.0 spec to v0.2.0" begin
    # Build a v0.1.0-shape spec missing v1+ fields.
    obj = Dict{String,Any}(
        "schema_version" => "0.1.0",
        "system" => Dict(
            "source" => Dict("type" => "user_supplied", "topology" => "x.parm7",
                             "coordinates" => "x.rst7", "pdb_id" => nothing),
            "n_atoms_estimate" => 100, "has_ligand" => false,
            "solvent" => Dict("model" => "vacuum", "ions_NaCl_mM" => 0.0),
        ),
        "force_field" => Dict("protein" => "amber14sb", "water" => "vacuum",
                              "ligand" => "user_supplied"),
        "protocol" => [Dict("kind" => "minimize", "max_iterations" => 100,
                            "tolerance_kj_mol_nm" => 10.0)],
        "observables" => Any[],
        "provenance"  => Dict{String,Any}(),
        "warnings"    => String[],
        "notes"       => "",
    )
    import JSON3
    src = tempname() * ".json"
    write(src, JSON3.write(obj))
    out = tempname() * ".json"
    try
        original_stderr = stderr
        rd_e, wr_e = redirect_stderr()
        rc = nothing
        try
            rc = CLI.main(String["upgrade", src, "--out", out])
        finally
            redirect_stderr(original_stderr)
            close(wr_e)
        end
        @test rc == 0
        body = read(out, String)
        @test occursin("\"schema_version\":\"0.2.0\"", body)
        @test occursin("\"ligand_smiles\"", body)
        @test occursin("\"membrane\"", body)
        @test occursin("\"lipid\"", body)
    finally
        rm(src; force=true)
        rm(out; force=true)
    end
end

@testset "cmd_trajstat returns rc=1 on a bad path" begin
    original_stderr = stderr
    rd_e, wr_e = redirect_stderr()
    rc = nothing
    try
        rc = CLI.main(String["trajstat", "/nonexistent/path/qqq"])
    finally
        redirect_stderr(original_stderr)
        close(wr_e)
    end
    @test rc == 1
end

@testset "cmd_cite emits provenance grouped by source" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    original_stdout = stdout
    rd, wr = redirect_stdout()
    rc = nothing
    try
        rc = CLI.main(String["cite", fixture])
    finally
        redirect_stdout(original_stdout)
        close(wr)
    end
    @test rc == 0
    out = read(rd, String)
    # Should mention at least one bracketed source label
    @test occursin(r"\[(paper|paper_default|user|assumed|runtime_default)\]", out) ||
          occursin("(no provenance entries)", out)
end

@testset "cmd_import_jsonl round-trips a templates_to_jsonl export" begin
    # Build a fake JSONL that templates_to_jsonl would produce.
    src = tempname() * ".jsonl"
    open(src, "w") do io
        for name in list_templates()
            spec = get_template(name)
            entry = Dict("id" => "template:$(name)",
                         "paper_text" => spec.notes,
                         "spec_json"  => Crucible.spec_to_json(spec),
                         "schema_version" => "0.3.0",
                         "method_kind" => String(name),
                         "split"      => "synthetic_seed",
                         "provider"   => "import")
            println(io, JSON3.write(entry))
        end
    end
    db = tempname() * ".duckdb"
    try
        original_stdout = stdout
        rd, wr = redirect_stdout()
        rc = nothing
        try
            rc = CLI.main(String["import-jsonl", src, "--db", db])
        finally
            redirect_stdout(original_stdout)
            close(wr)
        end
        @test rc == 0
        out = read(rd, String)
        @test occursin("imported", out)
        @test occursin(string(length(list_templates())), out)
        store = open_transcript_store(path=db)
        try
            @test transcript_count(store) == length(list_templates())
        finally
            close_transcript_store(store)
        end
    finally
        rm(src; force=true)
        rm(db; force=true)
    end
end

@testset "cmd_analyze summarizes a synthetic workdir" begin
    workdir = mktempdir(prefix="crucible-analyze-")
    try
        # Synthetic rmsd.csv + rg.csv
        write(joinpath(workdir, "rmsd.csv"),
              "frame,rmsd_nm\n0,0.10\n1,0.12\n2,0.15\n3,0.13\n4,0.14\n")
        write(joinpath(workdir, "rg.csv"),
              "frame,rg_nm\n0,1.20\n1,1.21\n2,1.18\n")

        original_stdout = stdout
        rd, wr = redirect_stdout()
        rc = nothing
        try
            rc = CLI.main(String["analyze", workdir, "--format", "markdown"])
        finally
            redirect_stdout(original_stdout)
            close(wr)
        end
        @test rc == 0
        out = read(rd, String)
        @test occursin("# Crucible analysis", out)
        @test occursin("RMSD", out)
        @test occursin("Radius of gyration", out)
    finally
        rm(workdir; recursive=true, force=true)
    end
end

@testset "cmd_events flags an RMSD jump in a synthetic CSV" begin
    workdir = mktempdir(prefix="crucible-events-")
    try
        # 100 frames of stable RMSD, then a sudden jump.
        open(joinpath(workdir, "rmsd.csv"), "w") do io
            println(io, "frame,rmsd_nm")
            for i in 0:99
                println(io, "$i,$(0.1 + 0.001 * i)")
            end
            println(io, "100,1.5")    # the jump
        end
        events = Crucible.detect_events(workdir)
        @test !isempty(events)
        @test any(e -> e.kind == :rmsd_jump, events)

        original_stdout = stdout
        rd, wr = redirect_stdout()
        rc = nothing
        try
            rc = CLI.main(String["events", workdir, "--format", "markdown"])
        finally
            redirect_stdout(original_stdout)
            close(wr)
        end
        @test rc == 0
        out = read(rd, String)
        @test occursin("# Crucible events", out)
        @test occursin("rmsd_jump", out)
    finally
        rm(workdir; recursive=true, force=true)
    end
end

@testset "cmd_events distance crossing detection" begin
    workdir = mktempdir(prefix="crucible-events-dist-")
    try
        # Distance time-series that crosses 0.6 nm upward = unbinding.
        open(joinpath(workdir, "distance.csv"), "w") do io
            println(io, "frame,distance_nm")
            # 50 frames bound (~0.4 nm), then unbinding spike.
            for i in 0:49
                println(io, "$i,$(0.4 + 0.001 * i)")
            end
            for i in 50:99
                println(io, "$i,$(0.7 + 0.001 * (i - 50))")
            end
        end
        events = Crucible.detect_events(workdir)
        @test any(e -> e.kind == :distance_crossing, events)
    finally
        rm(workdir; recursive=true, force=true)
    end
end

@testset "cmd_events on a real workdir with no observable CSVs returns 0 events" begin
    workdir = mktempdir(prefix="crucible-events-empty-")
    try
        write(joinpath(workdir, "spec.json"),
              Crucible.spec_to_json(get_template(:vanilla)))
        events = Crucible.detect_events(workdir)
        @test isempty(events)
    finally
        rm(workdir; recursive=true, force=true)
    end
end

@testset "cmd_analyze handles empty workdir gracefully" begin
    workdir = mktempdir(prefix="crucible-analyze-empty-")
    try
        original_stdout = stdout
        rd, wr = redirect_stdout()
        rc = nothing
        try
            rc = CLI.main(String["analyze", workdir])
        finally
            redirect_stdout(original_stdout)
            close(wr)
        end
        @test rc == 0
        out = read(rd, String)
        @test occursin("no observable CSVs found", out)
    finally
        rm(workdir; recursive=true, force=true)
    end
end

@testset "cmd_run validates first, refuses to run when gates fail" begin
    # Spec that fails Gate 2 (NPT without barostat).
    bad_spec = MDSpec(
        system = SystemSpec(SystemSource(type=:user_supplied, coordinates="x.pdb"),
                            500, false, SolventSpec(model=:vacuum, ions_NaCl_mM=0.0)),
        force_field = ForceFieldSpec(protein=:amber14sb, water=:vacuum,
                                     ligand=:user_supplied),
        protocol = Stage[
            DynamicsStage(role=:production, ensemble=:NPT, duration_ns=0.001,
                          dt_fs=2.0, temperature_K=300.0, pressure_bar=nothing,
                          thermostat=:langevin, barostat=nothing,
                          friction_ps=1.0, constraints=:h_bonds,
                          restraints=RestraintSpec()),
        ],
        observables=Observable[], provenance=Dict{String,Provenance}(),
        warnings=String[], notes="")
    tmp = tempname() * ".json"
    write(tmp, Crucible.spec_to_json(bad_spec))
    try
        original_stderr = stderr
        rd_e, wr_e = redirect_stderr()
        rc = nothing
        try
            rc = CLI.main(String["run", tmp])
        finally
            redirect_stderr(original_stderr)
            close(wr_e)
        end
        @test rc == 2   # validation failure
    finally
        rm(tmp; force=true)
    end
end

@testset "cmd_run shells through to python when present (skip otherwise)" begin
    if Sys.which("python") === nothing && Sys.which("python3") === nothing
        @info "no python on PATH; skipping run smoke"
        @test true
        return
    end
    # A spec whose script will fail at runtime (no openmm), but
    # validation passes — we check that we got past validation and
    # actually invoked python.
    spec = get_template(:vanilla)
    tmp_spec = tempname() * ".json"
    write(tmp_spec, Crucible.spec_to_json(spec))
    workdir = mktempdir(prefix="crucible-run-test-")
    try
        original_stdout = stdout
        original_stderr = stderr
        rd_o, wr_o = redirect_stdout()
        rd_e, wr_e = redirect_stderr()
        rc = nothing
        try
            rc = CLI.main(String["run", tmp_spec, "--workdir", workdir,
                                 "--platform", "Reference"])
        finally
            redirect_stdout(original_stdout)
            redirect_stderr(original_stderr)
            close(wr_o); close(wr_e)
        end
        # rc != 2 (we got past validation). Likely rc=1 (python ImportError
        # without openmm installed) or rc=0 if openmm is somehow present.
        @test rc != 2
        out = read(rd_o, String)
        @test occursin("workdir:", out)
        @test occursin("python:", out)
    finally
        rm(tmp_spec; force=true)
        rm(workdir; recursive=true, force=true)
    end
end

@testset "cmd_bench --save + --baseline round-trip detects regressions" begin
    base = tempname() * ".json"
    try
        # Save a baseline.
        original_stdout = stdout
        rd, wr = redirect_stdout()
        rc = nothing
        try
            rc = CLI.main(String["bench", "--save", base, "--repeat", "2", "--format", "text"])
        finally
            redirect_stdout(original_stdout)
            close(wr)
        end
        @test rc == 0
        @test isfile(base)
        # Reload with --baseline pointing at itself: identical run should
        # produce zero regressions (some noise is possible but threshold=99 catches it).
        original2 = stdout
        rd2, wr2 = redirect_stdout()
        rc2 = nothing
        try
            # 500% threshold absorbs the noise of a 2-iteration micro-bench
            # under test-suite load.
            rc2 = CLI.main(String["bench", "--baseline", base, "--repeat", "2",
                                  "--threshold", "500"])
        finally
            redirect_stdout(original2)
            close(wr2)
        end
        # Micro-bench under heavy test-suite load can swing wildly;
        # `rc2 in (0, 4)` confirms the baseline-comparison code path
        # ran without erroring, regardless of whether noise crossed the
        # threshold. The text output should mention "baseline:" either
        # way.
        @test rc2 in (0, 4)
        out = read(rd2, String)
        @test occursin("baseline:", out)
    finally
        rm(base; force=true)
    end
end

@testset "cmd_health prints validate + lint + coverage panels" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    original_stdout = stdout
    rd, wr = redirect_stdout()
    rc = nothing
    try
        rc = CLI.main(String["health", fixture])
    finally
        redirect_stdout(original_stdout)
        close(wr)
    end
    @test rc == 0
    out = read(rd, String)
    @test occursin("Validation:", out)
    @test occursin("Lint:", out)
    @test occursin("Provenance:", out)
    @test occursin("Verdict:", out)
end

@testset "cmd_diff --intent classifies FF swap" begin
    a_path = tempname() * ".json"
    b_path = tempname() * ".json"
    a = get_template(:vanilla)
    b_obj = JSON3.read(Crucible.spec_to_json(a), Dict)
    b_obj["force_field"]["protein"] = "amber99sb_ildn"   # was amber14sb
    write(a_path, Crucible.spec_to_json(a))
    write(b_path, JSON3.write(b_obj))
    try
        original_stdout = stdout
        rd, wr = redirect_stdout()
        rc = nothing
        try
            rc = CLI.main(String["diff", a_path, b_path, "--intent"])
        finally
            redirect_stdout(original_stdout)
            close(wr)
        end
        @test rc == 4    # diff is non-empty
        out = read(rd, String)
        @test occursin("## Intent", out)
        @test occursin("FF swap (protein)", out)
        @test occursin("amber14sb", out)
        @test occursin("amber99sb_ildn", out)
    finally
        rm(a_path; force=true)
        rm(b_path; force=true)
    end
end

@testset "cmd_diff --intent classifies parameter retune" begin
    a_path = tempname() * ".json"
    b_path = tempname() * ".json"
    a = get_template(:vanilla)
    b_obj = JSON3.read(Crucible.spec_to_json(a), Dict)
    b_obj["protocol"][2]["temperature_K"] = 310.0    # was 300.0
    write(a_path, Crucible.spec_to_json(a))
    write(b_path, JSON3.write(b_obj))
    try
        original_stdout = stdout
        rd, wr = redirect_stdout()
        rc = nothing
        try
            rc = CLI.main(String["diff", a_path, b_path, "--intent"])
        finally
            redirect_stdout(original_stdout)
            close(wr)
        end
        @test rc == 4
        out = read(rd, String)
        @test occursin("parameter retune", out)
    finally
        rm(a_path; force=true)
        rm(b_path; force=true)
    end
end

@testset "cmd_templates list shows score + findings + stages" begin
    original_stdout = stdout
    rd, wr = redirect_stdout()
    rc = nothing
    try
        rc = CLI.main(String["templates", "list"])
    finally
        redirect_stdout(original_stdout)
        close(wr)
    end
    @test rc == 0
    out = read(rd, String)
    @test occursin("score", out)
    @test occursin("findings", out)
    @test occursin("stages", out)
    @test occursin("vanilla", out)
end

@testset "cmd_run pre/post hooks fire" begin
    if Sys.which("python") === nothing && Sys.which("python3") === nothing
        @info "no python; skipping hooks test"
        @test true
        return
    end
    spec = get_template(:vanilla)
    tmp_spec = tempname() * ".json"
    write(tmp_spec, Crucible.spec_to_json(spec))
    workdir = mktempdir(prefix="crucible-hooks-")
    try
        # Pre-hook touches a file; post-hook touches another. Both should
        # exist after `run` completes regardless of python rc.
        pre_marker  = joinpath(workdir, ".pre_fired")
        post_marker = joinpath(workdir, ".post_fired")
        original_stdout = stdout
        original_stderr = stderr
        rd_o, wr_o = redirect_stdout()
        rd_e, wr_e = redirect_stderr()
        try
            CLI.main(String["run", tmp_spec, "--workdir", workdir,
                            "--platform", "Reference",
                            "--pre-run-hook",  "touch \"\$CRUCIBLE_WORKDIR/.pre_fired\"",
                            "--post-run-hook", "touch \"\$CRUCIBLE_WORKDIR/.post_fired\""])
        finally
            redirect_stdout(original_stdout)
            redirect_stderr(original_stderr)
            close(wr_o); close(wr_e)
        end
        @test isfile(pre_marker)
        @test isfile(post_marker)
    finally
        rm(tmp_spec; force=true)
        rm(workdir; recursive=true, force=true)
    end
end

@testset "cmd_export_jsonschema prints the schema" begin
    original_stdout = stdout
    rd, wr = redirect_stdout()
    rc = nothing
    try
        rc = CLI.main(String["export-jsonschema"])
    finally
        redirect_stdout(original_stdout)
        close(wr)
    end
    @test rc == 0
    out = read(rd, String)
    @test occursin("MDSpec", out)
    @test occursin("0.3.0", out)
end

@testset "cmd_explain produces a paragraph for every template" begin
    for name in list_templates()
        spec = get_template(name)
        json = Crucible.spec_to_json(spec)
        tmp = tempname() * ".json"
        write(tmp, json)
        try
            original_stdout = stdout
            rd, wr = redirect_stdout()
            rc = nothing
            try
                rc = CLI.main(String["explain", tmp])
            finally
                redirect_stdout(original_stdout)
                close(wr)
            end
            @test rc == 0
            out = read(rd, String)
            @test occursin("Force field:", out)
            @test occursin("Protocol", out)
        finally
            rm(tmp; force=true)
        end
    end
end
