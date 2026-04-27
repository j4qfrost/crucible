using Test
using Crucible

# Heavy-lift v1.5: membrane / lipid bilayer system support.

function _membrane_spec()
    MDSpec(
        system = SystemSpec(
            SystemSource(type=:user_supplied, topology="m.parm7", coordinates="m.rst7"),
            45_000, false,
            SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0,
                        membrane=LipidBilayer(composition=:POPC, n_lipids=128,
                                              chol_mol_fraction=0.0)),
        ),
        force_field = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                                     ligand=:user_supplied, lipid=:lipid21),
        protocol = Stage[
            MinimizeStage(),
            DynamicsStage(role=:equilibrate, ensemble=:NPT, duration_ns=0.5,
                          dt_fs=2.0, temperature_K=310.0, pressure_bar=1.0,
                          thermostat=:langevin, barostat=:monte_carlo,
                          friction_ps=1.0, constraints=:h_bonds,
                          restraints=RestraintSpec()),
            DynamicsStage(role=:production, ensemble=:NPT, duration_ns=1.0,
                          dt_fs=2.0, temperature_K=310.0, pressure_bar=1.0,
                          thermostat=:langevin, barostat=:monte_carlo,
                          friction_ps=1.0, constraints=:h_bonds,
                          restraints=RestraintSpec()),
        ],
        observables = Observable[],
        provenance = Dict{String,Provenance}(),
        warnings = String[], notes = "POPC bilayer demo")
end

@testset "LipidBilayer construction" begin
    b = LipidBilayer(composition=:POPC, n_lipids=128)
    @test b.composition == :POPC
    @test b.n_lipids == 128
    @test b.chol_mol_fraction == 0.0
end

@testset "SolventSpec carries membrane" begin
    s = SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0,
                    membrane=LipidBilayer(composition=:DPPC, n_lipids=64))
    @test s.membrane !== nothing
    @test s.membrane.composition == :DPPC
end

@testset "ForceFieldSpec carries lipid" begin
    f = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                       ligand=:user_supplied, lipid=:charmm36_lipid)
    @test f.lipid == :charmm36_lipid
end

@testset "membrane round-trip through JSON" begin
    spec = _membrane_spec()
    json_str = Crucible.spec_to_json(spec)
    @test occursin("membrane", json_str)
    @test occursin("POPC", json_str)
    @test occursin("lipid21", json_str)
    spec2 = Crucible.spec_from_json(json_str)
    @test spec2.system.solvent.membrane !== nothing
    @test spec2.system.solvent.membrane.composition == :POPC
    @test spec2.force_field.lipid == :lipid21
end

@testset "membrane required_features includes :membrane and :anisotropic_barostat" begin
    feats = Crucible.required_features(_membrane_spec())
    @test :membrane in feats
    @test :anisotropic_barostat in feats
end

@testset "schema accepts membrane spec" begin
    json_str = Crucible.spec_to_json(_membrane_spec())
    r = Crucible.gate_schema(json_str)
    @test r.ok
end

@testset "semantic gate rejects membrane without lipid FF" begin
    spec = _membrane_spec()
    bad_ff = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                            ligand=:user_supplied, lipid=nothing)
    bad = MDSpec(system=spec.system, force_field=bad_ff, protocol=spec.protocol,
                 observables=spec.observables, provenance=spec.provenance,
                 warnings=String[], notes="")
    r = Crucible.gate_semantic(bad)
    @test !r.ok
    @test any(occursin("force_field.lipid is null", e) for e in r.errors)
end

@testset "semantic gate rejects membrane in vacuum/implicit" begin
    spec = _membrane_spec()
    bad_sys = SystemSpec(spec.system.source, spec.system.n_atoms_estimate, false,
        SolventSpec(model=:vacuum, ions_NaCl_mM=0.0,
                    membrane=spec.system.solvent.membrane))
    bad_ff = ForceFieldSpec(protein=:amber14sb, water=:vacuum,
                            ligand=:user_supplied, lipid=:lipid21)
    bad = MDSpec(system=bad_sys, force_field=bad_ff, protocol=spec.protocol,
                 observables=spec.observables, provenance=spec.provenance,
                 warnings=String[], notes="")
    r = Crucible.gate_semantic(bad)
    @test !r.ok
end

@testset "semantic gate flags chol fraction without mixed composition" begin
    spec = _membrane_spec()
    bad_sys = SystemSpec(spec.system.source, spec.system.n_atoms_estimate, false,
        SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0,
                    membrane=LipidBilayer(composition=:POPC, n_lipids=128,
                                          chol_mol_fraction=0.3)))
    bad = MDSpec(system=bad_sys, force_field=spec.force_field,
        protocol=spec.protocol, observables=spec.observables,
        provenance=spec.provenance, warnings=String[], notes="")
    r = Crucible.gate_semantic(bad)
    @test r.ok    # warning, not error
    @test any(occursin("ignored when composition", w) for w in r.warnings)
end

@testset "OpenMM renderer emits MonteCarloMembraneBarostat for membranes" begin
    script = Crucible.render_script(OpenMMBackend(), _membrane_spec();
                                     output_dir="/tmp/mem-test")
    @test occursin("MonteCarloMembraneBarostat", script)
    @test occursin("XYIsotropic", script)
    @test occursin("ZFree", script)
    @test occursin("amber14/lipid21.xml", script)
end

@testset "non-membrane spec still uses MonteCarloBarostat" begin
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    spec = Crucible.spec_from_json(read(fixture, String))
    @test spec.system.solvent.membrane === nothing
    script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp/nomem-test")
    @test occursin("_baro = MonteCarloBarostat(", script)
    @test !occursin("MonteCarloMembraneBarostat", script)
end
