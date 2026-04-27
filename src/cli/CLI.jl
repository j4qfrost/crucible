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
  crucible run           <spec.json> [--workdir path] [--platform X] [--precision P]
                                     [--seed N] [--resume] [--backend openmm]   # render + execute
  crucible serve         [--host 0.0.0.0] [--port 8080]         # HTTP web frontend
  crucible doctor                                                 # diagnose Python / OpenMM / OpenFF deps
  crucible coverage      <spec.json>                              # provenance coverage report
  crucible lint          <spec.json> [--format text|json]         # advisory checks
  crucible templates     list | show <name> | init <name> [--out spec.json]
  crucible snapshot      <workdir> --out <archive.tar.gz> [--max-size-mb N]
  crucible restore       <archive.tar.gz> --out <dest-dir> [--no-verify]
  crucible fmt           <spec.json> [--in-place]                # pretty-print spec
  crucible trajstat      <workdir>                                # walk + classify artifacts
  crucible analyze       <workdir> [--format text|markdown|json]  # summarize observables
  crucible upgrade       <spec.json> [--out path] [--target ver]  # forward-migrate schema
  crucible bench         [--format text|json] [--repeat N]
                         [--save baseline.json] [--baseline base.json] [--threshold 20]
  crucible cite          <spec.json>                                # list every provenance entry
  crucible explain       <spec.json>                                # natural-language summary
  crucible export-jsonschema [--out path]                            # dump the live schema.json
  crucible audit-transcripts <db.duckdb> [--threshold 0.5] [--format text|json]  # corpus quality
  crucible import-jsonl  <file.jsonl> [--db path]                  # load training pairs into TranscriptStore
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
                "vram_gb"       => rec.chosen.vram_gb,
                "fits_system"   => rec.chosen.fits_system,
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
                "vram_gb" => c.vram_gb,
                "fits_system" => c.fits_system,
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
    println("crucible — capability surface (schema v0.3.0)")
    println()
    println("Schema version:   0.3.0")
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
    println("Observable types: rmsd, rmsf, energy, trajectory, rg, sasa, distance, hbonds")
    println()
    println("Validation gates: 1) schema  2) semantic  3) loadability  4) preview  5) user-confirm")
    println()
    println("CLI subcommands: transpile validate render advise summarize diff walkthrough")
    println("                 info parameterize verify serve doctor coverage lint templates")
    println("                 snapshot restore fmt trajstat analyze upgrade bench cite explain")
    println("                 export-jsonschema audit-transcripts import-jsonl run")
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

