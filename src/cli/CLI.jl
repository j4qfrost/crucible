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
  crucible diff          <spec-a.json> <spec-b.json>   # Markdown diff
  crucible info                                       # capability surface
  crucible parameterize  <smiles> --out <dir> [--ff openff_sage_2_2_0]
                                              [--python python] [--name LIG]
  crucible verify        <spec.json> [--backend openmm|molly]   # gates 1-3 + render
  crucible serve         [--host 0.0.0.0] [--port 8080]         # HTTP web frontend
  crucible doctor                                                 # diagnose Python / OpenMM / OpenFF deps
  crucible coverage      <spec.json>                              # provenance coverage report
  crucible lint          <spec.json> [--format text|json]         # advisory checks
  crucible templates     list | show <name> | init <name> [--out spec.json]
  crucible snapshot      <workdir> --out <archive.tar.gz> [--max-size-mb N]
  crucible restore       <archive.tar.gz> --out <dest-dir> [--no-verify]
  crucible fmt           <spec.json> [--in-place]                # pretty-print spec
  crucible trajstat      <workdir>                                # walk + classify artifacts
  crucible upgrade       <spec.json> [--out path] [--target ver]  # forward-migrate schema
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
    length(pos) < 1 && error("usage: advise <spec.json> [--budget-hours N] [--backend openmm|molly] [--format text|json]")
    spec = spec_from_json(read(pos[1], String))
    budget_hours = parse(Float64, get(kw, "budget-hours", "6"))
    backend_name = Symbol(get(kw, "backend", "openmm"))
    rec = Crucible.advise(spec; budget_hours=budget_hours, backend_name=backend_name)
    fmt = get(kw, "format", "text")
    if fmt == "json"
        obj = Dict{String,Any}(
            "chosen" => rec.chosen === nothing ? nothing : Dict{String,Any}(
                "gpu" => rec.chosen.gpu,
                "runtime_hours" => rec.chosen.runtime_hours,
                "on_demand_usd" => rec.chosen.on_demand_usd,
                "ns_per_day"    => rec.chosen.ns_per_day,
                "gcp_instance"  => rec.chosen.gcp_instance,
                "gcp_command"   => rec.chosen.gcp_command,
                "aws_instance"  => rec.chosen.aws_instance,
                "aws_command"   => rec.chosen.aws_command,
                "azure_instance" => rec.chosen.azure_instance,
                "azure_command"  => rec.chosen.azure_command,
            ),
            "chosen_reason" => rec.chosen_reason,
            "warnings"      => rec.warnings,
            "requires_confirmation" => rec.requires_confirmation,
            "candidates" => [Dict{String,Any}(
                "gpu" => c.gpu, "ns_per_day" => c.ns_per_day,
                "runtime_hours" => c.runtime_hours,
                "on_demand_usd" => c.on_demand_usd,
            ) for c in rec.candidates],
        )
        println(JSON3.write(obj))
    else
        if rec.chosen !== nothing
            c = rec.chosen
            println("chosen:  $(c.gpu)")
            println("runtime: $(round(c.runtime_hours; digits=2)) h")
            println("cost:    \$$(round(c.on_demand_usd; digits=2))")
            println("reason:  $(rec.chosen_reason)")
            println("gcp:     $(c.gcp_command)")
            println("aws:     $(c.aws_command)")
            println("azure:   $(c.azure_command)")
        end
        for w in rec.warnings; println("warn:    ", w); end
    end
    rec.requires_confirmation ? 3 : 0
end

