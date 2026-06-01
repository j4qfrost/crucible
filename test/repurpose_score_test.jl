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
end
