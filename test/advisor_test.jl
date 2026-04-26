using Test
using Crucible

function _good_spec()
    fixture = joinpath(@__DIR__, "fixtures", "known_good_spec.json")
    Crucible.spec_from_json(read(fixture, String))
end

@testset "cloud advisor" begin
    spec = _good_spec()
    rec = Crucible.advise(spec; budget_hours=6.0, backend_name=:openmm)
    @test !isempty(rec.candidates)
    @test rec.chosen !== nothing
    # 30k atoms × 10 ns finishes on L4 in <6 h
    @test rec.chosen.gpu in ("T4", "L4", "A10G", "A100_40GB", "H100")
    @test rec.chosen.runtime_hours <= 6.0 + 1e-6

    # Force a long run — should require confirmation
    long_proto = vcat(
        spec.protocol[1:3],
        [Crucible.DynamicsStage(role=:production, ensemble=:NPT, duration_ns=200.0,
            dt_fs=2.0, temperature_K=300.0, pressure_bar=1.0,
            thermostat=:langevin, barostat=:monte_carlo, friction_ps=1.0,
            constraints=:h_bonds, restraints=Crucible.RestraintSpec())],
    )
    long_spec = MDSpec(system=spec.system, force_field=spec.force_field,
                       protocol=long_proto, observables=spec.observables,
                       provenance=spec.provenance, warnings=spec.warnings,
                       notes=spec.notes)
    rec2 = Crucible.advise(long_spec; budget_hours=24.0, backend_name=:openmm)
    @test rec2.requires_confirmation
    @test any(occursin("50 ns", w) for w in rec2.warnings)
end

@testset "advisor candidates carry Azure entries" begin
    spec = _good_spec()
    rec = Crucible.advise(spec; budget_hours=24.0, backend_name=:openmm)
    @test !isempty(rec.candidates)
    # Every candidate should have an azure_instance string (some may be
    # "no Azure entry" placeholders; we just want the field to exist)
    for c in rec.candidates
        @test isa(c.azure_instance, AbstractString)
        @test isa(c.azure_command, AbstractString)
    end
    # At least one candidate has a real Azure VM SKU
    @test any(occursin("Standard_NC", c.azure_instance) for c in rec.candidates)
end