function cmd_info(::Vector{String})
    println("crucible — capability surface (v1.5)")
    println()
    println("Schema version:   0.1.0")
    println()
    println("Backends:")
    for (b, b_inst) in (("MollyBackend", MollyBackend()),
                        ("OpenMMBackend", OpenMMBackend()),
                        ("KineticsBackend (stub)", KineticsBackend()))
        feats = sort(collect(Crucible.supported_features(b_inst)))
        println("  ", b, ": ", join(feats, ", "))
    end
    println()
    println("Stage types:")
    println("  MinimizeStage      — energy minimization")
    println("  DynamicsStage      — vanilla MD (NVE / NVT / NPT)")
    println("  FEPStage           — alchemical free-energy (decouple / annihilate)")
    println("  REMDStage          — replica-exchange MD (T-ladder)")
    println("  MetadynamicsStage  — biased sampling with collective variables")
    println()
    println("System source types:")
    println("  :user_supplied     — BYO topology + coords")
    println("  :pdb_id / :pdb_fetch — PDBFixer auto-build (canonical residues only)")
    println("  :smiles            — pure ligand from SMILES (OpenFFParameterizer)")
    println("  :protein_ligand    — PDBFixer + SMIRNOFFTemplateGenerator at runtime")
    println()
    println("Force-field allowlists:")
    println("  protein:  amber14sb | amber99sb_ildn | amber03 | charmm36m | opls_aam")
    println("  water:    TIP3P | TIP4P_EW | SPC_E | implicit_GBSA | vacuum")
    println("  ligand:   user_supplied | gaff2 | openff_sage_2_2_0")
    println("  lipid:    charmm36_lipid | lipid21 | slipids")
    println()
    println("Solvent extras:")
    println("  LipidBilayer (POPC | POPE | DPPC | mixed_POPC_chol)")
    println("  → renderer auto-switches NPT to MonteCarloMembraneBarostat (XYIsotropic, ZFree)")
    println()
    println("LLM providers:")
    println("  AnthropicProvider — Claude tool-use; needs ANTHROPIC_API_KEY")
    println("  RecordedProvider  — replays a fixture JSON (deterministic)")
    println("  LocalProvider     — OpenAI-compatible (vLLM / Ollama / llama.cpp)")
    println()
    println("Input adapters:")
    println("  PDFAdapter      — local PDF via pdftotext")
    println("  ArxivAdapter    — arXiv ID; fetches PDF when pdftotext available")
    println("  BioRxivAdapter  — bioRxiv DOI; fetches PDF when pdftotext available")
    println("  NotesAdapter    — raw text passthrough")
    println()
    println("Output renderers:")
    println("  PlutoRenderer   — inline HTML for Pluto notebooks")
    println("  MarkdownRenderer — GFM tables for CLI / PR / README")
    println("  NotebookRenderer — exports a standalone Pluto .jl")
    println("  WebRenderer     — HTTP.jl single-page UI + JSON API")
    println()
    println("Validation gates: 1) schema  2) semantic  3) loadability  4) preview  5) user-confirm")
    println()
    println("CLI subcommands: transpile validate render advise summarize diff walkthrough")
    println("                 info parameterize verify serve doctor coverage lint templates")
    println("                 snapshot restore fmt trajstat upgrade")
    println()
    println("Ligand parameterizer:")
    avail = parameterizer_available()
    println("  OpenFFParameterizer (openff-toolkit): ", avail ? "available" : "not installed")
    0
end

function cmd_diff(args::Vector{String})
    pos, _ = _parse_kw_args(args)
    length(pos) < 2 && error("usage: diff <spec-a.json> <spec-b.json>")
    a = spec_from_json(read(pos[1], String))
    b = spec_from_json(read(pos[2], String))
    print(render(MarkdownRenderer(), diff_specs(a, b)))
    isempty(diff_specs(a, b)) ? 0 : 4
end

