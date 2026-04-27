using Test
using Crucible

# v1.5.1+ polish: provenance_coverage + lint utilities.

function _bare_spec()
    MDSpec(
        system = SystemSpec(
            SystemSource(type=:user_supplied, coordinates="x.pdb"),
            500, false, SolventSpec(model=:vacuum, ions_NaCl_mM=0.0)),
        force_field = ForceFieldSpec(protein=:amber14sb, water=:vacuum,
                                     ligand=:user_supplied),
        protocol = Stage[
            MinimizeStage(),
            DynamicsStage(role=:production, ensemble=:NVT, duration_ns=0.0005,
                          dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
                          friction_ps=1.0, constraints=:h_bonds,
                          restraints=RestraintSpec()),
        ],
        observables = Observable[
            Observable(type=:rmsd, selection="protein", stride_ps=10.0),
        ],
        provenance = Dict{String,Provenance}(),
        warnings = String[], notes = "")
end

@testset "provenance_coverage on bare spec is 0%" begin
    rep = provenance_coverage(_bare_spec())
    @test rep.fields_with_provenance == 0
    @test rep.total_numeric_fields > 0
    @test isempty(rep.by_source)
    @test length(rep.missing_paths) == rep.total_numeric_fields
end

@testset "provenance_coverage tallies entries by source" begin
    spec = _bare_spec()
    prov = Dict{String,Provenance}(
        "system.n_atoms_estimate"        => Provenance(:paper),
        "system.solvent.ions_NaCl_mM"    => Provenance(:paper_default),
        "protocol[2].temperature_K"      => Provenance(:assumed),
        "protocol[2].dt_fs"              => Provenance(:runtime_default),
    )
    spec_with_prov = MDSpec(system=spec.system, force_field=spec.force_field,
        protocol=spec.protocol, observables=spec.observables,
        provenance=prov, warnings=String[], notes="")
    rep = provenance_coverage(spec_with_prov)
    @test rep.fields_with_provenance == 4
    @test rep.by_source[:paper] == 1
    @test rep.by_source[:paper_default] == 1
    @test rep.by_source[:assumed] == 1
    @test rep.by_source[:runtime_default] == 1
end

@testset "coverage_score weights are sane" begin
    spec = _bare_spec()
    # 100% paper-cited
    paths = Crucible._enumerate_provenance_keys(spec)
    full = Dict{String,Provenance}(p => Provenance(:paper) for p in paths)
    full_spec = MDSpec(system=spec.system, force_field=spec.force_field,
        protocol=spec.protocol, observables=spec.observables,
        provenance=full, warnings=String[], notes="")
    @test coverage_score(provenance_coverage(full_spec)) ≈ 1.0

    # 100% assumed
    asm = Dict{String,Provenance}(p => Provenance(:assumed) for p in paths)
    asm_spec = MDSpec(system=spec.system, force_field=spec.force_field,
        protocol=spec.protocol, observables=spec.observables,
        provenance=asm, warnings=String[], notes="")
    @test 0.39 < coverage_score(provenance_coverage(asm_spec)) < 0.41

    # nothing
    @test coverage_score(provenance_coverage(_bare_spec())) ≈ 0.0
end

@testset "lint flags short production + missing equilibration" begin
    rep = lint(_bare_spec())
    rules = Set(f.rule for f in rep.findings)
    @test :no_equilibration in rules
    @test :short_production in rules
end

@testset "lint flags rmsd observable without trajectory" begin
    rep = lint(_bare_spec())
    @test any(f.rule == :rmsd_no_trajectory for f in rep.findings)
end

@testset "lint flags low provenance coverage" begin
    rep = lint(_bare_spec())
    @test any(f.rule == :provenance_low for f in rep.findings)
end

@testset "lint clean spec has fewer findings" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    spec = Crucible.spec_from_json(read(fixture, String))
    rep = lint(spec)
    # The known-good fixture has equilibrate + production + a real protocol;
    # it should have NO no_equilibration + NO short_production findings.
    rules = Set(f.rule for f in rep.findings)
    @test :no_equilibration ∉ rules
    @test :short_production ∉ rules
end

@testset "lint flags FEP shape issues" begin
    spec = _bare_spec()
    bad_fep = FEPStage(target_selection="resname LIG",
                       lambda_windows=[0.0, 0.5, 1.0],   # only 3
                       duration_per_window_ns=0.05,       # short
                       ensemble=:NVT, pressure_bar=nothing,
                       temperature_K=300.0)
    spec_fep = MDSpec(system=spec.system, force_field=spec.force_field,
        protocol=Stage[MinimizeStage(),
                       DynamicsStage(role=:equilibrate, ensemble=:NVT,
                           duration_ns=0.5, dt_fs=2.0, temperature_K=300.0,
                           thermostat=:langevin, friction_ps=1.0,
                           constraints=:h_bonds, restraints=RestraintSpec()),
                       bad_fep],
        observables=Observable[], provenance=Dict{String,Provenance}(),
        warnings=String[], notes="")
    rep = lint(spec_fep)
    rules = Set(f.rule for f in rep.findings)
    @test :fep_few_windows in rules
    @test :fep_short_window in rules
end

@testset "lint flags REMD with too few replicas" begin
    spec = _bare_spec()
    bad_remd = REMDStage(temperature_ladder_K=[300.0, 320.0],
                         duration_per_replica_ns=0.5, ensemble=:NVT)
    spec_remd = MDSpec(system=spec.system, force_field=spec.force_field,
        protocol=Stage[MinimizeStage(), bad_remd],
        observables=Observable[], provenance=Dict{String,Provenance}(),
        warnings=String[], notes="")
    rep = lint(spec_remd)
    @test any(f.rule == :remd_few_replicas for f in rep.findings)
end

@testset "lint never throws on the empty protocol fixture" begin
    fixture = joinpath(@__DIR__, "fixtures", "recorded_anthropic_spec.json")
    spec = Crucible.spec_from_json(read(fixture, String))
    rep = lint(spec)
    @test rep isa LintReport
end

@testset "LintReport isempty + n_findings sanity" begin
    rep = LintReport()
    @test isempty(rep)
    @test Crucible.n_findings(rep) == 0
end
