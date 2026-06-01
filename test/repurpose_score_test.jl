# repurpose_score: the binding-plan integration point for asklepius / apotheca.
# Spec-build + gates 1-2 only — no GPU, no OpenFF, fully deterministic.

using Test
using Crucible

@testset "repurpose_score" begin
    imatinib = "Cc1ccc(NC(=O)c2ccc(CN3CCN(C)CC3)cc2)cc1Nc1nccc(-c2cccnc2)n1"

    @testset "spec_only builds a valid protein-ligand FEP plan" begin
        out = Crucible.repurpose_score("2HYY", imatinib)
        @test out["method"] == "spec_only"
        @test out["delta_g_kcal_mol"] === nothing      # never fabricated
        @test out["validation"]["ok"] == true          # gates 1-2 pass
        @test out["advise"] !== nothing                # sizing produced
        # The caller's target + ligand made it into the spec.
        spec = Crucible.spec_from_json(out["spec_json"])
        @test spec.system.source.type == :protein_ligand
        @test spec.system.source.pdb_id == "2HYY"
        @test spec.system.source.ligand_smiles == imatinib
        # It really is an FEP protocol (the binding-affinity stage).
        @test any(s -> s isa FEPStage, spec.protocol)
    end

    @testset "run=true prepares a real run, still no fabricated ΔG" begin
        out = Crucible.repurpose_score("2HYY", imatinib; run=true)
        @test out["method"] == "run_prepared"
        @test out["delta_g_kcal_mol"] === nothing
        @test occursin("crucible run", out["run_command"])
        @test isfile(joinpath(out["workdir"], "spec.json"))
    end

    @testset "bad input is rejected" begin
        @test_throws Exception Crucible.repurpose_score("2H", imatinib)   # pdb too short
        @test_throws Exception Crucible.repurpose_score("2HYY", "")       # no ligand
    end

    @testset "rendered OpenMM script keeps the ligand template + honors padding" begin
        out = Crucible.repurpose_score("2HYY", imatinib)
        spec0 = Crucible.spec_from_json(out["spec_json"])
        # Rebuild the spec with an explicit non-default solvent padding to assert it flows.
        solv = SolventSpec(model=:TIP3P, ions_NaCl_mM=150.0, padding_nm=0.7)
        sys = SystemSpec(spec0.system.source, spec0.system.n_atoms_estimate, true, solv)
        spec = MDSpec(system=sys, force_field=spec0.force_field, protocol=spec0.protocol,
                      observables=spec0.observables, provenance=spec0.provenance,
                      warnings=String[], notes="render test")
        script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp")
        # Bug 1: the ForceField built with the SMIRNOFF generator must not be rebuilt.
        @test occursin("_ff_ready = True", script)
        @test occursin("if not _use_amber and not _ff_ready:", script)
        # Bug 2: solvent.padding_nm must reach addSolvent (not a hardcoded 1.0 nm).
        @test occursin("padding=0.7*nanometer", script)
        # Bug 3: the ligand must be placed at its CRYSTAL pose (from_pdb_and_smiles),
        # not a bare generated conformer, and heterogens removed only AFTER pose capture.
        @test occursin("from_pdb_and_smiles", script)
        @test !occursin("generate_conformers", script)
        @test findfirst("from_pdb_and_smiles", script).start <
              findfirst("removeHeterogens", script).start
    end
end