function cmd_summarize(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: summarize <spec.json>")
    spec = spec_from_json(read(pos[1], String))
    print(render(MarkdownRenderer(), spec))
    0
end

function cmd_parameterize(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: parameterize <smiles> --out <dir> [--ff openff_sage_2_2_0] [--python python] [--name LIG]")
    smiles = pos[1]
    out_dir = get(kw, "out", "")
    isempty(out_dir) && error("--out <dir> is required")
    ff = get(kw, "ff", "openff_sage_2_2_0")
    sage_version = startswith(ff, "openff_sage_") ?
        replace(ff[length("openff_sage_")+1:end], "_" => ".") : "2.2.0"
    p = OpenFFParameterizer(
        sage_version=sage_version,
        python=get(kw, "python", "python"),
        ligand_name=get(kw, "name", "LIG"),
    )
    if !parameterizer_available(p)
        println(stderr, "error: openff-toolkit not available via $(p.python). " *
                        "Install with: pip install openff-toolkit openff-interchange rdkit")
        return 5
    end
    result = parameterize(p, smiles, out_dir)
    println("smiles:        $(result.smiles)")
    println("topology:      $(result.topology_path)")
    println("coordinates:   $(result.coordinates_path)")
    println("forcefield:    $(result.forcefield_name)")
    for (k, v) in result.metadata
        println("$(rpad(k * ":", 14))$(v)")
    end
    0
end

function cmd_verify(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: verify <spec.json> [--backend openmm|molly]")
    spec_json = read(pos[1], String)
    spec = spec_from_json(spec_json)
    backend = haskey(kw, "backend") ? _backend(kw["backend"]) :
              route_backend(spec; available=[OpenMMBackend(), MollyBackend()]).backend
    println("verify $(pos[1]) on backend=$(Crucible.backend_name(backend))")
    report = Crucible.run_validation(spec_json, spec, backend)
    println("  gates 1-3: ", report.ok ? "PASS" : "FAIL")
    for w in report.warnings; println("    warn:  ", w); end
    for e in report.errors;   println("    error: ", e); end
    if !report.ok
        return 2
    end
    workdir = mktempdir(prefix="crucible-verify-")
    try
        job = Crucible.prepare(backend, spec, workdir)
        println("  render:    OK ($(filesize(job.script_path)) bytes -> $(job.script_path))")
    catch err
        println("  render:    FAIL: $(err)")
        return 6
    end
    println("verify ok.")
    0
end

function cmd_serve(args::Vector{String})
    _, kw = _parse_kw_args(args)
    host = get(kw, "host", "0.0.0.0")
    port = parse(Int, get(kw, "port", "8080"))
    Crucible.serve_http(; host=host, port=port)
    0
end

function cmd_doctor(::Vector{String})
    println("crucible doctor — environment diagnostic")
    println("=" ^ 60)

    # Probe each optional dep. Each probe either returns the version
    # string + ok status, or a remediation hint.
    pythons = ["python", "python3"]
    py = nothing
    for cmd in pythons
        if Sys.which(cmd) !== nothing
            py = cmd
            break
        end
    end

    if py === nothing
        println("  python:               not found on PATH")
        println("    fix:                install python ≥3.10 and put it on PATH")
        println()
    else
        ver = strip(_run_capture(`$py -c "import sys; print('.'.join(map(str, sys.version_info[:3])))"`))
        println("  python:               $(py) ($(ver))")
    end

    function _probe_pkg(import_stmt::AbstractString, ver_expr::AbstractString,
                        label::AbstractString, fix::AbstractString)
        py === nothing && return nothing
        ok = false
        ver = ""
        try
            out = _run_capture(`$py -c "$import_stmt; print($ver_expr)"`)
            ver = strip(out)
            ok = !isempty(ver) && !occursin("Traceback", ver)
        catch
        end
        if ok
            println("  $(rpad(label, 22)) $(ver)")
        else
            println("  $(rpad(label, 22)) not installed")
            println("    fix:                $(fix)")
        end
        ok
    end

    _probe_pkg("import openmm", "openmm.__version__", "openmm:",
               "pip install openmm")
    _probe_pkg("from openff.toolkit import __version__ as v", "v",
               "openff-toolkit:",
               "pip install openff-toolkit openff-interchange rdkit")
    _probe_pkg("import pdbfixer", "pdbfixer.__version__", "pdbfixer:",
               "pip install pdbfixer")
    _probe_pkg("import mdtraj", "mdtraj.__version__", "mdtraj:",
               "pip install mdtraj")
    _probe_pkg("import openmmtools", "openmmtools.__version__",
               "openmmtools:",
               "pip install openmmtools  # required for FEP / REMD")
    _probe_pkg("import openmmplumed", "'(installed)'", "openmm-plumed:",
               "conda install -c conda-forge openmm-plumed plumed  # required for metadynamics")
    _probe_pkg("import openmmforcefields", "openmmforcefields.__version__",
               "openmm-forcefields:",
               "pip install openmm-forcefields  # required for :protein_ligand source")

    # GPU probe
    println()
    println("  GPU detection:")
    if Sys.which("nvidia-smi") !== nothing
        try
            out = _run_capture(`nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader`)
            for line in eachline(IOBuffer(out))
                println("    ", strip(line))
            end
        catch err
            println("    nvidia-smi present but query failed: $(err)")
        end
    else
        println("    nvidia-smi not on PATH (no NVIDIA GPU detected)")
    end

    # Crucible's own optional bits
    println()
    println("  Crucible providers:")
    println("    OpenFFParameterizer:  ", parameterizer_available() ? "available" : "not installed")
    has_anthropic = haskey(ENV, "ANTHROPIC_API_KEY") && !isempty(ENV["ANTHROPIC_API_KEY"])
    println("    ANTHROPIC_API_KEY:    ", has_anthropic ? "set" : "not set (AnthropicProvider will no-op)")
    println("    CRUCIBLE_LOCAL_ENDPOINT: ", get(ENV, "CRUCIBLE_LOCAL_ENDPOINT", "(default: http://localhost:8000/v1)"))
    println()
    println("  Verdict: ", _doctor_verdict(py))
    0
end

function _run_capture(cmd::Cmd)::String
    io = IOBuffer()
    try
        run(pipeline(cmd; stdout=io, stderr=devnull); wait=true)
        String(take!(io))
    catch
        ""
    end
end

function _doctor_verdict(py)
    py === nothing && return "broken — install python first."
    ok_count = 0
    for stmt in ("import openmm", "import openff.toolkit", "import pdbfixer",
                 "import mdtraj", "import openmmtools")
        try
            run(pipeline(`$py -c $stmt`; stdout=devnull, stderr=devnull); wait=true)
            ok_count += 1
        catch
        end
    end
    if ok_count == 5
        "all green — full v1.5 surface available"
    elseif ok_count >= 3
        "good — most of v1.0 works; some v1.5 features (FEP/REMD/metad) need extra deps"
    elseif ok_count >= 1
        "partial — IR + render works, execution mostly blocked"
    else
        "IR + LLM only — no Python deps installed"
    end
end

function cmd_coverage(args::Vector{String})
    pos, _ = _parse_kw_args(args)
    length(pos) < 1 && error("usage: coverage <spec.json>")
    spec = spec_from_json(read(pos[1], String))
    rep = Crucible.provenance_coverage(spec)
    score = Crucible.coverage_score(rep)
    println("Provenance coverage: $(rep.fields_with_provenance) / $(rep.total_numeric_fields) " *
            "($(round(100 * rep.fields_with_provenance / max(rep.total_numeric_fields, 1); digits=1))%)")
    println("Quality score:       $(round(score; digits=3))  (1.0 = all paper-cited; 0.0 = nothing)")
    println()
    if !isempty(rep.by_source)
        println("By source:")
        for (src, n) in sort(collect(rep.by_source); by = x -> -x[2])
            println("  $(rpad(string(src) * ":", 20))$(n)")
        end
    end
    if !isempty(rep.missing_paths)
        println()
        println("Missing provenance ($(length(rep.missing_paths)) fields):")
        for p in rep.missing_paths
            println("  - $(p)")
        end
    end
    0
end

function cmd_upgrade(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: upgrade <spec.json> [--out path] [--target version]")
    raw = read(pos[1], String)
    target = get(kw, "target", "0.2.0")
    upgraded = Crucible.migrate_spec_json(raw; target=target)
    out = get(kw, "out", "")
    if isempty(out)
        # Re-pretty for human readability
        println(_pretty_json(JSON3.read(upgraded, Dict)))
    else
        write(out, upgraded)
        println(stderr, "wrote: $(out) ($(filesize(out)) bytes; target schema $(target))")
    end
    0
end

function cmd_fmt(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: fmt <spec.json> [--in-place]")
    raw = read(pos[1], String)
    spec = spec_from_json(raw)
    pretty = _pretty_json(JSON3.read(spec_to_json(spec), Dict))
    if haskey(kw, "in-place")
        write(pos[1], pretty)
        println(stderr, "wrote: $(pos[1]) ($(filesize(pos[1])) bytes)")
    else
        println(pretty)
    end
    0
end

# Tiny JSON pretty-printer. Keeps output deterministic + close to what
# `jq` would produce. Trade-off: doesn't sort keys (preserves insertion
# order); good enough for human review and avoids surprising diffs.
function _pretty_json(v; indent=0, step=2)
    pad(n) = " " ^ (n * step)
    if v isa AbstractDict
        isempty(v) && return "{}"
        io = IOBuffer()
        print(io, "{\n")
        keys_v = collect(keys(v))
        for (i, k) in enumerate(keys_v)
            print(io, pad(indent + 1))
            print(io, JSON3.write(string(k)))
            print(io, ": ")
            print(io, _pretty_json(v[k]; indent=indent+1, step=step))
            i < length(keys_v) && print(io, ",")
            print(io, "\n")
        end
        print(io, pad(indent), "}")
        String(take!(io))
    elseif v isa AbstractVector
        isempty(v) && return "[]"
        # Inline short numeric/string arrays for readability.
        if all(x -> !(x isa AbstractDict) && !(x isa AbstractVector), v) &&
           length(v) <= 16
            return "[" * join((JSON3.write(x) for x in v), ", ") * "]"
        end
        io = IOBuffer()
        print(io, "[\n")
        for (i, x) in enumerate(v)
            print(io, pad(indent + 1))
            print(io, _pretty_json(x; indent=indent+1, step=step))
            i < length(v) && print(io, ",")
            print(io, "\n")
        end
        print(io, pad(indent), "]")
        String(take!(io))
    else
        JSON3.write(v)
    end
end

function cmd_trajstat(args::Vector{String})
    pos, _ = _parse_kw_args(args)
    length(pos) < 1 && error("usage: trajstat <workdir>")
    workdir = pos[1]
    isdir(workdir) || error("trajstat: not a directory: $(workdir)")
    by_kind = Dict{Symbol,Vector{String}}(:trajectory=>String[],
                                          :timeseries=>String[],
                                          :checkpoint=>String[],
                                          :spec=>String[],
                                          :script=>String[],
                                          :other=>String[])
    total_bytes = 0
    for (root, _dirs, fnames) in walkdir(workdir)
        for f in fnames
            full = joinpath(root, f)
            n = filesize(full)
            total_bytes += n
            kind = endswith(f, ".dcd") || endswith(f, ".xtc") || endswith(f, ".trr") ? :trajectory :
                   endswith(f, ".csv") || endswith(f, ".log") ? :timeseries :
                   endswith(f, ".chk") || endswith(f, ".cpt") ? :checkpoint :
                   endswith(f, "spec.json") || f == "spec.json" ? :spec :
                   endswith(f, ".py") || endswith(f, ".jl") ? :script :
                   :other
            push!(by_kind[kind], relpath(full, workdir))
        end
    end
    println("trajstat: $(workdir)")
    println("  total bytes: $(total_bytes) ($(round(total_bytes / 1024 / 1024; digits=2)) MB)")
    for kind in (:trajectory, :timeseries, :checkpoint, :spec, :script, :other)
        files = sort(by_kind[kind])
        isempty(files) && continue
        println("  $(rpad(string(kind) * ":", 14))$(length(files)) file(s)")
        for f in files
            full = joinpath(workdir, f)
            println("    $(rpad(f, 50)) $(rpad(string(filesize(full)), 12)) bytes")
        end
    end
    # mdtraj sniff (if available) for trajectory frame counts.
    if !isempty(by_kind[:trajectory])
        py = Sys.which("python") !== nothing ? "python" :
             Sys.which("python3") !== nothing ? "python3" : nothing
        if py !== nothing && _has_mdtraj(py)
            println("  trajectory frame counts (via mdtraj):")
            for f in sort(by_kind[:trajectory])
                full = joinpath(workdir, f)
                top = joinpath(workdir, "spec.json")  # if the workdir has a topology, mdtraj will fail without it; use a heuristic
                cmd = `$py -c "import mdtraj; t = mdtraj.load_dcd($(repr(full)), top=$(repr(_guess_topology(workdir)))); print(t.n_frames, t.n_atoms)"`
                out = _run_capture(cmd)
                if !isempty(out)
                    parts = split(strip(out))
                    if length(parts) == 2
                        println("    $(rpad(f, 50)) frames=$(parts[1]) atoms=$(parts[2])")
                    end
                end
            end
        end
    end
    0
end

function _has_mdtraj(py::AbstractString)
    try
        run(pipeline(`$py -c "import mdtraj"`; stdout=devnull, stderr=devnull); wait=true)
        return true
    catch
        return false
    end
end

function _guess_topology(workdir)
    for cand in ("topology.pdb", "system.pdb", "complex.pdb")
        full = joinpath(workdir, cand)
        isfile(full) && return full
    end
    # Fallback: any .pdb in the workdir
    for f in readdir(workdir)
        endswith(f, ".pdb") && return joinpath(workdir, f)
    end
    ""
end

function cmd_snapshot(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: snapshot <workdir> --out <archive.tar.gz> [--max-size-mb N]")
    workdir = pos[1]
    out = get(kw, "out", "")
    isempty(out) && error("--out <archive.tar.gz> is required")
    max_mb = haskey(kw, "max-size-mb") ? parse(Float64, kw["max-size-mb"]) : nothing
    path = Crucible.snapshot(workdir, out; max_size_mb=max_mb)
    println("wrote: $(path) ($(filesize(path)) bytes)")
    0
end

function cmd_restore(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: restore <archive.tar.gz> --out <dest-dir> [--no-verify]")
    archive = pos[1]
    out = get(kw, "out", "")
    isempty(out) && error("--out <dest-dir> is required")
    verify = !haskey(kw, "no-verify")
    dest, manifest = Crucible.restore(archive, out; verify=verify)
    println("restored to:        $(dest)")
    println("crucible version:   $(manifest.crucible_version)")
    println("schema version:     $(manifest.schema_version)")
    println("snapshot taken at:  $(manifest.created_at)")
    println("files:              $(length(manifest.files))")
    println("verified:           $(verify)")
    0
end

function cmd_templates(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    isempty(pos) && error("usage: templates list | show <name> | init <name> [--out path]")
    sub = pos[1]
    if sub == "list"
        names = list_templates()
        println("Templates ($(length(names))):")
        for n in names
            spec = get_template(n)
            println("  ", rpad(string(n), 22), strip(spec.notes))
        end
        return 0
    elseif sub == "show"
        length(pos) < 2 && error("usage: templates show <name>")
        spec = get_template(Symbol(pos[2]))
        # Pretty-print (JSON3.write doesn't pretty-print; round-trip
        # through Dict so we can hand-format).
        json = spec_to_json(spec)
        # Re-emit with indentation for human reading.
        obj = JSON3.read(json, Dict)
        println(JSON3.write(obj; allow_inf=false))
        return 0
    elseif sub == "init"
        length(pos) < 2 && error("usage: templates init <name> [--out path]")
        name = Symbol(pos[2])
        spec = get_template(name)
        json = spec_to_json(spec)
        out_path = get(kw, "out", "")
        if isempty(out_path)
            println(json)
        else
            write(out_path, json)
            println(stderr, "wrote: $(out_path) ($(filesize(out_path)) bytes)")
        end
        return 0
    else
        error("unknown templates subcommand: $(sub) (expected list|show|init)")
    end
end

function cmd_lint(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: lint <spec.json> [--format text|json]")
    spec = spec_from_json(read(pos[1], String))
    rep = Crucible.lint(spec)
    fmt = get(kw, "format", "text")
    if fmt == "json"
        obj = Dict{String,Any}(
            "findings" => [Dict("severity" => String(f.severity),
                                "rule"     => String(f.rule),
                                "path"     => f.path,
                                "message"  => f.message)
                           for f in rep.findings],
            "coverage" => Dict("total_numeric_fields"   => rep.coverage.total_numeric_fields,
                               "fields_with_provenance" => rep.coverage.fields_with_provenance,
                               "score"                  => Crucible.coverage_score(rep.coverage)),
        )
        println(JSON3.write(obj))
    else
        if isempty(rep)
            println("lint: clean — no advisories.")
        else
            println("lint: $(length(rep.findings)) finding(s)")
            for f in rep.findings
                tag = f.severity == :warn      ? "warn"   :
                      f.severity == :advisory  ? "advise" : "info"
                println("  [$(tag)] $(f.rule) @ $(f.path)")
                println("          $(f.message)")
            end
        end
        println()
        cov = rep.coverage
        score = Crucible.coverage_score(cov)
        println("provenance: $(cov.fields_with_provenance)/$(cov.total_numeric_fields) " *
                "(score $(round(score; digits=2)))")
    end
    isempty(rep) ? 0 : 0   # lint never fails the build
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
        elseif cmd == "diff";        return cmd_diff(rest)
        elseif cmd == "info";        return cmd_info(rest)
        elseif cmd == "parameterize"; return cmd_parameterize(rest)
        elseif cmd == "verify";       return cmd_verify(rest)
        elseif cmd == "serve";        return cmd_serve(rest)
        elseif cmd == "doctor";       return cmd_doctor(rest)
        elseif cmd == "coverage";     return cmd_coverage(rest)
        elseif cmd == "lint";         return cmd_lint(rest)
        elseif cmd == "templates";    return cmd_templates(rest)
        elseif cmd == "snapshot";     return cmd_snapshot(rest)
        elseif cmd == "restore";      return cmd_restore(rest)
        elseif cmd == "fmt";          return cmd_fmt(rest)
        elseif cmd == "trajstat";     return cmd_trajstat(rest)
        elseif cmd == "upgrade";      return cmd_upgrade(rest)
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
