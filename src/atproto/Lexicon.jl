# Hand-rolled validator for the AT Proto-flavored JSON Schema subset that the
# four vendored hekate lexicons actually use. Not a general JSON Schema
# implementation. Returns a Vector of (path, message, severity) tuples.

const _SCHEMAS_DIR = joinpath(@__DIR__, "schemas")

# memoize lexicon parses
const _LEXICON_CACHE = Dict{String, Dict{String,Any}}()

const _AT_URI_REGEX = r"^at://[^/]+/[^/]+/[^/]+$"
const _URI_REGEX = r"^[A-Za-z][A-Za-z0-9+.\-]*:"

struct Violation
    path::String
    message::String
    severity::Symbol  # :error | :warning
end

function load_lexicon(name::AbstractString)::Dict{String,Any}
    n = String(name)
    if haskey(_LEXICON_CACHE, n)
        return _LEXICON_CACHE[n]
    end
    path = joinpath(_SCHEMAS_DIR, "$(n).json")
    isfile(path) || throw(ArgumentError("lexicon not found: $(path)"))
    parsed = JSON3.read(read(path, String), Dict{String,Any})
    _LEXICON_CACHE[n] = parsed
    parsed
end

# Resolve a local ref like "#geoPoint" against a lexicon's defs table.
function _resolve_ref(lexicon::Dict{String,Any}, ref::AbstractString)
    startswith(ref, "#") || throw(ArgumentError("non-local refs not supported: $(ref)"))
    name = String(ref[2:end])
    defs = lexicon["defs"]
    haskey(defs, name) || throw(ArgumentError("ref target not found: $(ref)"))
    defs[name]
end

function _is_datetime(s::AbstractString)
    try
        # Accept Z, +00:00, fractional seconds, etc. Just probe Dates.
        # Strip a trailing Z or ±HH:MM for tryparse, since DateTime parser
        # doesn't grok offsets.
        body = s
        m = match(r"^(.+?)(Z|[+-]\d{2}:?\d{2})$", String(s))
        if m !== nothing
            body = m.captures[1]
        end
        # Accept fractional seconds (3 or 6 digits)
        for fmt in ("yyyy-mm-ddTHH:MM:SS.sss", "yyyy-mm-ddTHH:MM:SS", "yyyy-mm-ddTHH:MM:SS.s")
            try
                Dates.DateTime(String(body), Dates.DateFormat(fmt))
                return true
            catch
            end
        end
        return false
    catch
        return false
    end
end

