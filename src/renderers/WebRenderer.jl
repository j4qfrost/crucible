# WebRenderer + lightweight HTTP frontend.
#
# Real implementation as of v1.0: HTTP.jl-based server (no Genie dep — keeps
# the package light, the user's preference). The renderer side emits a
# self-contained HTML page; the server side wraps the transpile / validate /
# render / parameterize pipeline behind JSON endpoints.
#
# Endpoints:
#   GET  /                    — single-page UI (HTML)
#   GET  /health              — {"status":"ok"}
#   POST /api/transpile       — {paper_text, provider:{kind,...}} -> spec_json
#   POST /api/validate        — {spec_json, backend?} -> ValidationReport
#   POST /api/render          — {spec_json, backend?} -> {script}
#   POST /api/advise          — {spec_json, budget_hours?} -> CloudRecommendation
#   POST /api/parameterize    — {smiles, ff?, name?} -> ParameterizedLigand
#
# Errors return {"ok":false, "error":"..."} with HTTP 4xx/5xx as appropriate.

using Base64
using HTTP
using JSON3

struct WebRenderer <: Renderer end

function render(::WebRenderer, spec::MDSpec)
    # Standalone HTML page — useful for "give me a one-file report" exports
    # outside the live server context.
    md = render(MarkdownRenderer(), spec)
    title = "Crucible spec ($(spec.schema_version))"
    """
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"><title>$(title)</title>
    <style>body{font:14px/1.5 -apple-system,system-ui,sans-serif;max-width:920px;margin:2em auto;padding:0 1em;color:#1a1a1a}
    pre,code{background:#f6f8fa;border-radius:4px}pre{padding:0.6em 1em;overflow-x:auto}
    h1,h2,h3{font-weight:600}table{border-collapse:collapse}td,th{border:1px solid #ddd;padding:4px 8px}</style>
    </head><body>$(_md_to_html(md))</body></html>
    """
end

# Tiny markdown→HTML — does headers, paragraphs, code fences, tables. We
# already render the spec to a known shape so this doesn't need to be a
# full-CommonMark engine.
function _md_to_html(md::AbstractString)
    out = IOBuffer()
    in_code = false
    in_table = false
    table_rows = String[]
    for raw in eachline(IOBuffer(md))
        line = String(raw)
        if startswith(line, "```")
            if in_code
                print(out, "</pre>")
                in_code = false
            else
                print(out, "<pre>")
                in_code = true
            end
            continue
        end
        if in_code
            println(out, _esc(line))
            continue
        end
        if startswith(line, "| ")
            push!(table_rows, line)
            in_table = true
            continue
        elseif in_table
            print(out, _render_table(table_rows))
            empty!(table_rows)
            in_table = false
        end
        if startswith(line, "### ")
            println(out, "<h3>", _esc(line[5:end]), "</h3>")
        elseif startswith(line, "## ")
            println(out, "<h2>", _esc(line[4:end]), "</h2>")
        elseif startswith(line, "# ")
            println(out, "<h1>", _esc(line[3:end]), "</h1>")
        elseif startswith(line, "- ")
            println(out, "<p>• ", _esc(line[3:end]), "</p>")
        elseif isempty(strip(line))
            println(out, "")
        else
            println(out, "<p>", _esc(line), "</p>")
        end
    end
    in_table && print(out, _render_table(table_rows))
    String(take!(out))
end

function _render_table(rows::Vector{String})
    isempty(rows) && return ""
    io = IOBuffer()
    print(io, "<table>")
    for (k, row) in enumerate(rows)
        # skip GFM separator row (e.g. "|---|---|")
        if occursin(r"^\|\s*-+\s*\|", row)
            continue
        end
        cells = split(strip(row, '|'), "|")
        tag = k == 1 ? "th" : "td"
        print(io, "<tr>")
        for c in cells
            print(io, "<", tag, ">", _esc(strip(c)), "</", tag, ">")
        end
        print(io, "</tr>")
    end
    print(io, "</table>")
    String(take!(io))
end

_esc(s) = replace(String(s), "&" => "&amp;", "<" => "&lt;", ">" => "&gt;")

# -----------------------------------------------------------------------------
# HTTP server.

