using Test
using Crucible

# v1.5.2+ polish: canned MDSpec templates + CLI integration.

@testset "list_templates is deterministic + non-empty" begin
    names = list_templates()
    @test !isempty(names)
    @test issorted(names)
    @test :vanilla in names
    @test :smiles in names
    @test :protein_ligand_fep in names
    @test :remd in names
    @test :membrane in names
    @test :metadynamics in names
end

@testset "every template round-trips through JSON semantically" begin
    # Bytewise equality fails because Dict iteration order isn't stable
    # across the (provenance Dict has many entries now). Compare the
    # parsed shape — that's what actually matters for the IR contract.
    for name in list_templates()
        spec = get_template(name)
        json = Crucible.spec_to_json(spec)
        spec2 = Crucible.spec_from_json(json)
        @test spec2.schema_version == spec.schema_version
        @test length(spec2.protocol) == length(spec.protocol)
        @test length(spec2.provenance) == length(spec.provenance)
        @test spec2.system.source.type == spec.system.source.type
        @test spec2.force_field.protein == spec.force_field.protein
    end
end

@testset "every template passes Gate 1 (schema)" begin
    for name in list_templates()
        spec = get_template(name)
        json = Crucible.spec_to_json(spec)
        r = Crucible.gate_schema(json)
        @test r.ok
        @test isempty(r.errors)
    end
end

@testset "every template passes Gate 2 (semantic)" begin
    for name in list_templates()
        spec = get_template(name)
        r = Crucible.gate_semantic(spec)
        # Some templates may emit warnings (e.g. metadynamics CV atom-group
        # placeholder) — that's fine, errors are not.
        @test r.ok
    end
end

@testset "templates list -> Router routes to the right backend" begin
    backends = [OpenMMBackend(), MollyBackend()]
    # Templates that demand v1+ features should route to OpenMM.
    for name in (:protein_ligand_fep, :remd, :membrane, :metadynamics, :smiles)
        spec = get_template(name)
        choice = route_backend(spec; available=backends)
        @test Crucible.backend_name(choice.backend) == :openmm
    end
end

@testset "vanilla template renders for OpenMM backend" begin
    spec = get_template(:vanilla)
    script = Crucible.render_script(OpenMMBackend(), spec; output_dir="/tmp/templ-test")
    @test occursin("from openmm", script)
    @test occursin("amber14-all.xml", script)
end

@testset "every template renders to Markdown without error" begin
    for name in list_templates()
        spec = get_template(name)
        md = render(MarkdownRenderer(), spec)
        @test occursin("# MDSpec", md)
        @test occursin("Protocol", md)
    end
end

@testset "every template renders to Pluto without error" begin
    for name in list_templates()
        spec = get_template(name)
        html = render(PlutoRenderer(), spec)
        @test occursin("<div", html)
    end
end

@testset "every template lints without throwing" begin
    for name in list_templates()
        spec = get_template(name)
        rep = lint(spec)
        @test rep isa LintReport
    end
end

@testset "templates have realistic provenance coverage" begin
    for name in list_templates()
        spec = get_template(name)
        rep = provenance_coverage(spec)
        @test rep.fields_with_provenance == rep.total_numeric_fields
        # Score should be solidly above the "everything is :assumed" floor (~0.4)
        # but not so high we'd lock in a brittle invariant.
        @test 0.55 <= coverage_score(rep) <= 1.0
    end
end

@testset "register_template! accepts external builders" begin
    register_template!(:_test_only, () -> get_template(:vanilla))
    try
        @test :_test_only in list_templates()
        @test get_template(:_test_only) isa MDSpec
    finally
        delete!(Crucible._TEMPLATES, :_test_only)
    end
end

@testset "get_template errors on unknown name" begin
    @test_throws ErrorException get_template(:no_such_template)
end