# Walk a single schema fragment (object/string/array/integer/...) against a
# value, accumulating violations.
function _walk!(violations::Vector{Violation}, lex::Dict{String,Any},
                schema::Dict{String,Any}, value, path::String)
    t = get(schema, "type", "")

    if t == "ref"
        ref = get(schema, "ref", "")
        target = _resolve_ref(lex, ref)
        return _walk!(violations, lex, target, value, path)
    end

    if t == "object"
        if !(value isa AbstractDict)
            push!(violations, Violation(path, "expected object, got $(typeof(value))", :error))
            return violations
        end
        for req in get(schema, "required", String[])
            req_s = String(req)
            if !haskey(value, req_s) || value[req_s] === nothing
                push!(violations, Violation("$(path).$(req_s)", "required field missing", :error))
            end
        end
        for (prop, sub_schema) in get(schema, "properties", Dict{String,Any}())
            prop_s = String(prop)
            if haskey(value, prop_s) && value[prop_s] !== nothing
                _walk!(violations, lex, Dict{String,Any}(sub_schema), value[prop_s],
                       isempty(path) ? prop_s : "$(path).$(prop_s)")
            end
        end
        return violations
    end

    if t == "string"
        if !(value isa AbstractString)
            push!(violations, Violation(path, "expected string, got $(typeof(value))", :error))
            return violations
        end
        s = String(value)
        if haskey(schema, "minLength") && length(s) < schema["minLength"]
            push!(violations, Violation(path,
                "string shorter than minLength=$(schema["minLength"])", :error))
        end
        if haskey(schema, "maxLength") && length(s) > schema["maxLength"]
            push!(violations, Violation(path,
                "string longer than maxLength=$(schema["maxLength"]) (got $(length(s)))", :error))
        end
        if haskey(schema, "enum")
            allowed = [String(x) for x in schema["enum"]]
            if !(s in allowed)
                push!(violations, Violation(path,
                    "value $(repr(s)) not in enum [$(join(allowed, ", "))]", :error))
            end
        end
        if haskey(schema, "knownValues")
            allowed = [String(x) for x in schema["knownValues"]]
            if !(s in allowed)
                push!(violations, Violation(path,
                    "value $(repr(s)) not in knownValues (warn-only)", :warning))
            end
        end
        if haskey(schema, "format")
            fmt = String(schema["format"])
            if fmt == "at-uri" && match(_AT_URI_REGEX, s) === nothing
                push!(violations, Violation(path, "invalid at-uri: $(repr(s))", :error))
            elseif fmt == "datetime" && !_is_datetime(s)
                push!(violations, Violation(path, "invalid datetime: $(repr(s))", :error))
            elseif fmt == "uri" && match(_URI_REGEX, s) === nothing
                push!(violations, Violation(path, "invalid uri: $(repr(s))", :error))
            end
        end
        return violations
    end

    if t == "integer" || t == "number"
        if !(value isa Real) || (t == "integer" && !(value isa Integer))
            push!(violations, Violation(path, "expected $(t), got $(typeof(value))", :error))
            return violations
        end
        if haskey(schema, "minimum") && value < schema["minimum"]
            push!(violations, Violation(path,
                "value $(value) below minimum=$(schema["minimum"])", :error))
        end
        if haskey(schema, "maximum") && value > schema["maximum"]
            push!(violations, Violation(path,
                "value $(value) above maximum=$(schema["maximum"])", :error))
        end
        return violations
    end

    if t == "array"
        if !(value isa AbstractVector)
            push!(violations, Violation(path, "expected array, got $(typeof(value))", :error))
            return violations
        end
        if haskey(schema, "minLength") && length(value) < schema["minLength"]
            push!(violations, Violation(path,
                "array shorter than minLength=$(schema["minLength"])", :error))
        end
        if haskey(schema, "maxLength") && length(value) > schema["maxLength"]
            push!(violations, Violation(path,
                "array longer than maxLength=$(schema["maxLength"]) (got $(length(value)))", :error))
        end
        if haskey(schema, "items")
            item_schema = Dict{String,Any}(schema["items"])
            for (i, v) in enumerate(value)
                _walk!(violations, lex, item_schema, v, "$(path)[$(i)]")
            end
        end
        return violations
    end

    if t == "boolean"
        if !(value isa Bool)
            push!(violations, Violation(path, "expected boolean, got $(typeof(value))", :error))
        end
        return violations
    end

    # Unknown type — don't fail the user; record a warning so we notice.
    push!(violations, Violation(path, "unsupported schema type $(repr(t))", :warning))
    violations
end

"""
    validate_record(name, record) -> Vector{Violation}

Validate a record against the named lexicon (one of "venue", "slot",
"recurrence", "event"). Returns an empty vector on success.
"""
function validate_record(name::AbstractString, record::AbstractDict)::Vector{Violation}
    lex = load_lexicon(name)
    main = Dict{String,Any}(lex["defs"]["main"])
    record_schema = Dict{String,Any}(main["record"])
    violations = Violation[]
    _walk!(violations, lex, record_schema, record, "")
    violations
end

function has_errors(violations::Vector{Violation})
    any(v -> v.severity == :error, violations)
end

function format_violations(violations::Vector{Violation})
    isempty(violations) && return "(none)"
    io = IOBuffer()
    for v in violations
        tag = v.severity == :error ? "error" : "warn"
        path = isempty(v.path) ? "<root>" : v.path
        println(io, "  [$(tag)] $(path): $(v.message)")
    end
    String(take!(io))
end

"""
    assert_valid!(name, record)

Throw an ATProtoError (status=0, endpoint="<local-validation>") if there are
any error-severity violations.
"""
function assert_valid!(name::AbstractString, record::AbstractDict)
    violations = validate_record(name, record)
    if has_errors(violations)
        msg = "lexicon validation failed for app.hekate.$(name):\n" *
              format_violations(violations)
        throw(ATProtoError(0, "<local-validation>", msg, "ValidationError", msg))
    end
    violations
end
