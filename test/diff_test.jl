using Test
using Crucible

function _good_spec()
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    Crucible.spec_from_json(read(fixture, String))
end

@testset "diff_specs identity" begin
    spec = _good_spec()
    d = diff_specs(spec, spec)
    @test isempty(d)
    @test length(d) == 0
end

@testset "diff_specs detects scalar change" begin
    a = _good_spec()
    # Build a spec with one altered field (temperature in stage 2)
    new_proto = copy(a.protocol)
    s = a.protocol[2]
    @assert s isa Crucible.DynamicsStage
    new_proto[2] = Crucible.DynamicsStage(
        role=s.role, ensemble=s.ensemble, duration_ns=s.duration_ns,
        dt_fs=s.dt_fs, temperature_K=310.0,    # was 300.0
        pressure_bar=s.pressure_bar, thermostat=s.thermostat,
        barostat=s.barostat, friction_ps=s.friction_ps,
        constraints=s.constraints, restraints=s.restraints,
    )
    b = MDSpec(system=a.system, force_field=a.force_field, protocol=new_proto,
               observables=a.observables, provenance=a.provenance,
               warnings=a.warnings, notes=a.notes)
    d = diff_specs(a, b)
    @test !isempty(d)
    @test length(d.changed) >= 1
    @test any(c[1] == "protocol[2].temperature_K" && c[2] == 300.0 && c[3] == 310.0
              for c in d.changed)
end

@testset "diff_specs detects added stage" begin
    a = _good_spec()
    extra = Crucible.MinimizeStage(max_iterations=100, tolerance_kj_mol_nm=10.0)
    b = MDSpec(system=a.system, force_field=a.force_field,
               protocol=Crucible.Stage[a.protocol..., extra],
               observables=a.observables, provenance=a.provenance,
               warnings=a.warnings, notes=a.notes)
    d = diff_specs(a, b)
    @test length(d.only_in_b) == 1
    @test d.only_in_b[1][1] == "protocol[5]"
end

@testset "diff_specs Markdown render" begin
    a = _good_spec()
    new_proto = copy(a.protocol)
    s = a.protocol[2]
    new_proto[2] = Crucible.DynamicsStage(
        role=s.role, ensemble=s.ensemble, duration_ns=s.duration_ns,
        dt_fs=s.dt_fs, temperature_K=310.0,
        pressure_bar=s.pressure_bar, thermostat=s.thermostat,
        barostat=s.barostat, friction_ps=s.friction_ps,
        constraints=s.constraints, restraints=s.restraints,
    )
    b = MDSpec(system=a.system, force_field=a.force_field, protocol=new_proto,
               observables=a.observables, provenance=a.provenance,
               warnings=a.warnings, notes=a.notes)
    md = Crucible.render(MarkdownRenderer(), diff_specs(a, b))
    @test occursin("## Spec diff", md)
    @test occursin("temperature_K", md)
    @test occursin("310", md)
end
