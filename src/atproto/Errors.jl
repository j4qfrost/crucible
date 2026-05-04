# AT Protocol error type. status==0 is reserved for local validation failures
# (no HTTP call was made).

struct ATProtoError <: Exception
    status::Int
    endpoint::String
    body::String
    error_code::Union{Nothing,String}
    message::Union{Nothing,String}
end

function ATProtoError(status::Int, endpoint::AbstractString, body::AbstractString)
    code, msg = nothing, nothing
    if !isempty(body)
        try
            parsed = JSON3.read(body, Dict{String,Any})
            code = haskey(parsed, "error") ? String(parsed["error"]) : nothing
            msg  = haskey(parsed, "message") ? String(parsed["message"]) : nothing
        catch
            # body wasn't JSON; leave code/msg as nothing
        end
    end
    ATProtoError(status, String(endpoint), String(body), code, msg)
end

function Base.showerror(io::IO, e::ATProtoError)
    print(io, "ATProtoError on ", e.endpoint, ": HTTP ", e.status)
    if e.error_code !== nothing
        print(io, " (", e.error_code, ")")
    end
    if e.message !== nothing
        print(io, ": ", e.message)
    end
end
