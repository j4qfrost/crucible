using Test
using Crucible

# Heavy-lift v1.5: metadynamics scaffolding (collective variables + bias).

function _metad_spec()
    cvs = CollectiveVariable[
        CollectiveVariable(kind=:distance, name="d1", selection="1,2", sigma=0.1),
        CollectiveVariable(kind=:dihedral, name="phi",
                           selection="5,7,9,15", sigma=0.5),
    ]
    MDSpec(
        system = SystemSpec(
            SystemSource(type=:user_supplied, coordinates="x.pdb"),
            500, false,
            SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0),
        ),
        force_field = ForceFieldSpec(protein=:amber14sb, water=:TIP3P,
                                     ligand=:user_supplied),
        protocol = Stage[
            MinimizeStage(),
            MetadynamicsStage(cvs=cvs, bias_height_kj_mol=1.5,
                              bias_deposit_period_ps=2.0,
                              duration_ns=0.1, well_tempered=true,
                              bias_factor=8.0, ensemble=:NVT,
                              temperature_K=300.0),
        ],
        observables = Observable[],
        provenance = Dict{String,Provenance}(),
        warnings = String[], notes = "metad demo")
end

@testset "MetadynamicsStage construction" begin
    cvs = [CollectiveVariable(kind=:distance, name="d", selection="1,2")]
    s = MetadynamicsStage(cvs=cvs)
    @test length(s.cvs) == 1
    @test s.well_tempered == true
    @test s.bias_factor == 10.0
end

@testset "metadynamics round-trip through JSON" begin
    spec = _metad_spec()
    json_str = Crucible.spec_to_json(spec)
    @test occursin("metadynamics", json_str)
    @test occursin("dihedral", json_str)
    spec2 = Crucible.spec_from_json(json_str)
    s = spec2.protocol[2]
    @test s isa MetadynamicsStage
    @test length(s.cvs) == 2
    @test s.cvs[1].kind == :distance
    @test s.cvs[2].kind == :dihedral
    @test s.bias_factor == 8.0
end

@testset "schema accepts metadynamics stage" begin
    json_str = Crucible.spec_to_json(_metad_spec())
    r = Crucible.gate_schema(json_str)
    @test r.ok
end

@testset "semantic gate rejects rmsd CV without reference" begin
    bad_cvs = [CollectiveVariable(kind=:rmsd, name="r", selection="all",
                                  reference=nothing)]
    spec = _metad_spec()
    bad = MDSpec(system=spec.system, force_field=spec.force_field,
        protocol=Stage[MetadynamicsStage(cvs=bad_cvs, ensemble=:NVT,
                                         temperature_K=300.0)],
        observables=Observable[], provenance=spec.provenance,
        warnings=String[], notes="")
    r = Crucible.gate_semantic(bad)
    @test !r.ok
    @test any(occursin("reference PDB", e) for e in r.errors)
end

@testset "semantic gate rejects well_tempered with bias_factor=1" begin
    spec = _metad_spec()
    bad = MDSpec(system=spec.system, force_field=spec.force_field,
        protocol=Stage[MetadynamicsStage(cvs=spec.protocol[2].cvs,
            well_tempered=true, bias_factor=1.0, ensemble=:NVT,
            temperature_K=300.0)],
        observables=Observable[], provenance=spec.provenance,
        warnings=String[], notes="")
    r = Crucible.gate_semantic(bad)
    @test !r.ok
end

@testset "semantic gate warns on wrong CV atom-group count" begin
    spec = _metad_spec()
    bad_cvs = [CollectiveVariable(kind=:distance, name="d", selection="1,2,3")]
    bad = MDSpec(system=spec.system, force_field=spec.force_field,
        protocol=Stage[MetadynamicsStage(cvs=bad_cvs, ensemble=:NVT,
                                          temperature_K=300.0)],
        observables=Observable[], provenance=spec.provenance,
        warnings=String[], notes="")
    r = Crucible.gate_semantic(bad)
    @test r.ok
    @test any(occursin("atom groups", w) for w in r.warnings)
end

@testset "metad features expose plumed + biased_sampling" begin
    feats = Crucible.required_features(_metad_spec())
    @test :metadynamics in feats
    @test :biased_sampling in feats
    @test :plumed in feats
end

@testset "OpenMM renders metadynamics with PLUMED" begin
    script = Crucible.render_script(OpenMMBackend(), _metad_spec();
                                     output_dir="/tmp/metad-test")
    @test occursin("openmmplumed", script)
    @test occursin("PlumedForce", script)
    @test occursin("METAD", script)
    @test occursin("BIASFACTOR=8.0", script)
    @test occursin("d1: DISTANCE", script)
    @test occursin("phi: TORSION", script)
end
