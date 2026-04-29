# Why HTTP.jl, not Genie (web frontend choice)

The v0 plan listed `WebRenderer` as a stub for a future Genie.jl
frontend. v1.0 shipped a real `WebRenderer` — but on raw HTTP.jl, not
Genie. This is the story.

## What Genie is

Genie.jl is the canonical Julia web framework. Rails-style: routing
DSL, controllers, view templates, ORM (SearchLight), websocket
support, hot-reload. Battle-tested for full-stack web apps in Julia.

## What Crucible's web frontend actually is

Eight endpoints (`GET /`, `GET /health`, `POST /api/transpile`,
`POST /api/validate`, `POST /api/render`, `POST /api/advise`,
`POST /api/parameterize`, plus `GET /api/templates[/<name>]`). One
single-page UI baked into a string literal in `WebRenderer.jl`. No
authentication, no database, no websocket, no template engine.

The single-page UI is ~150 lines of HTML/CSS/JS that talks to those
endpoints with `fetch()`. Total backend logic outside the handlers
is the tiny markdown→HTML helper for the standalone-HTML report.

## What we considered

### Option A: Genie.jl

Heavy:
- ~50 transitive deps
- Genie's bootstrap takes ~3-5s on a cold cache
- ORM/template/websocket machinery we don't use
- "Generated app" scaffold doesn't fit a 1-file renderer pattern

Light:
- Idiomatic for Julia
- Routing DSL is nice to read
- Has people who've used it before

### Option B: HTTP.jl directly (what we shipped)

Heavy:
- Hand-roll routing — `req.target` if/elseif tree
- Hand-roll the SPA HTML
- No middleware out of the box

Light:
- ~5 transitive deps (HTTP.jl is already in our deps for `LocalProvider`)
- Bootstrap is instant (~50ms)
- Single file, easy to read end-to-end
- One handler-per-endpoint pattern is easy to test (the tests hit
  `Crucible._router(::HTTP.Request)` directly with mock requests —
  no server boot, no port binding)

## Why HTTP.jl won

### 1. The endpoint count is fixed

We have 8 endpoints. We're not going to grow to 80. The IR-first
design means every "feature" is a new IR axis, not a new web
endpoint. Genie's value-add scales with endpoint count + feature
count; crucible's web layer is essentially complete.

### 2. The SPA is a single string

The whole frontend is `_INDEX_HTML` — a Julia const string with the
HTML/CSS/JS inline. Genie's view layer (templates, partials, asset
pipeline) is overkill for "one HTML page that fits in a screen of
source code."

If the SPA grows beyond one screen, we'd carve it out — but the next
step would be to ship it as a separate static-asset directory served
from `crucible serve`, not to adopt Genie's template engine.

### 3. Tests need a router function, not a server

`test/web_test.jl` uses `Crucible._router(_req("POST", "/api/lint",
body))` — the router is just a function from `HTTP.Request` to
`HTTP.Response`. We can call it in unit tests without binding a port,
without waiting for a worker pool, without coordinating shutdown.

The first version of `web_test.jl` *did* bind a real port (with
`HTTP.serve!(...)` + `HTTP.get(...)`). It hung in CI at ~50% reliability.
The fix was to drop the server boot and call the router function
directly. Genie's request lifecycle is harder to short-circuit this
way.

### 4. The endpoint contract is the JSON, not the HTTP framework

The `/api/transpile`-shape contract is "JSON in, JSON out, with these
fields." Whether HTTP.jl or Genie or a Rust axum server hosts it
doesn't matter. Picking the lightest framework keeps the project's
dependency surface small without locking in a Julia-only future. If
a user wants to wire crucible's API into their own FastAPI server,
they can — the contract is the JSON.

### 5. Bootstrap latency matters for the dev loop

A `crucible serve` invocation should be live within a second. With
HTTP.jl, the first request lands ~100ms after the shell prompt
returns. With Genie, it's 3-5s of cold-load. For a CLI tool that the
user expects to behave like `python -m http.server`, the latency
matters.

## When to revisit

The reasons above hold up for Crucible's current shape (offline IR
tools + a small web layer). If any of these become true, reopen the
question:

- The web frontend grows beyond a single SPA — say, multi-user
  dashboards, persistent state across users.
- Auth/sessions become real requirements (SSO, role-based access).
- Real-time WebSocket streams become necessary (live progress
  reporting on a running simulation).
- The endpoint count exceeds ~20 and the if/elseif router becomes
  hard to maintain.

Until then: HTTP.jl is the right tool. Genie isn't wrong; it's just
overkill.

## The minimal-viable router

For reference, the entire dispatch is this function:

```julia
function _router(req::HTTP.Request)
    target = req.target
    method = req.method
    if method == "GET" && (target == "/" || target == "/index.html")
        return HTTP.Response(200, ["content-type" => "text/html"], _INDEX_HTML)
    elseif method == "GET" && target == "/health"
        return _json_response(Dict("status" => "ok"))
    # … 7 more elseif arms …
    end
    HTTP.Response(404, ["content-type" => "application/json"],
                  JSON3.write(Dict("error" => "not found: $(method) $(target)")))
end
```

That's the whole framework. Anything Genie would add — middleware,
controllers, model binding — would obscure rather than clarify this.
