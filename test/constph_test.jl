using Test
using Crucible

# v2 IR scaffolding: constant-pH MD. Round-trip + validation only — the
# renderer emits a NotImplementedError stub.

function _ph_spec()
    sys = SystemSpec(
        SystemSource(type=:user_supplied, coordinates="x.pdb"),
        500, false,
        SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0),
        ProtonationSpec(pH=6.5,
                        titrating_residues=["resname HIS", "resid 35"],
                        transition_attempt_per_ps=10.0,
                        salt_concentration_M=0.15),
    )
    ff = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                        ligand=:user_supplied)
    proto = Stage[
        MinimizeStage(),
        DynamicsStage(role=:production, ensemble=:NVT, duration_ns=0.1,
                      dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
                      friction_ps=1.0, constraints=:h_bonds,
                      restraints=RestraintSpec()),
    ]
    MDSpec(system=sys, force_field=ff, protocol=proto,
           observables=Observable[],
           provenance=Dict{String,Provenance}(),
           warnings=String[], notes="constant-pH MD demo")
end

@testset "ProtonationSpec construction defaults" begin
    p = ProtonationSpec()
    @test p.pH == 7.0
    @test p.transition_attempt_per_ps == 0.0
    @test p.salt_concentration_M == 0.15
    @test isempty(p.titrating_residues)
end

@testset "SystemSpec carries optional protonation field" begin
    s = _ph_spec().system
    @test s.protonation !== nothing
    @test s.protonation.pH == 6.5
    @test length(s.protonation.titrating_residues) == 2
end

@testset "Backwards-compat: SystemSpec without protonation kw" begin
    s = SystemSpec(SystemSource(type=:user_supplied, coordinates="x.pdb"),
                   100, false,
                   SolventSpec(model=:vacuum, ions_NaCl_mM=0.0))
    @test s.protonation === nothing
end

@testset "constph round-trips through JSON" begin
    spec = _ph_spec()
    json = Crucible.spec_to_json(spec)
    @test occursin("protonation", json)
    @test occursin("\"pH\":6.5", json)
    spec2 = Crucible.spec_from_json(json)
    @test spec2.system.protonation !== nothing
    @test spec2.system.protonation.pH == 6.5
    @test spec2.system.protonation.titrating_residues == ["resname HIS", "resid 35"]
end

@testset "schema accepts protonation block" begin
    json = Crucible.spec_to_json(_ph_spec())
    r = Crucible.gate_schema(json)
    @test r.ok
end

@testset "schema accepts null protonation" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    spec = Crucible.spec_from_json(read(fixture, String))
    @test spec.system.protonation === nothing
end

@testset "semantic gate rejects empty titrating_residues" begin
    spec = _ph_spec()
    bad_sys = SystemSpec(spec.system.source, spec.system.n_atoms_estimate,
                         spec.system.has_ligand, spec.system.solvent,
                         ProtonationSpec(pH=7.0, titrating_residues=String[],
                                         transition_attempt_per_ps=10.0,
                                         salt_concentration_M=0.15))
    bad = MDSpec(system=bad_sys, force_field=spec.force_field,
                 protocol=spec.protocol, observables=spec.observables,
                 provenance=spec.provenance, warnings=String[], notes="")
    r = Crucible.gate_semantic(bad)
    @test !r.ok
    @test any(occursin("titrating_residues is empty", e) for e in r.errors)
end

@testset "constph features present + OpenMM supports them" begin
    feats = Crucible.required_features(_ph_spec())
    @test :constph in feats
    @test :titration in feats
    @test :constph in Crucible.supported_features(OpenMMBackend())
end

@testset "OpenMM renderer emits NotImplementedError stub" begin
    script = Crucible.render_script(OpenMMBackend(), _ph_spec();
                                     output_dir="/tmp/ph-test")
    @test occursin("constant-pH MD (v2 scaffolding stub)", script)
    @test occursin("NotImplementedError", script)
    @test occursin("openmm-constph", script)
end
