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
import Dates

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
  crucible diff          <spec-a.json> <spec-b.json> [--intent]   # Markdown diff
  crucible info          [--format text|json]        # capability surface
  crucible parameterize  <smiles> --out <dir> [--ff openff_sage_2_2_0]
                                              [--python python] [--name LIG]
  crucible verify        <spec.json> [--backend openmm|molly]   # gates 1-3 + render
  crucible health        <spec.json> [--backend openmm|molly]   # validate + lint + coverage
  crucible run           <spec.json> [--workdir path] [--platform X] [--precision P]
                                     [--seed N] [--resume] [--backend openmm] [--quiet]
                                     [--pre-run-hook 'cmd'] [--post-run-hook 'cmd']
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
  crucible plot          <workdir> [--out-dir path] [--python python] [--annotate]  # PNGs of CSVs (matplotlib)
  crucible events        <workdir> [--format text|json|markdown]   # critical-moment detection
  crucible upgrade       <spec.json> [--out path] [--target ver]  # forward-migrate schema
  crucible bench         [--format text|json] [--repeat N]
                         [--save baseline.json] [--baseline base.json] [--threshold 20]
  crucible cite          <spec.json>                                # list every provenance entry
  crucible explain       <spec.json>                                # natural-language summary
  crucible export-jsonschema [--out path]                            # dump the live schema.json
  crucible audit-transcripts <db.duckdb> [--threshold 0.5] [--format text|json]  # corpus quality
  crucible import-jsonl  <file.jsonl> [--db path]                  # load training pairs into TranscriptStore
  crucible walkthrough   <source-kind> <source>
  crucible hekate        bootstrap-venue [--name N] [--lat L] [--lon L] [--capacity N]
                                          [--rrule R] [--duration M] [--dry-run]
                         create-slot [--start ISO8601] [--duration M]
                         publish-event <spec.json> [--paper-title T] [--report-url U]
                                                   [--workdir D] [--live]
                         doctor                                  # AT Proto config + session check

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

function _cmd_info_json()
    backends = Dict{String,Any}()
    for (name, b) in (("MollyBackend", MollyBackend()),
                      ("OpenMMBackend", OpenMMBackend()),
                      ("KineticsBackend", KineticsBackend()))
        backends[name] = sort(string.(collect(Crucible.supported_features(b))))
    end
    obj = Dict{String,Any}(
        "schema_version"     => "0.3.0",
        "stage_types"        => ["MinimizeStage", "DynamicsStage",
                                 "FEPStage", "REMDStage", "MetadynamicsStage"],
        "source_types"       => ["user_supplied", "pdb_id", "pdb_fetch",
                                 "smiles", "protein_ligand"],
        "observable_types"   => ["rmsd", "rmsf", "energy", "trajectory",
                                 "rg", "sasa", "distance", "hbonds"],
        "force_fields"       => Dict(
            "protein" => string.(collect(Crucible.PROTEIN_FF_ALLOWLIST)),
            "water"   => string.(collect(Crucible.WATER_MODEL_ALLOWLIST)),
            "ligand"  => string.(collect(Crucible.LIGAND_FF_ALLOWLIST)),
            "lipid"   => string.(collect(Crucible.LIPID_FF_ALLOWLIST)),
        ),
        "backends"           => backends,
        "templates"          => string.(list_templates()),
        "openff_available"   => parameterizer_available(),
        "subcommands"        => [m.captures[1] for m in
            (match(r"^\s+crucible\s+([\w-]+)", line) for line in eachline(IOBuffer(HELP_TEXT)))
            if m !== nothing],
    )
    println(JSON3.write(obj))
    0
end

function cmd_info(args::Vector{String})
    _, kw = _parse_kw_args(args)
    if get(kw, "format", "text") == "json"
        return _cmd_info_json()
    end
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
    println("                 info parameterize verify health serve doctor coverage lint")
    println("                 templates snapshot restore fmt trajstat analyze plot upgrade")
    println("                 bench cite explain export-jsonschema audit-transcripts")
    println("                 import-jsonl run")
    println()
    println("Ligand parameterizer:")
    avail = parameterizer_available()
    println("  OpenFFParameterizer (openff-toolkit): ", avail ? "available" : "not installed")
    0