const _INDEX_HTML = """
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Crucible — paper → MD sim</title>
<style>
body{font:14px/1.5 -apple-system,system-ui,sans-serif;max-width:1080px;margin:1.5em auto;padding:0 1em;color:#1a1a1a}
h1{margin:0 0 0.4em}small{color:#666}
.row{display:flex;gap:1em;align-items:flex-start}
.col{flex:1}
textarea,input,select{font:13px/1.4 ui-monospace,'SF Mono',Menlo,monospace;width:100%;box-sizing:border-box}
textarea{height:14em;padding:0.5em}
.btn{background:#1a1a1a;color:#fff;border:0;padding:0.4em 0.9em;border-radius:4px;cursor:pointer}
.btn:hover{background:#333}
pre{background:#f6f8fa;border-radius:4px;padding:0.6em 1em;overflow-x:auto;max-height:30em}
.ok{color:#0a0}.warn{color:#a60}.err{color:#a00}
.tag{display:inline-block;background:#eef;border-radius:3px;padding:1px 6px;font-size:12px;margin-right:4px}
</style></head>
<body>
<h1>Crucible <small>— paper → MDSpec → script</small></h1>
<p><span class="tag">v1.0</span><span class="tag">IR-first</span><span class="tag">Anthropic / Local / Recorded providers</span></p>

<div class="row">
  <div class="col">
    <h3>1. Paper text</h3>
    <textarea id="paper" placeholder="paste a Methods section, or click 'Use sample', or upload a PDF below"></textarea>
    <p>
      <input type="file" id="pdfFile" accept="application/pdf" onchange="loadPdf(this)">
      <span id="pdfStatus" style="color:#666;font-size:12px;"></span>
    </p>
    <p>
      provider:
      <select id="provider">
        <option value="recorded">recorded (offline)</option>
        <option value="anthropic">anthropic (needs ANTHROPIC_API_KEY on the server)</option>
        <option value="local">local (vLLM / Ollama, server-configured endpoint)</option>
      </select>
      <button class="btn" onclick="useSample()">Use sample</button>
      <button class="btn" onclick="transpile()">Transpile →</button>
    </p>
  </div>
  <div class="col">
    <h3>2. MDSpec JSON</h3>
    <textarea id="spec" placeholder="(populated after transpile, or paste a spec to validate)"></textarea>
    <p>
      backend:
      <select id="backend"><option value="openmm">openmm</option><option value="molly">molly</option></select>
      <button class="btn" onclick="validate()">Validate</button>
      <button class="btn" onclick="renderScript()">Render</button>
      <button class="btn" onclick="advise()">Cloud advise</button>
      <button class="btn" onclick="lintSpec()">Lint</button>
      <button class="btn" onclick="coverageSpec()">Coverage</button>
    </p>
  </div>
</div>

<h3>3. Output</h3>
<pre id="output">(awaiting action)</pre>

<script>
const SAMPLE = `Methods. The simulation used the AMBER ff14SB force field with TIP3P water.\\nSystems were built using a 1.0 nm padding around the protein, with 150 mM NaCl.\\nProduction MD ran for 100 ns at 300 K with a Langevin thermostat and Monte Carlo barostat at 1 bar.\\nThe integration timestep was 2 fs with HBonds constraints. Coordinates were saved every 10 ps.`;
function useSample(){document.getElementById('paper').value = SAMPLE;}
async function call(path, body){
  const r = await fetch(path, {method:'POST', headers:{'content-type':'application/json'}, body: JSON.stringify(body)});
  const t = await r.text();
  try { return [r.ok, JSON.parse(t)]; } catch(e) { return [r.ok, t]; }
}
function show(label, ok, x){
  const o = document.getElementById('output');
  const cls = ok ? 'ok' : 'err';
  o.innerHTML = '<span class="'+cls+'">[' + (ok?'OK':'ERR') + '] ' + label + '</span>\\n' +
                (typeof x === 'string' ? x : JSON.stringify(x, null, 2));
}
// Holds the base64 of the most recently selected PDF; cleared after a
// transpile so the textarea path takes priority next time.
let pendingPdfB64 = null;
function loadPdf(input){
  const f = input.files && input.files[0];
  if (!f) { pendingPdfB64 = null; return; }
  const reader = new FileReader();
  reader.onload = (e) => {
    // strip the "data:application/pdf;base64," prefix
    const b64 = String(e.target.result).split(',', 2)[1] || '';
    pendingPdfB64 = b64;
    document.getElementById('pdfStatus').textContent =
      'loaded ' + f.name + ' (' + (b64.length * 0.75 / 1024).toFixed(1) + ' KB) — click Transpile';
  };
  reader.readAsDataURL(f);
}
async function transpile(){
  const paper_text = document.getElementById('paper').value;
  const provider = document.getElementById('provider').value;
  const body = {provider:{kind:provider}};
  if (pendingPdfB64) {
    body.paper_pdf_b64 = pendingPdfB64;
  } else {
    body.paper_text = paper_text;
  }
  const [ok, res] = await call('/api/transpile', body);
  if (ok && res.spec_json){ document.getElementById('spec').value = res.spec_json; }
  show('transpile', ok, res);
  pendingPdfB64 = null;
  document.getElementById('pdfStatus').textContent = '';
  document.getElementById('pdfFile').value = '';
}
async function validate(){
  const spec_json = document.getElementById('spec').value;
  const backend = document.getElementById('backend').value;
  const [ok, res] = await call('/api/validate', {spec_json, backend});
  show('validate', ok, res);
}
async function renderScript(){
  const spec_json = document.getElementById('spec').value;
  const backend = document.getElementById('backend').value;
  const [ok, res] = await call('/api/render', {spec_json, backend});
  show('render', ok, res);
}
async function advise(){
  const spec_json = document.getElementById('spec').value;
  const [ok, res] = await call('/api/advise', {spec_json});
  show('advise', ok, res);
}
async function lintSpec(){
  const spec_json = document.getElementById('spec').value;
  const [ok, res] = await call('/api/lint', {spec_json});
  show('lint', ok, res);
}
async function coverageSpec(){
  const spec_json = document.getElementById('spec').value;
  const [ok, res] = await call('/api/coverage', {spec_json});
  show('coverage', ok, res);
}
</script>
</body></html>
"""

