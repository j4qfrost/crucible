using Test
using Crucible

# v2 IR scaffolding: Martini coarse-grained protein FFs.

function _martini_spec(; protein=:martini3, dt_fs=20.0)
    sys = SystemSpec(
        SystemSource(type=:user_supplied, topology="cg.top",
                     coordinates="cg.gro"),
        2_000, false,
        SolventSpec(model=:vacuum, ions_NaCl_mM=0.0))
    ff = ForceFieldSpec(protein=protein, water=:vacuum, ligand=:user_supplied)
    proto = Stage[
        MinimizeStage(),
        DynamicsStage(role=:production, ensemble=:NVT, duration_ns=1.0,
                      dt_fs=dt_fs, temperature_K=310.0,
                      thermostat=:langevin, friction_ps=1.0,
                      constraints=:none, restraints=RestraintSpec()),
    ]
    MDSpec(system=sys, force_field=ff, protocol=proto,
           observables=Observable[],
           provenance=Dict{String,Provenance}(),
           warnings=String[], notes="Martini CG demo")
end

@testset "Martini protein FFs in allowlist + features" begin
    for ff in (:martini3, :martini2_2)
        @test ff in Crucible.PROTEIN_FF_ALLOWLIST
        @test ff in Crucible.CG_PROTEIN_FF
    end
end

@testset "Martini spec round-trips through JSON" begin
    spec = _martini_spec()
    json = Crucible.spec_to_json(spec)
    @test occursin("martini3", json)
    spec2 = Crucible.spec_from_json(json)
    @test spec2.force_field.protein == :martini3
end

@testset "schema accepts martini3 in protein enum + 20 fs dt" begin
    json = Crucible.spec_to_json(_martini_spec())
    r = Crucible.gate_schema(json)
    @test r.ok
end

@testset "semantic gate rejects atomistic water with Martini" begin
    spec = _martini_spec()
    bad_sys = SystemSpec(spec.system.source, spec.system.n_atoms_estimate,
                         spec.system.has_ligand,
                         SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0))
    bad_ff = ForceFieldSpec(protein=:martini3, water=:TIP3P,
                            ligand=:user_supplied)
    bad = MDSpec(system=bad_sys, force_field=bad_ff, protocol=spec.protocol,
                 observables=spec.observables, provenance=spec.provenance,
                 warnings=String[], notes="")
    r = Crucible.gate_semantic(bad)
    @test !r.ok
    @test any(occursin("incoherent", e) || occursin("Martini", e) for e in r.errors)
end

@testset "atomistic spec still rejects 25 fs timestep" begin
    spec = _martini_spec()
    bad_ff = ForceFieldSpec(protein=:amber14sb, water=:vacuum,
                            ligand=:user_supplied)
    bad = MDSpec(system=spec.system, force_field=bad_ff, protocol=spec.protocol,
                 observables=spec.observables, provenance=spec.provenance,
                 warnings=String[], notes="")
    r = Crucible.gate_semantic(bad)
    @test !r.ok    # 20 fs > 5 fs cap for atomistic
end

@testset "Martini at 25 fs is fine" begin
    spec = _martini_spec(dt_fs=25.0)
    r = Crucible.gate_semantic(spec)
    @test r.ok
end

@testset "Martini at 100 fs hits the CG hard cap" begin
    spec = _martini_spec(dt_fs=100.0)
    # JSON schema at 30 fs cap will catch this first
    json = Crucible.spec_to_json(spec)
    r = Crucible.gate_schema(json)
    @test !r.ok
end

@testset "OpenMM renderer emits NotImplementedError stub for Martini" begin
    script = Crucible.render_script(OpenMMBackend(), _martini_spec();
                                     output_dir="/tmp/martini-test")
    @test occursin("coarse-grained force field", script)
    @test occursin("NotImplementedError", script)
    @test occursin("martinize2", script)
end

@testset "CG features expose :coarse_grain" begin
    feats = Crucible.required_features(_martini_spec())
    @test :coarse_grain in feats
end
