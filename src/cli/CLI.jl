# Crucible CLI — a thin Julia driver that exposes the pipeline as subcommands.
#
# Invoked via the `bin/crucible` shell wrapper; this module is also callable
# directly as `julia --project src/cli/CLI.jl <subcommand> [args...]`.
#
# Subcommands:
#   transpile <source-kind> <source> [--out spec.json] [--provider recorded:fixture.json]
#   validate <spec.json>
#   render <spec.json> --backend openmm|molly --out script.{py,jl}
#   advise <spec.json> [--budget-hours 6]
#   walkthrough <source-kind> <source>    end-to-end (offline if --provider recorded:...)

module CLI

using Crucible
using Crucible: spec_to_json, spec_from_json
import JSON3

const HELP_TEXT = """
crucible — Julia drug-discovery sim transpiler

Usage:
  crucible transpile     <source-kind> <source> [--out spec.json]
                                                [--provider recorded:<fixture>]
                                                [--provider anthropic]
  crucible validate      <spec.json> [--backend openmm|molly]
  crucible render        <spec.json> --backend openmm|molly --out <script>
  crucible advise        <spec.json> [--budget-hours N] [--backend openmm|molly]
  crucible summarize     <spec.json>                # Markdown summary of MDSpec
  crucible walkthrough   <source-kind> <source>

source-kind: notes | pdf | arxiv | biorxiv

Examples:
  crucible transpile pdf  ./paper.pdf --provider recorded:test/fixtures/recorded_anthropic_spec.json
  crucible validate spec.json
  crucible render   spec.json --backend openmm --out run.py
  crucible advise   spec.json --budget-hours 6
  crucible walkthrough notes "AMBER ff14SB ... 100 ns NPT ... TIP3P"
"""

# -----------------------------------------------------------------------------
# Argument helpers

function _parse_kw_args(args::Vector{String})
    kwargs = Dict{String,String}()
    positional = String[]
    i = 1
    while i <= length(args)
        a = args[i]
        if startswith(a, "--")
            key = String(a[3:end])
            if i + 1 <= length(args) && !startswith(args[i+1], "--")
                kwargs[key] = args[i+1]
                i += 2
            else
                kwargs[key] = "true"
                i += 1
            end
        else
            push!(positional, a)
            i += 1
        end
    end
    positional, kwargs
end

function _adapter(kind::AbstractString)
    kind == "notes"   ? NotesAdapter() :
    kind == "pdf"     ? PDFAdapter() :
    kind == "arxiv"   ? ArxivAdapter() :
    kind == "biorxiv" ? BioRxivAdapter() :
    error("unknown source-kind: $(kind) (expected notes|pdf|arxiv|biorxiv)")
end

function _provider(spec_str::AbstractString)
    if startswith(spec_str, "recorded:")
        path = spec_str[length("recorded:")+1:end]
        return RecordedProvider(path)
    elseif spec_str == "anthropic" || spec_str == "claude"
        return AnthropicProvider()
    end
    error("unknown provider: $(spec_str) (expected anthropic|recorded:<path>)")
end

function _backend(name::AbstractString)
    name == "openmm" ? OpenMMBackend() :
    name == "molly"  ? MollyBackend()  :
    error("unknown backend: $(name)")
end

# -----------------------------------------------------------------------------
# Subcommands