function _json_response(payload; status::Int=200)
    HTTP.Response(status, ["content-type" => "application/json"], JSON3.write(payload))
end

function _bad(req_msg::AbstractString; status::Int=400)
    _json_response(Dict("ok" => false, "error" => req_msg); status=status)
end

function _read_json(req::HTTP.Request)
    body = String(req.body)
    isempty(body) && return Dict{String,Any}()
    JSON3.read(body, Dict)
end

function _backend_from_str(name::AbstractString)
    name == "openmm" ? OpenMMBackend() :
    name == "molly"  ? MollyBackend()  :
    error("unknown backend: $(name)")
end

function _provider_from_payload(p)
    p === nothing && return RecordedProvider(_default_recorded_fixture())
    kind = String(get(p, "kind", "recorded"))
    if kind == "recorded"
        path = get(p, "fixture", _default_recorded_fixture())
        return RecordedProvider(String(path))
    elseif kind == "anthropic"
        return AnthropicProvider()
    elseif kind == "local"
        return LocalProvider()
    end
    error("unknown provider kind: $(kind)")
end

function _default_recorded_fixture()
    candidates = [
        joinpath(@__DIR__, "..", "..", "test", "fixtures", "recorded_anthropic_spec.json"),
        joinpath(pwd(), "test", "fixtures", "recorded_anthropic_spec.json"),
    ]
    for c in candidates
        isfile(c) && return c
    end
    candidates[1]
end

function _handle_transpile(req::HTTP.Request)
    try
        body = _read_json(req)
        # Either `paper_text` (existing path) OR `paper_pdf_b64` (new
        # PDF upload). When both are given, pdf_b64 wins after extraction.
        # Trade-off: base64 inflates payload ~33% but keeps the endpoint
        # JSON-only — no multipart parsing in Crucible.
        paper_text = String(get(body, "paper_text", ""))
        pdf_b64 = String(get(body, "paper_pdf_b64", ""))
        if !isempty(pdf_b64)
            tmp = tempname() * ".pdf"
            try
                bytes = Base64.base64decode(pdf_b64)
                write(tmp, bytes)
                paper = ingest(PDFAdapter(), tmp)
                paper_text = paper.body_text
            catch err
                return _bad("paper_pdf_b64 decode/ingest failed: $(err)")
            finally
                rm(tmp; force=true)
            end
        end
        isempty(paper_text) && return _bad("paper_text or paper_pdf_b64 is required")
        provider = _provider_from_payload(get(body, "provider", nothing))
        result = transpile(provider, paper_text)
        if result.spec === nothing
            return _bad("transpile produced no spec: $(result.raw_response)"; status=502)
        end
        _json_response(Dict(
            "ok"            => true,
            "provider"      => String(result.provider_name),
            "spec_json"     => result.spec_json,
            "raw_response"  => result.raw_response,
            "paper_chars"   => length(paper_text),
        ))
    catch err
        _bad("transpile failed: $(err)"; status=500)
    end
end