end

function cmd_diff(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 2 && error("usage: diff <spec-a.json> <spec-b.json> [--intent]")
    a = spec_from_json(read(pos[1], String))
    b = spec_from_json(read(pos[2], String))
    d = diff_specs(a, b)
    if haskey(kw, "intent")
        # Intent-aware header: classify the diff into recognizable
        # buckets (FF swap, stage added/removed, parameter retune, etc.)
        # before the field-level dump. Useful for the option-3 corpus's
        # human-review pass — reviewers can skip pure-noise diffs.
        intents = _classify_intent(a, b, d)
        println("## Intent\n")
        if isempty(intents)
            println("- (no intent-bucket fired; see field-level diff below)\n")
        else
            for tag in intents
                println("- ", tag)
            end
            println()
        end
    end
    print(render(MarkdownRenderer(), d))
    isempty(d) ? 0 : 4
end

"""
    _classify_intent(a, b, d) -> Vector{String}

Coarse classification of how `b` differs from `a` for human triage.
Returns a list of human-readable tags. Empty list = no recognizable
intent (the user should look at the field-level diff).
"""
function _classify_intent(a::MDSpec, b::MDSpec, d::SpecDiff)::Vector{String}
    tags = String[]
    # FF swaps
    if a.force_field.protein != b.force_field.protein
        push!(tags, "**FF swap (protein)**: `$(a.force_field.protein)` → `$(b.force_field.protein)`")
    end
    if a.force_field.water != b.force_field.water
        push!(tags, "**FF swap (water)**: `$(a.force_field.water)` → `$(b.force_field.water)`")
    end
    if a.force_field.ligand != b.force_field.ligand
        push!(tags, "**FF swap (ligand)**: `$(a.force_field.ligand)` → `$(b.force_field.ligand)`")
    end
    if a.force_field.lipid != b.force_field.lipid
        push!(tags, "**FF swap (lipid)**: `$(a.force_field.lipid)` → `$(b.force_field.lipid)`")
    end
    # Source migration
    if a.system.source.type != b.system.source.type
        push!(tags, "**source change**: `$(a.system.source.type)` → `$(b.system.source.type)`")
    end
    # Stage changes
    if length(a.protocol) != length(b.protocol)
        push!(tags, "**protocol resized**: $(length(a.protocol)) → $(length(b.protocol)) stages")
    else
        for (i, (sa, sb)) in enumerate(zip(a.protocol, b.protocol))
            if typeof(sa) != typeof(sb)
                push!(tags, "**stage[$i] kind**: $(nameof(typeof(sa))) → $(nameof(typeof(sb)))")
            elseif sa isa DynamicsStage && sb isa DynamicsStage
                if sa.ensemble != sb.ensemble
                    push!(tags, "**stage[$i] ensemble**: $(sa.ensemble) → $(sb.ensemble)")
                end
                if sa.role != sb.role
                    push!(tags, "**stage[$i] role**: $(sa.role) → $(sb.role)")
                end
            end
        end
    end
    # Solvent / membrane change
    if a.system.solvent.model != b.system.solvent.model
        push!(tags, "**solvent model change**: `$(a.system.solvent.model)` → `$(b.system.solvent.model)`")
    end
    a_mem = a.system.solvent.membrane === nothing
    b_mem = b.system.solvent.membrane === nothing
    if a_mem != b_mem
        push!(tags, b_mem ? "**membrane removed**" : "**membrane added**")
    end
    # Pure parameter retune (no structural change but field-level diff non-empty)
    if isempty(tags) && !isempty(d.changed)
        push!(tags, "**parameter retune** ($(length(d.changed)) field(s))")
    end
    tags
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

function cmd_health(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: health <spec.json> [--backend openmm|molly]")
    spec_json = read(pos[1], String)
    spec = spec_from_json(spec_json)
    backend = haskey(kw, "backend") ? _backend(kw["backend"]) :
              route_backend(spec; available=[OpenMMBackend(), MollyBackend()]).backend
    println("crucible health: $(pos[1])  (backend=$(Crucible.backend_name(backend)))")
    println(repeat("=", 70))

    # Validation block (gates 1-3)
    println()
    report = Crucible.run_validation(spec_json, spec, backend)
    println("Validation:  ", report.ok ? "✓ PASS" : "✗ FAIL")
    for e in report.errors;   println("  error: ",   e); end
    for w in report.warnings; println("  warn:  ",   w); end

    # Lint block
    println()
    lint_rep = Crucible.lint(spec)
    if isempty(lint_rep)
        println("Lint:        ✓ no advisories")
    else
        println("Lint:        $(length(lint_rep.findings)) finding(s)")
        for f in lint_rep.findings
            tag = f.severity == :warn      ? "warn  " :
                  f.severity == :advisory  ? "advise" : "info  "
            println("  [$(tag)] $(f.rule) @ $(f.path)")
            println("            $(f.message)")
        end
    end

    # Coverage block
    println()
    cov = Crucible.provenance_coverage(spec)
    score = Crucible.coverage_score(cov)
    pct = cov.total_numeric_fields == 0 ? 0.0 :
          100 * cov.fields_with_provenance / cov.total_numeric_fields
    println("Provenance:  $(cov.fields_with_provenance)/$(cov.total_numeric_fields) " *
            "($(round(pct; digits=1))%)  score=$(round(score; digits=2))")
    if !isempty(cov.by_source)
        for (src, n) in sort(collect(cov.by_source); by = x -> -x[2])
            println("    $(rpad(string(src) * ":", 18))$(n)")
        end
    end

    # Single-line verdict
    println()
    n_warn = length(lint_rep.findings)
    verdict = if !report.ok
        "✗ broken — fix Gate errors before proceeding"
    elseif score < 0.5
        "⚠ thin — provenance score $(round(score; digits=2)) is below 0.5; re-extract"
    elseif n_warn > 5
        "⚠ noisy — $(n_warn) lint findings; consider tightening before a run"
    else
        "✓ ready"
    end
    println("Verdict:     $(verdict)")

    report.ok ? 0 : 2
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
    quiet = haskey(kw, "quiet")
    quiet || println("workdir:        $(workdir)")
    quiet || println("script:         $(job.script_path) ($(filesize(job.script_path)) bytes)")

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
        quiet || println("resume from:    $(env["CRUCIBLE_RESUME_FROM"])")
    end

    quiet || println("python:         $(py)")
    quiet || println("env overrides:  ",
            join((string(k, "=", v) for (k, v) in env if startswith(k, "CRUCIBLE_") && haskey(kw, lowercase(replace(k, "CRUCIBLE_" => "")))),
                 ", "))
    # Hooks: --pre-run-hook 'cmd' / --post-run-hook 'cmd' or
    # CRUCIBLE_PRE_RUN / CRUCIBLE_POST_RUN env vars. Both are shell
    # strings; CRUCIBLE_WORKDIR is exported into the hook env so the
    # hook can reach the workdir without us having to pass it in args.
    # Trade-off: shell exec means the hook author owns escaping. We
    # don't sanitize; if you put untrusted strings in here that's on
    # you (the same as `bash -c 'whatever'`).
    pre_hook  = get(kw, "pre-run-hook",  get(ENV, "CRUCIBLE_PRE_RUN",  ""))
    post_hook = get(kw, "post-run-hook", get(ENV, "CRUCIBLE_POST_RUN", ""))
    hook_env = copy(env)
    hook_env["CRUCIBLE_WORKDIR"] = workdir
    hook_env["CRUCIBLE_SPEC"]    = pos[1]

    if !isempty(pre_hook)
        quiet || println("pre-run hook:   $(pre_hook)")
        try
            run(pipeline(setenv(`bash -c $pre_hook`, hook_env)); wait=true)
        catch err
            println(stderr, "pre-run hook failed: $(err)")
            return 5
        end
    end

    quiet || println("---- script stdout ----")
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
    quiet || println("---- exit $(rc) ----")

    if rc == 0 && !haskey(kw, "no-hekate") && get(ENV, "CRUCIBLE_HEKATE_DISABLE", "0") != "1"
        try
            Crucible.ATProto.publish_review_session_from_run(
                spec_json, workdir,
                get(kw, "paper-title", ""),
                get(kw, "report-url", ""))
        catch err
            @warn "[hekate] publish hook errored at boundary" error=string(err)
        end
    end

    if !isempty(post_hook)
        quiet || println("post-run hook:  $(post_hook)")
        # Post-hook runs even when the python rc is non-zero — that's
        # the point of "post" (alerting on failure, cleanup, upload, …).
        # The hook gets CRUCIBLE_RUN_RC in its env so it can branch.
        hook_env["CRUCIBLE_RUN_RC"] = string(rc)
        try
            run(pipeline(setenv(`bash -c $post_hook`, hook_env)); wait=true)
        catch err
            println(stderr, "post-run hook failed: $(err)")
            # Don't override the python rc; the post-hook fault doesn't
            # cancel a successful simulation.
        end
    end
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
    println(Crucible._explain_spec(spec))
    0
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

function cmd_plot(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: plot <workdir> [--out-dir path] [--python python]")
    workdir = pos[1]
    isdir(workdir) || error("plot: not a directory: $(workdir)")
    out_dir = get(kw, "out-dir", joinpath(workdir, "plots"))
    py = get(kw, "python",
             Sys.which("python") !== nothing ? "python" :
             Sys.which("python3") !== nothing ? "python3" : "")
    isempty(py) && error("plot: no python on PATH; install matplotlib + pandas")

    mkpath(out_dir)
    csvs = filter(f -> endswith(f, ".csv"), readdir(workdir; join=false))
    if isempty(csvs)
        println("plot: no CSVs in $(workdir)")
        return 0
    end

    # Optional --annotate: detect events and pass per-CSV frame lists to
    # the plotter so it can overlay vertical lines.
    annotations = Dict{String,Vector{Int}}()
    if haskey(kw, "annotate")
        for ev in Crucible.detect_events(workdir)
            push!(get!(annotations, ev.observable, Int[]), ev.frame)
        end
        println("annotate: $(sum(length(v) for v in values(annotations); init=0)) event(s) across $(length(annotations)) observable(s)")
    end

    # Build a tiny matplotlib script. Trade-off: we shell to python rather
    # than depending on PyPlot.jl, matching the renderer's
    # subprocess-over-PythonCall precedent. Skips cleanly when matplotlib
    # is missing; emits one PNG per CSV.
    #
    # Argument format: "csv_path::out_png[::frame1,frame2,…]" — third
    # field is optional comma-separated frame indices to overlay as
    # red vertical lines (annotated events).
    script_path = joinpath(out_dir, "_plot.py")
    open(script_path, "w") do io
        print(io, """
        import sys, os, csv as _csv
        try:
            import matplotlib
            matplotlib.use('Agg')
            import matplotlib.pyplot as plt
        except ImportError:
            print('plot: matplotlib not installed; install via: pip install matplotlib')
            sys.exit(2)

        def _plot(path, out_png, event_frames):
            with open(path) as f:
                rdr = list(_csv.reader(f))
            if len(rdr) < 2:
                print(f'plot: {path} has <2 rows; skipping')
                return
            header = rdr[0]
            xs, ys = [], []
            for row in rdr[1:]:
                if len(row) < 2: continue
                try:
                    xs.append(float(row[0]))
                    ys.append(float(row[1]))
                except ValueError:
                    continue
            if not ys:
                print(f'plot: {path} had no numeric rows')
                return
            fig, ax = plt.subplots(figsize=(7, 4))
            ax.plot(xs, ys, lw=1.0)
            for f_idx in event_frames:
                # Map the integer frame back to its x-axis value if the
                # first column is itself a frame index. Otherwise we
                # interpret the event's "frame" as a row position and
                # look up xs[row].
                xv = None
                if 0 <= f_idx < len(xs):
                    xv = xs[f_idx]
                else:
                    # Try matching xs literally (rmsd.csv uses frame as col 0)
                    for cand_x in xs:
                        if abs(cand_x - f_idx) < 0.5:
                            xv = cand_x
                            break
                if xv is None:
                    continue
                ax.axvline(xv, color='red', alpha=0.5, lw=1.0)
            ax.set_xlabel(header[0])
            ax.set_ylabel(header[1] if len(header) > 1 else 'value')
            title = os.path.basename(path)
            if event_frames:
                title += f'  ({len(event_frames)} event(s) flagged)'
            ax.set_title(title)
            ax.grid(alpha=0.3)
            fig.tight_layout()
            fig.savefig(out_png, dpi=120)
            plt.close(fig)
            print(f'wrote {out_png}')

        for arg in sys.argv[1:]:
            parts = arg.split('::')
            csv_path, out_png = parts[0], parts[1]
            ev_frames = []
            if len(parts) > 2 and parts[2]:
                ev_frames = [int(x) for x in parts[2].split(',') if x.strip()]
            _plot(csv_path, out_png, ev_frames)
        """)
    end
    pairs = String[]
    for csv in csvs
        png = joinpath(out_dir, replace(csv, r"\.csv$" => ".png"))
        ev_frames = get(annotations, csv, Int[])
        suffix = isempty(ev_frames) ? "" : "::" * join(string.(ev_frames), ",")
        push!(pairs, joinpath(workdir, csv) * "::" * png * suffix)
    end
    cmd = `$py $script_path $(pairs)`
    try
        run(cmd; wait=true)
        rm(script_path; force=true)
        println("plotted: $(length(csvs)) CSV(s) → $(out_dir)/")
        return 0
    catch err
        rm(script_path; force=true)
        println(stderr, "plot failed: $(err)")
        return 1
    end
end

function cmd_events(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    length(pos) < 1 && error("usage: events <workdir> [--format text|json|markdown]")
    workdir = pos[1]
    isdir(workdir) || error("events: not a directory: $(workdir)")
    fmt = get(kw, "format", "text")
    events = Crucible.detect_events(workdir)
    if fmt == "json"
        rows = [Dict("kind" => String(e.kind), "observable" => e.observable,
                     "frame" => e.frame, "value" => e.value,
                     "description" => e.description) for e in events]
        println(JSON3.write(rows))
    elseif fmt == "markdown"
        println("# Crucible events: ", basename(rstrip(abspath(workdir), '/')))
        println()
        if isempty(events)
            println("_(no critical moments detected — could be a clean run, or thresholds may need tuning)_")
        else
            println("$(length(events)) event(s):")
            println()
            println("| kind | observable | frame | value | description |")
            println("|---|---|---:|---:|---|")
            for e in events
                println("| `$(e.kind)` | `$(e.observable)` | $(e.frame) | $(round(e.value; digits=4)) | $(e.description) |")
            end
        end
    else
        println("crucible events: $(workdir)")
        println()
        if isempty(events)
            println("(no critical moments detected — could be a clean run,")
            println(" or thresholds may need tuning. See docs/VISUALIZATION.md.)")
        else
            for e in events
                println("[$(e.kind)] $(e.observable) frame $(e.frame): $(e.description)")
            end
            println()
            println("$(length(events)) event(s) total")
        end
    end
    0
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
        println("  ", rpad("name", 22), rpad("score", 7), rpad("findings", 9),
                rpad("stages", 7), "notes")
        println("  ", repeat("-", 76))
        for n in names
            spec = get_template(n)
            cov = Crucible.provenance_coverage(spec)
            score = round(Crucible.coverage_score(cov); digits=2)
            lint_rep = Crucible.lint(spec)
            n_find = length(lint_rep.findings)
            n_stages = length(spec.protocol)
            println("  ", rpad(string(n), 22),
                    rpad(string(score), 7),
                    rpad(string(n_find), 9),
                    rpad(string(n_stages), 7),
                    strip(spec.notes))
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

function cmd_hekate(args::Vector{String})
    pos, kw = _parse_kw_args(args)
    isempty(pos) && error("usage: hekate bootstrap-venue | create-slot | publish-event <spec.json> | doctor")
    sub = pos[1]

    if sub == "bootstrap-venue"
        cfg = Crucible.ATProto.load_config()
        dry_run = haskey(kw, "dry-run")
        result = Crucible.ATProto.bootstrap_venue!(cfg;
            name = get(kw, "name", "Crucible Lab"),
            lat = parse(Float64, get(kw, "lat", "0")),
            lon = parse(Float64, get(kw, "lon", "0")),
            capacity = parse(Int, get(kw, "capacity", "20")),
            rrule = get(kw, "rrule", "FREQ=WEEKLY;BYDAY=FR;BYHOUR=15;BYMINUTE=0"),
            duration_min = parse(Int, get(kw, "duration", "60")),
            dry_run = dry_run,
        )
        println("venue:      $(result.venue_uri)")
        println("recurrence: $(result.recurrence_uri)")
        dry_run || println("config:     $(cfg.config_path)")
        return 0
    elseif sub == "create-slot"
        cfg = Crucible.ATProto.load_config()
        start = if haskey(kw, "start")
            try
                Dates.DateTime(kw["start"], Dates.DateFormat("yyyy-mm-ddTHH:MM:SS"))
            catch err
                error("--start must be ISO8601 like 2026-05-01T15:00:00 (got $(kw["start"]): $(err))")
            end
        else
            nothing
        end
        uri = Crucible.ATProto.create_slot!(cfg;
            start = start,
            duration_min = parse(Int, get(kw, "duration", "60")),
        )
        println("slot: $(uri)")
        return 0
    elseif sub == "publish-event"
        length(pos) < 2 && error("usage: hekate publish-event <spec.json> [--paper-title ...] [--report-url ...] [--live]")
        spec_path = pos[2]
        spec_json = read(spec_path, String)
        if haskey(kw, "live")
            ENV["CRUCIBLE_HEKATE_PUBLISH_EVENTS"] = "1"
        end
        result = Crucible.ATProto.publish_review_session_from_run(
            spec_json, get(kw, "workdir", dirname(spec_path)),
            get(kw, "paper-title", ""),
            get(kw, "report-url", ""))
        println("mode:   $(result.mode)")
        result.uri !== nothing && println("uri:    $(result.uri)")
        if !isempty(result.errors)
            println("errors:")
            for e in result.errors; println("  - $(e)"); end
        end
        return 0
    elseif sub == "doctor"
        cfg = Crucible.ATProto.load_config()
        println("config_path:        $(cfg.config_path)")
        println("pds_url:            $(cfg.pds_url)")
        println("handle:             $(isempty(cfg.handle) ? "(unset)" : cfg.handle)")
        println("app_password:       $(isempty(cfg.app_password) ? "(unset)" : "(set, $(length(cfg.app_password)) chars)")")
        println("publish_events:     $(cfg.publish_events)")
        println("venue_at_uri:       $(cfg.venue_at_uri === nothing ? "(unset)" : cfg.venue_at_uri)")
        println("recurrence_at_uri:  $(cfg.recurrence_at_uri === nothing ? "(unset)" : cfg.recurrence_at_uri)")
        println("publish_ready:      $(Crucible.ATProto.is_publish_ready(cfg))")
        if !isempty(cfg.handle) && !isempty(cfg.app_password)
            print("session check:      ")
            try
                s = Crucible.ATProto.create_session(cfg)
                println("ok (did=$(s.did))")
            catch err
                println("FAILED: $(err)")
                return 2
            end
        else
            println("session check:      skipped (handle/password not set)")
        end
        return 0
    else
        error("unknown hekate subcommand: $(sub) (expected bootstrap-venue|create-slot|publish-event|doctor)")
    end
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
        elseif cmd == "health";       return cmd_health(rest)
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
        elseif cmd == "plot";         return cmd_plot(rest)
        elseif cmd == "events";       return cmd_events(rest)
        elseif cmd == "upgrade";      return cmd_upgrade(rest)
        elseif cmd == "bench";        return cmd_bench(rest)
        elseif cmd == "cite";         return cmd_cite(rest)
        elseif cmd == "explain";      return cmd_explain(rest)
        elseif cmd == "export-jsonschema"; return cmd_export_jsonschema(rest)
        elseif cmd == "audit-transcripts"; return cmd_audit_transcripts(rest)
        elseif cmd == "import-jsonl"; return cmd_import_jsonl(rest)
        elseif cmd == "walkthrough"; return cmd_walkthrough(rest)
        elseif cmd == "hekate";      return cmd_hekate(rest)
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
