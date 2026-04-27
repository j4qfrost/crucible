using Test
using Crucible

@testset "Crucible" begin
    include("spec_schema_test.jl")
    include("validation_gates_test.jl")
    include("renderer_golden_test.jl")
    include("router_test.jl")
    include("advisor_test.jl")
    include("integration_test.jl")
    include("llm_test.jl")
    include("adapters_test.jl")
    include("cli_test.jl")
    include("diff_test.jl")
    include("migrations_test.jl")
    include("observables_test.jl")
    include("parameterizer_test.jl")
    include("smiles_test.jl")
    include("fep_test.jl")
    include("web_test.jl")
end