function _handle_validate(req::HTTP.Request)
    try
        body = _read_json(req)
        spec_json = String(get(body, "spec_json", ""))
        isempty(spec_json) && return _bad("spec_json is required")
        spec = spec_from_json(spec_json)
        backend = haskey(body, "backend") ? _backend_from_str(String(body["backend"])) :
                  route_backend(spec; available=[OpenMMBackend(), MollyBackend()]).backend
        report = run_validation(spec_json, spec, backend)
        _json_response(Dict(
            "ok"       => report.ok,
            "backend"  => String(Crucible.backend_name(backend)),
            "errors"   => report.errors,
            "warnings" => report.warnings,
        ))
    catch err
        _bad("validate failed: $(err)"; status=500)
    end
end

function _handle_render(req::HTTP.Request)
    try
        body = _read_json(req)
        spec_json = String(get(body, "spec_json", ""))
        isempty(spec_json) && return _bad("spec_json is required")
        spec = spec_from_json(spec_json)
        backend = _backend_from_str(String(get(body, "backend", "openmm")))
        workdir = mktempdir(prefix="crucible-web-")
        script = Crucible.render_script(backend, spec; output_dir=workdir)
        _json_response(Dict(
            "ok"       => true,
            "backend"  => String(Crucible.backend_name(backend)),
            "workdir"  => workdir,
            "script"   => script,
            "size"     => length(script),
        ))
    catch err
        _bad("render failed: $(err)"; status=500)
    end
end

function _handle_advise(req::HTTP.Request)
    try
        body = _read_json(req)
        spec_json = String(get(body, "spec_json", ""))
        isempty(spec_json) && return _bad("spec_json is required")
        spec = spec_from_json(spec_json)
        budget = Float64(get(body, "budget_hours", 6.0))
        backend_name = Symbol(get(body, "backend", "openmm"))
        rec = advise(spec; budget_hours=budget, backend_name=backend_name)
        _json_response(Dict(
            "ok"        => true,
            "chosen"    => rec.chosen === nothing ? nothing : Dict(
                "gpu"            => rec.chosen.gpu,
                "ns_per_day"     => rec.chosen.ns_per_day,
                "runtime_hours"  => rec.chosen.runtime_hours,
                "on_demand_usd"  => rec.chosen.on_demand_usd,
                "gcp_command"    => rec.chosen.gcp_command,
                "aws_command"    => rec.chosen.aws_command,
                "azure_command"  => rec.chosen.azure_command,
            ),
            "reason"    => rec.chosen_reason,
            "warnings"  => rec.warnings,
            "requires_confirmation" => rec.requires_confirmation,
        ))
    catch err
        _bad("advise failed: $(err)"; status=500)
    end
end

function _handle_repurpose_score(req::HTTP.Request)
    try
        body = _read_json(req)
        pdb = String(get(body, "pdb_id", ""))
        smiles = String(get(body, "smiles", ""))
        isempty(pdb) && return _bad("pdb_id is required")
        isempty(smiles) && return _bad("smiles is required")
        budget = Float64(get(body, "budget_hours", 24.0))
        run = get(body, "run", false) === true
        _json_response(repurpose_score(pdb, smiles; budget_hours=budget, run=run))
    catch err
        _bad("repurpose-score failed: $(err)"; status=500)
    end
end

function _handle_info(_req::HTTP.Request)
    _json_response(Dict(
        "templates" => String.(string.(list_templates())),
        "backends"  => Dict("openmm" => true, "molly" => true, "gromacs" => true),
    ))
end

function _handle_lint(req::HTTP.Request)
    try
        body = _read_json(req)
        spec_json = String(get(body, "spec_json", ""))
        isempty(spec_json) && return _bad("spec_json is required")
        spec = spec_from_json(spec_json)
        rep = lint(spec)
        _json_response(Dict(
            "ok"        => true,
            "findings"  => [Dict("severity" => String(f.severity),
                                 "rule"     => String(f.rule),
                                 "path"     => f.path,
                                 "message"  => f.message)
                            for f in rep.findings],
            "coverage"  => Dict(
                "total_numeric_fields"   => rep.coverage.total_numeric_fields,
                "fields_with_provenance" => rep.coverage.fields_with_provenance,
                "score"                  => coverage_score(rep.coverage),
                "by_source"              => Dict(String(k) => v for (k, v) in rep.coverage.by_source),
                "missing_paths"          => rep.coverage.missing_paths,
            ),
        ))
    catch err
        _bad("lint failed: $(err)"; status=500)
    end
end