function cmd_transpile(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 2 && error("usage: transpile <source-kind> <source> [--out path] [--provider ...]")
    source_kind, source = pos[1], pos[2]
    provider_str = get(kw, "provider", "anthropic")

    paper = ingest(_adapter(source_kind), source)
    provider = _provider(provider_str)
    result = transpile(provider, paper.body_text)

    if result.spec === nothing
        println(stderr, "transpile produced no spec:")
        println(stderr, "  ", result.raw_response)
        return 1
    end

    out_path = get(kw, "out", "")
    if isempty(out_path)
        println(result.spec_json)
    else
        write(out_path, result.spec_json)
        println(stderr, "wrote: $(out_path) ($(filesize(out_path)) bytes)")
    end
    0
end

function cmd_validate(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: validate <spec.json> [--backend openmm|molly] [--format text|markdown]")
    spec_json = read(pos[1], String)
    spec = spec_from_json(spec_json)
    backend = haskey(kw, "backend") ? _backend(kw["backend"]) :
              route_backend(spec; available=[OpenMMBackend(), MollyBackend()]).backend
    report = Crucible.run_validation(spec_json, spec, backend)
    fmt = get(kw, "format", "text")
    if fmt == "markdown"
        print(render(MarkdownRenderer(), spec))
        print(render(MarkdownRenderer(), report))
    else
        println("backend: ", Crucible.backend_name(backend))
        println("ok:      ", report.ok)
        for w in report.warnings; println("warn:    ", w); end
        for e in report.errors;   println("error:   ", e); end
    end
    report.ok ? 0 : 2
end

function cmd_render(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: render <spec.json> --backend openmm|molly --out <script>")
    spec_json = read(pos[1], String)
    spec = spec_from_json(spec_json)
    backend_name = get(kw, "backend", "openmm")
    backend = _backend(backend_name)
    out_path = get(kw, "out", backend_name == "openmm" ? "run.py" : "run.jl")
    script = Crucible.render_script(backend, spec; output_dir=dirname(abspath(out_path)))
    write(out_path, script)
    println(stderr, "wrote: $(out_path) ($(filesize(out_path)) bytes)")
    0
end

function cmd_advise(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: advise <spec.json> [--budget-hours N] [--backend openmm|molly]")
    spec = spec_from_json(read(pos[1], String))
    budget_hours = parse(Float64, get(kw, "budget-hours", "6"))
    backend_name = Symbol(get(kw, "backend", "openmm"))
    rec = Crucible.advise(spec; budget_hours=budget_hours, backend_name=backend_name)
    if rec.chosen !== nothing
        c = rec.chosen
        println("chosen:  $(c.gpu)")
        println("runtime: $(round(c.runtime_hours; digits=2)) h")
        println("cost:    \$$(round(c.on_demand_usd; digits=2))")
        println("reason:  $(rec.chosen_reason)")
        println("gcp:     $(c.gcp_command)")
        println("aws:     $(c.aws_command)")
    end
    for w in rec.warnings; println("warn:    ", w); end
    rec.requires_confirmation ? 3 : 0
end

function cmd_summarize(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: summarize <spec.json>")
    spec = spec_from_json(read(pos[1], String))
    print(render(MarkdownRenderer(), spec))
    0
end

function cmd_walkthrough(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 2 && error("usage: walkthrough <source-kind> <source>")
    source_kind, source = pos[1], pos[2]
    provider_str = get(kw, "provider",
        joinpath(@__DIR__, "..", "..", "test", "fixtures", "recorded_anthropic_spec.json")
        |> p -> "recorded:" * p)

    println("=" ^ 60)
    println("crucible walkthrough")
    println("=" ^ 60)

    paper = ingest(_adapter(source_kind), source)
    println("\n[1] ingested: kind=$(paper.source_kind), bytes=$(length(paper.body_text))")

    result = transpile(_provider(provider_str), paper.body_text)
    if result.spec === nothing
        println(stderr, "[2] transpile failed: ", result.raw_response)
        return 1
    end
    println("[2] transpiled via $(result.provider_name)")

    backends = [OpenMMBackend(), MollyBackend()]
    choice = route_backend(result.spec; available=backends)
    report = Crucible.run_validation(result.spec_json, result.spec, choice.backend)
    println("[3] validated: ok=$(report.ok), backend=$(Crucible.backend_name(choice.backend))")

    rec = Crucible.advise(result.spec; budget_hours=6.0,
                                       backend_name=Crucible.backend_name(choice.backend))
    if rec.chosen !== nothing
        println("[4] cloud:  $(rec.chosen.gpu) ~\$$(round(rec.chosen.on_demand_usd; digits=2))")
    end

    workdir = mktempdir(prefix="crucible-cli-")
    job = Crucible.prepare(choice.backend, result.spec, workdir)
    println("[5] rendered: $(job.script_path)")
    0
end

# -----------------------------------------------------------------------------
# Dispatcher

function main(args::Vector{String}=ARGS)::Int
    if isempty(args) || args[1] in ("-h", "--help", "help")
        println(HELP_TEXT)
        return 0
    end
    cmd, rest = args[1], args[2:end]
    try
        if     cmd == "transpile";   return cmd_transpile(rest)
        elseif cmd == "validate";    return cmd_validate(rest)
        elseif cmd == "render";      return cmd_render(rest)
        elseif cmd == "advise";      return cmd_advise(rest)
        elseif cmd == "summarize";   return cmd_summarize(rest)
        elseif cmd == "walkthrough"; return cmd_walkthrough(rest)
        else
            println(stderr, "unknown subcommand: $(cmd)")
            println(stderr, HELP_TEXT)
            return 2
        end
    catch err
        println(stderr, "error: $(err)")
        return 1
    end
end

end # module CLI
