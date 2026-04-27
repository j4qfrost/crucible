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

@testset "every template round-trips through JSON unchanged" begin
    for name in list_templates()
        spec = get_template(name)
        json = Crucible.spec_to_json(spec)
        spec2 = Crucible.spec_from_json(json)
        json2 = Crucible.spec_to_json(spec2)
        @test json == json2
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
