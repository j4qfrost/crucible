# Visualization (and what's deliberately out of scope)

Crucible isn't a 3D molecular viewer. The mature tools (PyMOL, VMD,
ChimeraX, NGL) are better at rendering atoms than anything Crucible
could ship in-house. What Crucible *does* ship is the layer right
above and right below: **trajectory artifacts** that those tools
load directly, and **time-series plots + critical-moment detection**
that summarize the run without needing the 3D pixels.

This doc walks through both, plus the integration recipes for
hand-off to PyMOL / VMD / ChimeraX / NGL.

## What Crucible ships

### Time-series PNG plots

Every observable (rmsd, rmsf, rg, sasa, distance, hbonds) emits a
CSV during the run. `crucible plot` shells out to matplotlib and
writes one PNG per CSV:

```bash
crucible plot runs/2026-04-29/
# →  runs/2026-04-29/plots/rmsd.png
#    runs/2026-04-29/plots/rg.png
#    …
```

Trade-off: shell-to-python (subprocess) instead of a Julia plotting
package — matches the project's existing
subprocess-over-PythonCall precedent (`musings/why_subprocess_over_pythoncall.md`).
Needs matplotlib; skips cleanly when missing.

### Critical-moment detection

`crucible events` walks the same CSVs and flags moments worth
looking at:

| Rule | Detects | Default threshold |
|---|---|---|
| `:rmsd_jump` | Frame-to-frame RMSD Δ above z-score | z > 3.0 |
| `:rg_expansion` | Frame-to-frame Rg Δ above z-score | z > 3.0 |
| `:distance_crossing` | Distance crosses a threshold | 0.6 nm (covalent → nonbonded) |
| `:hbond_drop` | Running-mean H-bond count drops by ≥ N% | 50% over 10 frames |
| `:energy_spike` | Total Energy z-score above threshold | z > 3.0 (rolling 50-frame window) |

```bash
crucible events runs/2026-04-29/ --format markdown
# Markdown table you can paste into a lab notebook or PR.
```

Output is heuristic, not definitive. The point is: a student or
reviewer should look at flagged frames in the actual 3D viewer to
understand *what* the event was. The thresholds default to "more
events, false positives OK" because missing a critical moment is
the worse failure mode for a learning audience. Tune via flags when
your system needs different sensitivity.

### Annotated plots

Combine the two:

```bash
crucible plot runs/2026-04-29/ --annotate
# → PNGs with red vertical lines at each detected event
```

This is the closest thing Crucible has to "label critical moments
on a timeline." It's a 2D summary; the 3D investigation happens in
PyMOL/VMD.

## What Crucible deliberately does NOT ship

### Embedded 3D particle viewer

The web SPA (`crucible serve`) does not show atoms. It shows the
spec, the validation report, the lint findings, the cloud
recommendation — pieces of metadata. Adding an embedded NGL.js
viewer would mean:

