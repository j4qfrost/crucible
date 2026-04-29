# Why dual CI (Woodpecker + GitHub Actions)

Crucible runs `.github/workflows/ci.yml` AND `.woodpecker.yml` on
every push. Two pipelines, same matrix (Julia 1.10 + 1.11 + opt-in
OpenMM smoke), same test commands. Why duplicate?

## The story

The repo's CI started on GitHub Actions in 2026-04-25. It went red on
day 2 — not from a test failure, but from GitHub clamping free
private-repo runner minutes. Crucible is private; the free tier on
private repos is 2,000 minutes/month, and a Julia 1.10/1.11 matrix
plus an OpenMM venv install eats ~3 minutes per push. A dozen pushes
a day exhausts the budget in a week.

The first response was to delete `.github/workflows/` and run CI
exclusively on Woodpecker, which lives on snowman (the user's GPU
workstation) — free at the marginal byte but visible only on the
Tailscale network.

The second response was to put Actions back on top of Woodpecker, so
the public-facing pipeline (badge in README, PR-status checks for
external collaborators) still works. Two pipelines.

## What each one is for

**Woodpecker**:
- The load-bearing pipeline for solo development.
- Runs even if GitHub clamps minutes again.
- On the Tailscale network — only the developer (and anyone on the
  tailnet) can see it.
- Hosts the GPU smoke step (the runner has the GPU; GitHub-hosted
  runners don't).
- Less noisy badge — not exposed to the public README, so a flaky
  network glitch doesn't show up in the project's reputation.

**GitHub Actions**:
- Public-facing. The README badge points at it.
- Required-checks gate for any external contributor's PR.
- Where the gpu-smoke workflow targets a self-hosted runner (the
  same snowman host, registered with `tools/gha-runner-setup.sh` or
  `tools/runner.Dockerfile`).
- Burns minutes — but the Anthropic key is already a paid expense,
  so a small amount of Actions usage is acceptable.

## Why not pick one?

We tried. Both modes failed at different times.

- **GH-only**: failed when minutes ran out. The fix would be a paid
  GH plan. Possible but a $0/month avoidable cost.
- **Woodpecker-only**: failed in two ways. (a) External contributors
  can't see the CI status — Woodpecker is on the tailnet. (b) The
  GitHub PR review UI loses the green checkmark, which makes the
  project look broken from the outside even when it's healthy.

Dual CI is the cheapest way to satisfy both audiences. It costs ~30
minutes of duplicate work to keep both YAMLs in sync (see
`AGENTS.md` § CI for the contract).

## What goes wrong with dual CI

Two real failure modes:

1. **Drift between the two YAMLs.** A new step added to one but not
   the other. We've hit this; the hygiene is "always edit both".
   The CONTRIBUTING.md hard rule covers it; future contributors
   should keep them in lockstep until/unless we automate.

2. **Different exit codes for the same failure.** Woodpecker's exit
   handling is more permissive than GHA's. We had a case where a
   step that printed an error but exited 0 went green on Woodpecker
   and red on GHA. Resolution: write CI steps that fail explicitly
   (`exit 1` on every error path), don't rely on the runner's
   inference.

## When to drop one

If GitHub raises the private-repo runner minutes for free tier (or
the project goes public), the rationale for Woodpecker weakens. The
GPU smoke is the remaining justification — a self-hosted runner
under either CI is the same operational cost. At that point we'd
likely move everything to GHA self-hosted and drop Woodpecker.

Until then: keep both.

## The minimum viable invariant

Whatever goes into CI **must** be runnable in the docker test loop:

```
docker run --rm -v "$PWD":/work -v /tmp/crucible-depot:/julia-depot \
  -w /work -e JULIA_DEPOT_PATH=/julia-depot julia:1.10 \
  bash -c 'julia --project -e "using Pkg; Pkg.test()"'
```

This is the developer's local equivalent. If a CI step needs
something the docker loop doesn't have, we're drifting toward "works
on the runner, broken locally" — which is the failure mode CI was
supposed to *prevent*. Catch this in review.