function cmd_run(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: run <spec.json> [--workdir path] [--platform X] [--precision P] [--seed N] [--backend openmm]")
    spec_json = read(pos[1], String)
    spec = spec_from_json(spec_json)
    backend_name = get(kw, "backend", "openmm")
    backend_name == "openmm" || error("crucible run currently supports --backend openmm only")
    backend = OpenMMBackend()

    # Validate first — don't bother launching if gates 1-3 fail.
    report = Crucible.run_validation(spec_json, spec, backend)
    if !report.ok
        println(stderr, "validation failed; refusing to run")
        for e in report.errors; println(stderr, "  error: ", e); end
        return 2
    end

    workdir = if haskey(kw, "workdir")
        kw["workdir"]
    else
        mktempdir(prefix="crucible-run-")
    end
    isdir(workdir) || mkpath(workdir)

    # Persist the spec next to the rendered script for reproducibility.
    write(joinpath(workdir, "spec.json"), spec_json)
    job = Crucible.prepare(backend, spec, workdir)
    println("workdir:        $(workdir)")
    println("script:         $(job.script_path) ($(filesize(job.script_path)) bytes)")

    # Find a python.
    py = haskey(kw, "python") ? kw["python"] :
         Sys.which("python") !== nothing ? "python" :
         Sys.which("python3") !== nothing ? "python3" :
         error("crucible run: no python on PATH; install one or pass --python /path/to/python")

    # Build the env. Don't clobber the user's existing values; --flags
    # take priority over inherited env (they're explicit).
    env = copy(ENV)
    haskey(kw, "platform")  && (env["CRUCIBLE_PLATFORM"]  = kw["platform"])
    haskey(kw, "precision") && (env["CRUCIBLE_PRECISION"] = kw["precision"])
    haskey(kw, "seed")      && (env["CRUCIBLE_SEED"]      = kw["seed"])

    # --resume: auto-find the most recent .chk in the workdir.
    if haskey(kw, "resume")
        chks = filter(f -> endswith(f, ".chk"), readdir(workdir))
        if isempty(chks)
            println(stderr, "crucible run: --resume given but no .chk files in $(workdir)")
            return 3
        end
        # Sort by mtime, take latest.
        latest = argmax(c -> stat(joinpath(workdir, c)).mtime, chks)
        env["CRUCIBLE_RESUME_FROM"] = joinpath(workdir, latest)
        println("resume from:    $(env["CRUCIBLE_RESUME_FROM"])")
    end

    println("python:         $(py)")
    println("env overrides:  ",
            join((string(k, "=", v) for (k, v) in env if startswith(k, "CRUCIBLE_") && haskey(kw, lowercase(replace(k, "CRUCIBLE_" => "")))),
                 ", "))
    println("---- script stdout ----")
    cmd = setenv(`$py $(job.script_path)`, env)
    rc = try
        run(cmd; wait=true)
        0
    catch err
        if err isa ProcessFailedException
            err.procs[1].exitcode
        else
            println(stderr, "crucible run: process error: $(err)")
            127
        end
    end
    println("---- exit $(rc) ----")
    rc
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
    # Per-platform plugin probes. OpenMM's CUDA support ships in the main
    # wheel; HIP + OpenCL are separate optional plugins.
    if py !== nothing
        try
            out = strip(_run_capture(`$py -c "import openmm; ps = [openmm.Platform.getPlatform(i).getName() for i in range(openmm.Platform.getNumPlatforms())]; print(','.join(ps))"`))
            if !isempty(out) && !occursin("Traceback", out)
                println("    OpenMM platforms:    ", out)
            end
        catch
        end
    end
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

    # GPU probe — multi-vendor.
    println()
    println("  GPU detection:")
    nvidia = Sys.which("nvidia-smi")
    rocm   = Sys.which("rocm-smi")
    intel  = Sys.which("intel_gpu_top")
    if nvidia !== nothing
        try
            out = _run_capture(`nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader`)
            for line in eachline(IOBuffer(out))
                stripped = strip(line)
                isempty(stripped) || println("    NVIDIA: ", stripped)
            end
        catch err
            println("    nvidia-smi present but query failed: $(err)")
        end
    end
    if rocm !== nothing
        try
            # rocm-smi emits a banner + per-GPU rows; --showproductname is
            # the most stable subset across ROCm versions.
            out = _run_capture(`rocm-smi --showproductname --showmeminfo vram --csv`)
            shown = false
            for line in eachline(IOBuffer(out))
                stripped = strip(line)
                # Skip header + blank lines + banner, keep card rows.
                if startswith(stripped, "card") || startswith(stripped, "GPU") ||
                   occursin("Card series", stripped)
                    println("    AMD:    ", stripped)
                    shown = true
                end
            end
            shown || println("    AMD:    rocm-smi found but no card rows parsed")
        catch err
            println("    rocm-smi present but query failed: $(err)")
        end
    end
    if intel !== nothing
        println("    Intel:  intel_gpu_top on PATH (live monitor; see `intel_gpu_top -L`)")
    end
    if nvidia === nothing && rocm === nothing && intel === nothing
        println("    no GPU SDK detected (nvidia-smi / rocm-smi / intel_gpu_top all absent)")
        println("                  → script will fall through to CPU (slow but correct)")
    end

    # Crucible's own optional bits
    println()
    println("  Crucible providers:")
    println("    OpenFFParameterizer:  ", parameterizer_available() ? "available" : "not installed")
    has_anthropic = haskey(ENV, "ANTHROPIC_API_KEY") && !isempty(ENV["ANTHROPIC_API_KEY"])
    println("    ANTHROPIC_API_KEY:    ", has_anthropic ? "set" : "not set (AnthropicProvider will no-op)")
    println("    CRUCIBLE_LOCAL_ENDPOINT: ", get(ENV, "CRUCIBLE_LOCAL_ENDPOINT", "(default: http://localhost:8000/v1)"))
    println("    CRUCIBLE_PLATFORM:    ", get(ENV, "CRUCIBLE_PLATFORM", "(default: auto = CUDA→HIP→OpenCL→CPU)"))
    println("    CRUCIBLE_PRECISION:   ", get(ENV, "CRUCIBLE_PRECISION", "(default: mixed)"))
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

function cmd_import_jsonl(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: import-jsonl <file.jsonl> [--db path]")
    src = pos[1]
    isfile(src) || error("import-jsonl: file not found: $(src)")
    db_path = get(kw, "db", Crucible.default_transcript_db())
    store = open_transcript_store(path=db_path)
    n_imported = 0
    n_skipped = 0
    try
        for line in eachline(src)
            isempty(strip(line)) && continue
            obj = try
                JSON3.read(line, Dict)
            catch err
                println(stderr, "import-jsonl: skipping malformed line: $(err)")
                n_skipped += 1
                continue
            end
            # Extract spec_json — may be nested object or string.
            spec_obj = get(obj, "spec_json", nothing)
            spec_obj === nothing && (n_skipped += 1; continue)
            spec_json = spec_obj isa AbstractString ? String(spec_obj) : JSON3.write(spec_obj)
            paper_text = String(get(obj, "paper_text", ""))

            # Synthesize the structs log_transcript expects.
            paper = Crucible.PaperRepr(
                source_kind = Symbol(get(obj, "method_kind", get(obj, "paper_kind", "imported"))),
                source_id = String(get(obj, "id", "imported:unknown")),
                title = get(obj, "paper_title", nothing),
                body_text = paper_text,
            )
            spec = nothing
            try
                spec = spec_from_json(spec_json)
            catch
                spec = nothing
            end
            result = Crucible.TranspileResult(
                spec_json, spec,
                String(get(obj, "raw_response", "")),
                Symbol(get(obj, "provider", "imported")),
                String(get(obj, "model", "")),
                Float64(get(obj, "cost_usd", 0.0)),
            )
            log_transcript(store, paper, result)
            n_imported += 1
        end
    finally
        close_transcript_store(store)
    end
    println("imported $(n_imported) entries into $(db_path)" *
            (n_skipped > 0 ? " ($(n_skipped) malformed lines skipped)" : ""))
    0
end

function cmd_export_jsonschema(args::Vector{String})
    _, kw = _parse_kw_args(args)
    schema_path = joinpath(@__DIR__, "..", "spec", "schema.json")
    body = read(schema_path, String)
    out = get(kw, "out", "")
    if isempty(out)
        print(body)
    else
        write(out, body)
        println(stderr, "wrote: $(out) ($(filesize(out)) bytes)")
    end
    0
end

function cmd_audit_transcripts(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: audit-transcripts <db.duckdb> [--threshold 0.5] [--format text|json]")
    db_path = pos[1]
    isfile(db_path) || error("audit-transcripts: db not found: $(db_path)")
    threshold = parse(Float64, get(kw, "threshold", "0.5"))
    fmt = get(kw, "format", "text")

    store = open_transcript_store(path=db_path)
    n_total = transcript_count(store)
    if n_total == 0
        close_transcript_store(store)
        println("audit-transcripts: 0 entries in $(db_path)")
        return 0
    end

    rows = NamedTuple[]
    n_low = 0
    histogram = Dict{Int,Int}()  # bucket = floor(score * 10)
    by_method = Dict{String,Int}()
    for row in Crucible.iter_transcripts(store)
        spec_json = String(row.spec_json)
        score = nothing
        n_findings = 0
        try
            spec = spec_from_json(spec_json)
            rep = Crucible.lint(spec)
            n_findings = length(rep.findings)
            score = Crucible.coverage_score(rep.coverage)
        catch err
            score = -1.0   # unparseable rows
        end
        if score !== nothing
            bucket = score < 0 ? -1 : Int(floor(score * 10))
            histogram[bucket] = get(histogram, bucket, 0) + 1
            score >= 0 && score < threshold && (n_low += 1)
            push!(rows, (id=row.id, score=score, findings=n_findings,
                         provider=String(row.provider)))
            by_method[String(row.provider)] = get(by_method, String(row.provider), 0) + 1
        end
    end
    close_transcript_store(store)

    if fmt == "json"
        println(JSON3.write(Dict(
            "total" => n_total,
            "below_threshold" => n_low,
            "threshold" => threshold,
            "histogram" => Dict(string(k)=>v for (k,v) in histogram),
            "by_provider" => by_method,
            "rows" => [Dict("id"=>r.id, "score"=>r.score,
                            "findings"=>r.findings, "provider"=>r.provider) for r in rows],
        )))
    else
        println("audit-transcripts: $(db_path)")
        println("  total entries:    $(n_total)")
        println("  below score $(threshold): $(n_low) ($(round(100 * n_low / n_total; digits=1))%)")
        println()
        println("Score histogram (buckets of 0.1):")
        for k in sort(collect(keys(histogram)))
            label = k == -1 ? "  parse-fail" : "  $(round(k*0.1; digits=1))–$(round((k+1)*0.1; digits=1))"
            println(rpad(label, 20), "█" ^ min(histogram[k], 60), " ", histogram[k])
        end
        println()
        println("By provider:")
        for (p, n) in sort(collect(by_method); by = x -> -x[2])
            println("  $(rpad(p, 20))$(n)")
        end
        if !isempty(rows)
            println()
            println("Bottom 10 by score:")
            sorted = sort(rows; by = r -> r.score)
            for r in first(sorted, min(10, length(sorted)))
                println("  id=$(r.id) score=$(round(r.score; digits=2)) findings=$(r.findings) provider=$(r.provider)")
            end
        end
    end
    0
end

function cmd_cite(args::Vector{String})
    pos, _ = _parse_kw_args(args)
    length(pos) < 1 && error("usage: cite <spec.json>")
    spec = spec_from_json(read(pos[1], String))
    if isempty(spec.provenance)
        println("(no provenance entries)")
        return 0
    end
    by_source = Dict{Symbol,Vector{String}}()
    for (path, p) in spec.provenance
        push!(get!(by_source, p.source, String[]), path)
    end
    for src in (:paper, :paper_default, :user, :assumed, :runtime_default)
        haskey(by_source, src) || continue
        paths = sort(by_source[src])
        println("[$(src)] ($(length(paths)) entries)")
        for path in paths
            p = spec.provenance[path]
            cite_str = p.cite === nothing ? "—" : p.cite
            println("  $(path)")
            println("    cite: $(cite_str)")
            println("    confidence: $(round(p.confidence; digits=2))")
        end
        println()
    end
    0
end

function cmd_explain(args::Vector{String})
    pos, _ = _parse_kw_args(args)
    length(pos) < 1 && error("usage: explain <spec.json>")
    spec = spec_from_json(read(pos[1], String))
    println(_explain_spec(spec))
    0
end

function _explain_spec(spec::MDSpec)::String
    io = IOBuffer()
    src = spec.system.source
    print(io, "This MDSpec describes a ")
    if src.type == :smiles
        print(io, "pure-ligand simulation of `$(src.ligand_smiles)` ")
    elseif src.type == :protein_ligand
        print(io, "protein-ligand simulation of PDB `$(src.pdb_id)` with ligand `$(src.ligand_smiles)` ")
    elseif src.type in (:pdb_id, :pdb_fetch)
        print(io, "simulation of PDB `$(src.pdb_id)` (PDBFixer auto-built) ")
    else
        print(io, "simulation of a user-supplied system ")
    end
    sol = spec.system.solvent
    if sol.membrane !== nothing
        print(io, "embedded in a $(String(sol.membrane.composition)) bilayer ($(sol.membrane.n_lipids) lipids) ")
    end
    if sol.model == :vacuum
        print(io, "in vacuum")
    elseif sol.model == :implicit_GBSA
        print(io, "in implicit GBSA solvent")
    else
        print(io, "in $(String(sol.model)) water with $(sol.ions_NaCl_mM) mM NaCl")
    end
    print(io, ".\n\n")
    is_cg = spec.force_field.protein in (:martini3, :martini2_2)
    print(io, "Force field: $(String(spec.force_field.protein))")
    is_cg && print(io, " (coarse-grained — runtime requires martinize2)")
    spec.force_field.water != :vacuum && print(io, " + $(String(spec.force_field.water))")
    spec.force_field.lipid !== nothing && print(io, " + $(String(spec.force_field.lipid))")
    spec.force_field.ligand != :user_supplied && print(io, " + $(String(spec.force_field.ligand)) for the ligand")
    print(io, ".\n\n")
    print(io, "Protocol ($(length(spec.protocol)) stages):\n")
    for (i, s) in enumerate(spec.protocol)
        print(io, "  $(i). $(_stage_one_liner(s))\n")
    end
    if !isempty(spec.observables)
        print(io, "\nObservables: ", join((String(o.type) for o in spec.observables), ", "), ".\n")
    end
    if spec.system.protonation !== nothing
        print(io, "\nConstant-pH MD at pH $(spec.system.protonation.pH) ",
              "(titrating: $(join(spec.system.protonation.titrating_residues, ", "))).\n")
    end
    if !isempty(spec.warnings)
        print(io, "\n⚠ Warnings:\n")
        for w in spec.warnings; print(io, "  - $(w)\n"); end
    end
    String(take!(io))
end

_stage_one_liner(s::MinimizeStage) =
    "Minimize ($(s.max_iterations) iterations to tol=$(s.tolerance_kj_mol_nm) kJ/mol/nm)."

function _stage_one_liner(s::DynamicsStage)
    role = s.role == :production ? "Production" : "Equilibrate"
    base = "$(role) $(String(s.ensemble)) for $(s.duration_ns) ns at $(s.temperature_K) K"
    if s.ensemble == :NPT
        base *= ", $(s.pressure_bar) bar"
    end
    if s.restraints.selection != :none
        base *= " with $(String(s.restraints.selection)) restraints (k=$(s.restraints.k_kj_mol_nm2))"
    end
    base * "."
end

function _stage_one_liner(s::FEPStage)
    "Alchemical $(String(s.kind)) FEP across $(length(s.lambda_windows)) λ windows " *
    "× $(s.duration_per_window_ns) ns each, target=`$(s.target_selection)`."
end

function _stage_one_liner(s::REMDStage)
    "Replica-exchange MD: $(length(s.temperature_ladder_K)) replicas " *
    "$(round(first(s.temperature_ladder_K); digits=1))–" *
    "$(round(last(s.temperature_ladder_K); digits=1)) K, " *
    "$(s.duration_per_replica_ns) ns per replica, " *
    "exchange every $(s.exchange_attempt_period_ps) ps."
end

function _stage_one_liner(s::MetadynamicsStage)
    cv_summary = join((cv.name * " (" * String(cv.kind) * ")" for cv in s.cvs), ", ")
    extra = s.well_tempered ? " (well-tempered, γ=$(s.bias_factor))" : ""
    "Metadynamics for $(s.duration_ns) ns biasing $(cv_summary)$(extra)."
end

function cmd_bench(args::Vector{String})
    _, kw = _parse_kw_args(args)
    n_repeat = parse(Int, get(kw, "repeat", "10"))
    fmt = get(kw, "format", "text")
    baseline_path = get(kw, "baseline", "")
    save_path = get(kw, "save", "")
    threshold_pct = parse(Float64, get(kw, "threshold", "20"))
    backend = OpenMMBackend()
    results = NamedTuple[]
    workdir = "/tmp/crucible-bench"
    for name in list_templates()
        spec = get_template(name)
        json = spec_to_json(spec)
        _ = Crucible.render_script(backend, spec; output_dir=workdir)
        _ = Crucible.gate_schema(json)
        t_render = @elapsed for _ in 1:n_repeat
            _ = Crucible.render_script(backend, spec; output_dir=workdir)
        end
        t_validate = @elapsed for _ in 1:n_repeat
            _ = Crucible.run_validation(json, spec, backend)
        end
        bytes = length(Crucible.render_script(backend, spec; output_dir=workdir))
        push!(results, (name = String(name),
                        render_us_per = (t_render / n_repeat) * 1e6,
                        validate_us_per = (t_validate / n_repeat) * 1e6,
                        script_bytes = bytes))
    end

    # Optional baseline comparison.
    baseline = nothing
    if !isempty(baseline_path)
        baseline_obj = JSON3.read(read(baseline_path, String))
        baseline = Dict{String,NamedTuple}()
        for r in baseline_obj
            baseline[String(r.name)] = (
                render_us_per   = Float64(r.render_us_per_call),
                validate_us_per = Float64(r.validate_us_per_call),
                script_bytes    = Int(r.script_bytes),
            )
        end
    end

    # Optional save.
    if !isempty(save_path)
        snapshot = [Dict("name" => r.name,
                         "render_us_per_call"   => r.render_us_per,
                         "validate_us_per_call" => r.validate_us_per,
                         "script_bytes"         => r.script_bytes) for r in results]
        write(save_path, JSON3.write(snapshot))
        println(stderr, "wrote baseline: $(save_path)")
    end

    regressions = NamedTuple[]
    if baseline !== nothing
        for r in results
            haskey(baseline, r.name) || continue
            b = baseline[r.name]
            for (label, cur, base_v) in (
                ("render",   r.render_us_per,   b.render_us_per),
                ("validate", r.validate_us_per, b.validate_us_per),
            )
                base_v <= 0 && continue
                pct = 100 * (cur - base_v) / base_v
                if pct > threshold_pct
                    push!(regressions, (template=r.name, op=label,
                                        before=base_v, after=cur, pct=pct))
                end
            end
        end
    end
    if fmt == "json"
        out = Dict{String,Any}(
            "results" => [Dict("name" => r.name,
                               "render_us_per_call"   => r.render_us_per,
                               "validate_us_per_call" => r.validate_us_per,
                               "script_bytes"         => r.script_bytes)
                          for r in results],
        )
        if baseline !== nothing
            out["regressions"] = [Dict("template" => r.template, "op" => r.op,
                                       "before_us" => r.before, "after_us" => r.after,
                                       "pct" => r.pct) for r in regressions]
        end
        println(JSON3.write(out))
    else
        println("crucible bench (n=$(n_repeat) per template, OpenMM backend)")
        println()
        println(rpad("template", 24), rpad("render µs", 14), rpad("validate µs", 14), "bytes")
        println(repeat("-", 60))
        for r in results
            println(rpad(r.name, 24),
                    rpad(string(round(r.render_us_per; digits=1)), 14),
                    rpad(string(round(r.validate_us_per; digits=1)), 14),
                    r.script_bytes)
        end
        if baseline !== nothing
            println()
            if isempty(regressions)
                println("baseline: ✓ no regressions above $(threshold_pct)% threshold")
            else
                println("baseline: $(length(regressions)) regression(s) above $(threshold_pct)% threshold")
                for r in regressions
                    println("  $(r.template) ($(r.op)): $(round(r.before; digits=1)) → $(round(r.after; digits=1)) µs ($(round(r.pct; digits=1))%)")
                end
            end
        end
    end
    # Non-zero exit when --baseline + regressions found, so CI can gate.
    return isempty(regressions) ? 0 : 4
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

function cmd_analyze(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: analyze <workdir> [--format text|markdown|json]")
    workdir = pos[1]
    isdir(workdir) || error("analyze: not a directory: $(workdir)")
    fmt = get(kw, "format", "text")

    # Discover observable CSVs by name. The renderer writes them with
    # canonical filenames; we hardcode the mapping rather than parsing
    # headers to keep the report deterministic.
    expected = [
        ("rmsd",     "rmsd.csv",     "rmsd_nm",     "RMSD (nm)"),
        ("rmsf",     "rmsf.csv",     "rmsf_nm",     "RMSF per atom (nm)"),
        ("rg",       "rg.csv",       "rg_nm",       "Radius of gyration (nm)"),
        ("sasa",     "sasa.csv",     "total_nm2",   "SASA total (nm²)"),
        ("distance", "distance.csv", "distance_nm", "Distance (nm)"),
        ("hbonds",   "hbonds.csv",   "n_hbonds",    "Hydrogen-bond count"),
    ]
    found = NamedTuple[]
    for (kind, fname, _col, label) in expected
        path = joinpath(workdir, fname)
        isfile(path) || continue
        s = try
            Crucible.summarize_observable(path)
        catch err
            (; kind=kind, path=path, error=string(err))
        end
        push!(found, (kind=kind, label=label, path=path, summary=s))
    end

    if fmt == "json"
        rows = []
        for f in found
            row = Dict{String,Any}(
                "kind" => f.kind,
                "path" => f.path,
            )
            if f.summary isa NamedTuple && haskey(f.summary, :count)
                row["count"] = f.summary.count
                row["mean"]  = f.summary.mean
                row["min"]   = f.summary.min
                row["max"]   = f.summary.max
                row["last"]  = f.summary.last
            else
                row["error"] = haskey(f.summary, :error) ? f.summary.error : "unknown"
            end
            push!(rows, row)
        end
        println(JSON3.write(rows))
    elseif fmt == "markdown"
        println("# Crucible analysis: ", basename(rstrip(abspath(workdir), '/')))
        println()
        if isempty(found)
            println("_(no observable CSVs found in `$(workdir)`)_")
        else
            println("| observable | n | mean | min | max | last |")
            println("|---|---:|---:|---:|---:|---:|")
            for f in found
                (f.summary isa NamedTuple && haskey(f.summary, :count)) || continue
                s = f.summary
                println("| ", f.label, " | ", s.count, " | ",
                        round(s.mean; digits=4), " | ",
                        round(s.min; digits=4), " | ",
                        round(s.max; digits=4), " | ",
                        round(s.last; digits=4), " |")
            end
        end
    else
        println("crucible analyze: $(workdir)")
        println()
        if isempty(found)
            println("(no observable CSVs found)")
        else
            for f in found
                println("[$(f.kind)] $(f.label)")
                println("  file: $(f.path)")
                if f.summary isa NamedTuple && haskey(f.summary, :count)
                    s = f.summary
                    println("  n=$(s.count)  mean=$(round(s.mean; digits=4))  min=$(round(s.min; digits=4))  max=$(round(s.max; digits=4))  last=$(round(s.last; digits=4))")
                else
                    println("  ERROR: ", haskey(f.summary, :error) ? f.summary.error : "unknown")
                end
                println()
            end
        end
    end
    0
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
        elseif cmd == "run";          return cmd_run(rest)
        elseif cmd == "serve";        return cmd_serve(rest)
        elseif cmd == "doctor";       return cmd_doctor(rest)
        elseif cmd == "coverage";     return cmd_coverage(rest)
        elseif cmd == "lint";         return cmd_lint(rest)
        elseif cmd == "templates";    return cmd_templates(rest)
        elseif cmd == "snapshot";     return cmd_snapshot(rest)
        elseif cmd == "restore";      return cmd_restore(rest)
        elseif cmd == "fmt";          return cmd_fmt(rest)
        elseif cmd == "trajstat";     return cmd_trajstat(rest)
        elseif cmd == "analyze";      return cmd_analyze(rest)
        elseif cmd == "upgrade";      return cmd_upgrade(rest)
        elseif cmd == "bench";        return cmd_bench(rest)
        elseif cmd == "cite";         return cmd_cite(rest)
        elseif cmd == "explain";      return cmd_explain(rest)
        elseif cmd == "export-jsonschema"; return cmd_export_jsonschema(rest)
        elseif cmd == "audit-transcripts"; return cmd_audit_transcripts(rest)
        elseif cmd == "import-jsonl"; return cmd_import_jsonl(rest)
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
