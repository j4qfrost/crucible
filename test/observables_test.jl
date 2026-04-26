using Test
using Crucible

@testset "read_observable_csv basic" begin
    path = tempname() * ".csv"
    open(path, "w") do io
        write(io, "frame,rmsd_nm\n")
        write(io, "0,0.10\n")
        write(io, "1,0.15\n")
        write(io, "2,0.18\n")
    end
    idx, vals = read_observable_csv(path)
    @test idx == [0, 1, 2]
    @test vals == [0.10, 0.15, 0.18]
    rm(path; force=true)
end

@testset "read_observable_csv tolerates malformed rows" begin
    path = tempname() * ".csv"
    open(path, "w") do io
        write(io, "frame,rmsd_nm\n")
        write(io, "0,0.10\n")
        write(io, "BAD,not-a-number\n")
        write(io, "2,0.18\n")
    end
    idx, vals = read_observable_csv(path)
    @test idx == [0, 2]    # malformed row skipped
    @test vals == [0.10, 0.18]
    rm(path; force=true)
end

@testset "summarize_observable" begin
    path = tempname() * ".csv"
    open(path, "w") do io
        write(io, "frame,rmsd_nm\n")
        write(io, "0,0.10\n")
        write(io, "1,0.20\n")
        write(io, "2,0.30\n")
    end
    s = summarize_observable(path)
    @test s.count == 3
    @test s.min == 0.10
    @test s.max == 0.30
    @test s.mean ≈ 0.20
    @test s.last == 0.30
    rm(path; force=true)
end

@testset "summarize_observable empty file returns zero count" begin
    path = tempname() * ".csv"
    open(path, "w") do io
        write(io, "frame,rmsd_nm\n")
    end
    s = summarize_observable(path)
    @test s.count == 0
    rm(path; force=true)
end

@testset "read_observable_csv errors on missing path" begin
    @test_throws ErrorException read_observable_csv("/nonexistent/path.csv")
end
