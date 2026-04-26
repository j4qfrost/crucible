# Observables — post-run readers for the CSVs the OpenMM renderer emits.
#
# The rendered Python script writes rmsd.csv / rmsf.csv / rg.csv via mdtraj.
# These functions load them back into Julia for further analysis without
# requiring Plots.jl or any heavy plotting deps.
#
# CSV format (single-header, comma-separated):
#   rmsd.csv → frame,rmsd_nm
#   rmsf.csv → atom_index,rmsf_nm
#   rg.csv   → frame,rg_nm

"""
    read_observable_csv(path) -> Tuple{Vector{Int},Vector{Float64}}

Read a two-column observable CSV (frame|atom_index, value). Returns the
two columns as separate vectors. Empty file or wrong-shape file returns
empty vectors — never throws on routine input issues, only on missing path.
"""
function read_observable_csv(path::AbstractString)::Tuple{Vector{Int},Vector{Float64}}
    isfile(path) || error("read_observable_csv: file not found: $(path)")
    indices = Int[]
    values  = Float64[]
    open(path, "r") do io
        seen_header = false
        for line in eachline(io)
            line = strip(line)
            isempty(line) && continue
            if !seen_header
                seen_header = true
                continue
            end
            parts = split(line, ',')
            length(parts) < 2 && continue
            try
                push!(indices, parse(Int, strip(parts[1])))
                push!(values,  parse(Float64, strip(parts[2])))
            catch
                # skip malformed row
            end
        end
    end
    indices, values
end

"""
    summarize_observable(path) -> NamedTuple

Quick stats on an observable CSV: count, min, max, mean, last value.
Useful for CLI-level health checks on a finished run.
"""
function summarize_observable(path::AbstractString)
    idx, vals = read_observable_csv(path)
    n = length(vals)
    n == 0 && return (count=0, min=NaN, max=NaN, mean=NaN, last=NaN)
    (count=n, min=minimum(vals), max=maximum(vals),
     mean=sum(vals)/n, last=vals[end])
end
