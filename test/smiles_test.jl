using Test
using Crucible

# Heavy-lift v1: SMILES → topology pipeline through the IR + backend.
# These tests verify the IR plumbing and validation rules — they do NOT
# require openff-toolkit to be installed (subprocess-availability is its
# own test in parameterizer_test.jl).

function _smiles_spec()
    MDSpec(
        system = SystemSpec(
            SystemSource(type=:smiles, ligand_smiles="CCO"),
            9, true,
            SolventSpec(model=:vacuum, ions_NaCl_mM=0.0),
        ),
        force_field = ForceFieldSpec(protein=:amber14sb, water=:vacuum,
                                     ligand=:openff_sage_2_2_0),
        protocol = Stage[
            MinimizeStage(max_iterations=100),
            DynamicsStage(role=:production, ensemble=:NVT, duration_ns=0.001,
                          dt_fs=2.0, temperature_K=300.0, thermostat=:langevin,
                          friction_ps=1.0, constraints=:h_bonds,
                          restraints=RestraintSpec()),
        ],
        observables=Observable[],
        provenance=Dict{String,Provenance}(),
        warnings=String[], notes="ethanol from SMILES",
    )
end

function _protein_ligand_spec()
    MDSpec(
        system = SystemSpec(
            SystemSource(type=:protein_ligand, pdb_id="1ubq",
                         ligand_smiles="Cc1ccccc1"),
            1500, true,
            SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0),
        ),
        force_field = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                                     ligand=:openff_sage_2_2_0),
        protocol = Stage[
            MinimizeStage(max_iterations=100),
            DynamicsStage(role=:equilibrate, ensemble=:NPT, duration_ns=0.5,
                          dt_fs=2.0, temperature_K=300.0, pressure_bar=1.0,
                          thermostat=:langevin, barostat=:monte_carlo,
                          friction_ps=1.0, constraints=:h_bonds,
                          restraints=RestraintSpec()),
        ],
        observables=Observable[],
        provenance=Dict{String,Provenance}(),
        warnings=String[], notes="toluene + 1ubq",
    )
end

@testset "SystemSource carries ligand_smiles" begin
    s = SystemSource(type=:smiles, ligand_smiles="CCO")
    @test s.type == :smiles
    @test s.ligand_smiles == "CCO"
    @test s.topology === nothing
    @test s.coordinates === nothing
end

@testset "MDSpec round-trip preserves ligand_smiles + protein_ligand" begin
    spec = _protein_ligand_spec()
    json_str = Crucible.spec_to_json(spec)
    @test occursin("protein_ligand", json_str)
    @test occursin("Cc1ccccc1", json_str)
    spec2 = Crucible.spec_from_json(json_str)
    @test spec2.system.source.type == :protein_ligand
    @test spec2.system.source.pdb_id == "1ubq"
    @test spec2.system.source.ligand_smiles == "Cc1ccccc1"
end

@testset "schema accepts smiles source + ligand_smiles" begin
    json_str = Crucible.spec_to_json(_smiles_spec())
    r = Crucible.gate_schema(json_str)
    @test r.ok
end

@testset "schema rejects smiles source without ligand_smiles" begin
    bad_spec = MDSpec(
        system = SystemSpec(
            SystemSource(type=:smiles, ligand_smiles=nothing),  # bug
            9, true, SolventSpec(model=:vacuum, ions_NaCl_mM=0.0),
        ),
        force_field = ForceFieldSpec(protein=:amber14sb, water=:vacuum,
                                     ligand=:openff_sage_2_2_0),
        protocol = Stage[MinimizeStage(max_iterations=100)],
        observables=Observable[],
        provenance=Dict{String,Provenance}(),
        warnings=String[], notes="",
    )
    json_str = Crucible.spec_to_json(bad_spec)
    r = Crucible.gate_schema(json_str)
    @test !r.ok
end

@testset "semantic gate flags :user_supplied ligand FF with SMILES source" begin
    spec = _smiles_spec()
    bad = MDSpec(
        system = spec.system,
        force_field = ForceFieldSpec(protein=:amber14sb, water=:vacuum,
                                     ligand=:user_supplied),  # incoherent
        protocol = spec.protocol, observables = spec.observables,
        provenance = spec.provenance, warnings = String[], notes = "",
    )
    r = Crucible.gate_semantic(bad)
    @test !r.ok
    @test any(occursin("incoherent", e) for e in r.errors)
end

@testset "semantic gate accepts good SMILES spec" begin
    r = Crucible.gate_semantic(_smiles_spec())
    @test r.ok
end

@testset "OpenMMBackend renders SMILES source as AMBER load" begin
    backend = OpenMMBackend()
    spec = _smiles_spec()
    script = Crucible.render_script(backend, spec; output_dir="/tmp/smiles-test")
    @test occursin("ligand.parm7", script)
    @test occursin("ligand.rst7", script)
    @test occursin("AmberPrmtopFile", script)
    @test occursin("_use_amber = True", script)
end

@testset "OpenMMBackend renders protein_ligand source with SMIRNOFF" begin
    backend = OpenMMBackend()
    spec = _protein_ligand_spec()
    script = Crucible.render_script(backend, spec; output_dir="/tmp/pl-test")
    @test occursin("PDBFixer(pdbid=\"1ubq\")", script)
    @test occursin("Molecule.from_smiles(\"Cc1ccccc1\"", script)
    @test occursin("SMIRNOFFTemplateGenerator", script)
    @test occursin("registerTemplateGenerator", script)
    @test occursin("am1bcc", script)
end

@testset "loadability gate allows SMILES sources" begin
    omm = OpenMMBackend()
    r = Crucible.gate_loadability(omm, _smiles_spec())
    @test r.ok
    r2 = Crucible.gate_loadability(omm, _protein_ligand_spec())
    @test r2.ok
end

@testset "loadability gate rejects user_supplied + SMILES combination" begin
    omm = OpenMMBackend()
    bad = MDSpec(
        system = SystemSpec(
            SystemSource(type=:smiles, ligand_smiles="CCO"),
            9, true, SolventSpec(model=:vacuum, ions_NaCl_mM=0.0)),
        force_field = ForceFieldSpec(protein=:amber14sb, water=:vacuum,
                                     ligand=:user_supplied),
        protocol = Stage[MinimizeStage()],
        observables = Observable[],
        provenance = Dict{String,Provenance}(),
        warnings = String[], notes = "")
    r = Crucible.gate_loadability(omm, bad)
    @test !r.ok
end