- ~1 MB JavaScript bundle baked into `_INDEX_HTML`
- A trajectory-streaming endpoint (currently `crucible serve`
  doesn't host workdir contents)
- Re-implementation of features PyMOL/VMD/ChimeraX have had for
  20+ years

Trade-off: out of scope. `crucible serve` is for pre-run triage
(spec quality, cost, lint); 3D investigation happens after the run
in dedicated tools.

### Real-time particle visualization during a run

OpenMM has live-visualization paths (the `OpenMM-Setup`
companion, plus the `nglview` jupyter integration), but Crucible's
`crucible run` is a fire-and-monitor-stdout pattern. Real-time
3D would require process-internal interaction (Python ↔ JS via a
notebook kernel) — also out of scope.

### Pedagogical "show me how MD works" animations

There's a separate market here (NGL's "molecular movies",
[mdaencore](https://github.com/MDAnalysis/MDAnalysis-tutorials),
the openmmtutorials notebooks). Crucible doesn't compete; it
focuses on the IR + render + validate + reduce loop.

## Hand-off recipes

Once you have a workdir with a trajectory + topology, here's how to
load it into the major viewers.

### PyMOL

```bash
# After crucible run wrote production_4_traj.dcd + a topology PDB
pymol runs/2026-04-29/1ubq_complex.pdb
# In PyMOL:
load_traj runs/2026-04-29/production_4_traj.dcd, complex, format=dcd
intra_fit complex     # align by backbone
mplay
```

For automated PNG snapshots of flagged frames:

```bash
crucible events runs/2026-04-29/ --format json | jq '.[].frame' > frames.txt
# Then in a PyMOL script:
#   load complex.pdb
#   load_traj production_4_traj.dcd
#   for f in <flagged frames>: png frame_$f.png
```

### VMD

```bash
vmd -e load_session.tcl
# load_session.tcl:
mol new runs/2026-04-29/1ubq_complex.pdb
mol addfile runs/2026-04-29/production_4_traj.dcd type dcd waitfor all
animate goto <flagged frame from crucible events>
```

VMD scripts can iterate through Crucible's flagged frames directly:

```tcl
# vmd_jump_to_events.tcl
set frames {123 456 789 1024}    ;# from crucible events --format json
foreach f $frames {
    animate goto $f
    render snapshot frame_${f}.tga
}
```

### ChimeraX

```
open runs/2026-04-29/1ubq_complex.pdb
open runs/2026-04-29/production_4_traj.dcd structureModel #1
mseries play
```

For programmatic access to the flagged frames, ChimeraX has a Python
API; you can subprocess `crucible events --format json` to get the
list.

### NGL viewer (notebook / web)

```python
import nglview as nv
import mdtraj as md

t = md.load("runs/2026-04-29/production_4_traj.dcd",
            top="runs/2026-04-29/1ubq_complex.pdb")
view = nv.show_mdtraj(t)
view.add_representation('cartoon', selection='protein')
view.add_representation('licorice', selection='resname LIG')

# Jump to a flagged frame from `crucible events`:
import json, subprocess
events = json.loads(subprocess.check_output(
    ["crucible", "events", "runs/2026-04-29/", "--format", "json"]))
view.frame = events[0]["frame"]
```

This is the closest thing to "embedded 3D viewer with critical-
moment labels" — it's a notebook pattern, not an embedded SPA
feature, but it composes the existing tools.

## What's a learning-oriented user looking for that we DON'T have

To be honest about gaps a student / teaching audience might want:

1. **An embedded SPA viewer with auto-paused playback at events.**
   Possible follow-on; would need the design choices above. Open
   issue if desired.

2. **Animated explanations of what each stage of the protocol does.**
   E.g., a small MP4 showing minimization → equilibration →
   production → FEP for a single template. Would be a one-time
   educational asset, not a runtime feature.

3. **Force-vector overlays on each atom.** Rendering forces is
   itself a research question (the largest forces dominate the
   visual; meaningful structure is usually in the residual).
   PyMOL's `arrow` API + a custom per-frame extraction would build
   this; not a Crucible feature.

4. **Pre-built tutorial trajectories with labeled events.** Useful
   for a course; would need ~1 GB of trajectory data per template,
   which is too much to ship in the repo. A separate
   `crucible-tutorials` companion repo would be the right home.

The current scope is: text + tables + 2D plots + flagged frames in
JSON. Those compose with PyMOL/VMD/ChimeraX/NGL to give 3D where it
matters. If a teaching use case needs more, file an issue with a
specific user story — the framework's there to extend.

## See also

- `crucible plot --help` — the CLI reference.
- `crucible events --help` — the CLI reference.
- `examples/kinase_inhibitor_walkthrough.jl` — end-to-end use case
  showing what plot + events look like in practice.
- `musings/why_no_genie.md` — the "small endpoint count, no
  embedded viewer" reasoning.