function _handle_coverage(req::HTTP.Request)
    try
        body = _read_json(req)
        spec_json = String(get(body, "spec_json", ""))
        isempty(spec_json) && return _bad("spec_json is required")
        spec = spec_from_json(spec_json)
        cov = provenance_coverage(spec)
        _json_response(Dict(
            "ok"                     => true,
            "total_numeric_fields"   => cov.total_numeric_fields,
            "fields_with_provenance" => cov.fields_with_provenance,
            "score"                  => coverage_score(cov),
            "by_source"              => Dict(String(k) => v for (k, v) in cov.by_source),
            "missing_paths"          => cov.missing_paths,
        ))
    catch err
        _bad("coverage failed: $(err)"; status=500)
    end
end

function _handle_templates(req::HTTP.Request)
    target = req.target
    if target == "/api/templates" || target == "/api/templates/"
        return _json_response(Dict("ok" => true,
            "templates" => [String(n) for n in list_templates()]))
    end
    # /api/templates/<name>
    name = strip(replace(target, "/api/templates/" => "", r"^/api/templates" => ""), '/')
    isempty(name) && return _bad("template name required")
    try
        spec = get_template(Symbol(name))
        _json_response(Dict("ok" => true, "name" => String(name),
                            "spec_json" => spec_to_json(spec)))
    catch err
        _bad("unknown template: $(name)"; status=404)
    end
end

function _handle_parameterize(req::HTTP.Request)
    try
        body = _read_json(req)
        smiles = String(get(body, "smiles", ""))
        isempty(smiles) && return _bad("smiles is required")
        ff = String(get(body, "ff", "openff_sage_2_2_0"))
        sage_version = startswith(ff, "openff_sage_") ?
            replace(ff[length("openff_sage_")+1:end], "_" => ".") : "2.2.0"
        p = OpenFFParameterizer(
            sage_version=sage_version,
            ligand_name=String(get(body, "name", "LIG")),
        )
        if !parameterizer_available(p)
            return _bad("openff-toolkit not installed on server"; status=503)
        end
        outdir = mktempdir(prefix="crucible-param-")
        result = parameterize(p, smiles, outdir)
        _json_response(Dict(
            "ok"             => true,
            "smiles"         => result.smiles,
            "topology_path"  => result.topology_path,
            "coordinates_path" => result.coordinates_path,
            "forcefield"     => String(result.forcefield_name),
            "metadata"       => result.metadata,
        ))
    catch err
        _bad("parameterize failed: $(err)"; status=500)
    end
end

function _router(req::HTTP.Request)
    target = req.target
    method = req.method
    if method == "GET" && (target == "/" || target == "/index.html")
        return HTTP.Response(200, ["content-type" => "text/html"], _INDEX_HTML)
    elseif method == "GET" && target == "/health"
        return _json_response(Dict("status" => "ok"))
    elseif method == "POST" && target == "/api/transpile"
        return _handle_transpile(req)
    elseif method == "POST" && target == "/api/validate"
        return _handle_validate(req)
    elseif method == "POST" && target == "/api/render"
        return _handle_render(req)
    elseif method == "POST" && target == "/api/advise"
        return _handle_advise(req)
    elseif method == "GET" && target == "/api/info"
        return _handle_info(req)
    elseif method == "POST" && target == "/api/repurpose-score"
        return _handle_repurpose_score(req)
    elseif method == "POST" && target == "/api/parameterize"
        return _handle_parameterize(req)
    elseif method == "POST" && target == "/api/lint"
        return _handle_lint(req)
    elseif method == "POST" && target == "/api/coverage"
        return _handle_coverage(req)
    elseif method == "GET" && (target == "/api/templates" || startswith(target, "/api/templates/"))
        return _handle_templates(req)
    end
    HTTP.Response(404, ["content-type" => "application/json"],
                  JSON3.write(Dict("error" => "not found: $(method) $(target)")))
end

"""
    serve_http(; host="0.0.0.0", port=8080)

Start the Crucible HTTP frontend. Blocks until interrupted.

Defaults are read from `CRUCIBLE_HTTP_HOST` (default `"0.0.0.0"`) and
`CRUCIBLE_HTTP_PORT` (default `8080`) when not passed explicitly.
"""
function serve_http(; host::AbstractString=get(ENV, "CRUCIBLE_HTTP_HOST", "0.0.0.0"),
                      port::Int=parse(Int, get(ENV, "CRUCIBLE_HTTP_PORT", "8080")))
    println("crucible: serving on http://$(host):$(port) — Ctrl+C to stop")
    HTTP.serve(_router, host, port)
end
