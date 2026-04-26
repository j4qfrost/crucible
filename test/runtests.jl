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
end
