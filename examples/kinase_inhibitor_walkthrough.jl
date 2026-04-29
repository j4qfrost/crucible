# Cancer drug-discovery walkthrough: Abl kinase + Imatinib analog FEP.
#
# End-to-end use case showing what crucible does for a real cancer-MD
# problem. No actual python execution — just the IR + render + advise
# + lint + cost path. Run with:
#
#   julia --project examples/kinase_inhibitor_walkthrough.jl
#
# The full workflow (which this example stops short of):
#   1. Render the OpenMM script.
#   2. `pip install openmm openff-toolkit openff-interchange openmmtools openmmforcefields pdbfixer`
#   3. `python /tmp/kinase-walk/run_openmm.py`  (~1 day on an A100)
#   4. Compute ΔG via pymbar.MBAR on /tmp/kinase-walk/fep_4_u_kln.csv.
#
# See docs/CANCER_USE_CASES.md for the full discussion.

using Crucible

println("=" ^ 72)
println("Crucible cancer-MD walkthrough: kinase inhibitor FEP")
println("Reference: PDB 2HYY (Abl + Imatinib)")
println("=" ^ 72)
println()

# 1. Pull the cancer-research template.
spec = get_template(:kinase_inhibitor_fep)
println("[1] Template: kinase_inhibitor_fep")
println("    PDB id:        $(spec.system.source.pdb_id)")
println("    Ligand SMILES: $(first(spec.system.source.ligand_smiles, 60))…")
println("    n_atoms (est): $(spec.system.n_atoms_estimate)")
println("    Protocol:      $(length(spec.protocol)) stages")
println("    Total ns:      $(sum(s isa DynamicsStage ? s.duration_ns :
                                   s isa FEPStage ? length(s.lambda_windows) * s.duration_per_window_ns :
                                   0.0 for s in spec.protocol)) ns of MD wall-time per replicate")
println()

# 2. Validate gates 1-3.
backend = OpenMMBackend()
report = Crucible.run_validation(Crucible.spec_to_json(spec), spec, backend)
println("[2] Validation (gates 1-3): ", report.ok ? "✓ ok" : "✗ FAILED")
for w in report.warnings; println("    warn:  $(w)"); end
for e in report.errors;   println("    error: $(e)"); end
println()

# 3. Lint + coverage in one panel.
lint_rep = Crucible.lint(spec)
cov = Crucible.provenance_coverage(spec)
println("[3] Lint:        $(length(lint_rep.findings)) finding(s)")
for f in lint_rep.findings
    println("       [$(f.severity)] $(f.rule)")
end
println("    Provenance:  $(cov.fields_with_provenance)/$(cov.total_numeric_fields) " *
        "fields (score $(round(Crucible.coverage_score(cov); digits=2)))")
println()

# 4. Cloud sizing — important: kinase systems are ~45k atoms, FEP
# multiplies wall-time by lambda_windows count.
rec = Crucible.advise(spec; budget_hours=48.0, backend_name=:openmm)
if rec.chosen !== nothing
    c = rec.chosen
    println("[4] Cloud sizing (48 h budget):")
    println("       chosen:    $(c.gpu) ($(round(c.vram_gb; digits=0)) GB VRAM)")
    println("       runtime:   $(round(c.runtime_hours; digits=1)) h")
    println("       cost:      \$$(round(c.on_demand_usd; digits=2))")
    println("       fits VRAM: $(c.fits_system ? "✓" : "✗ — pick a larger GPU")")
end
for w in rec.warnings; println("       warn: $(w)"); end
println()

# 5. Render the OpenMM script (no python invocation yet).
script = Crucible.render_script(backend, spec; output_dir="/tmp/kinase-walk")
println("[5] Rendered:    $(length(script)) bytes of OpenMM Python")
println("    Hooks: PDBFixer fetch, SMIRNOFFTemplateGenerator (OpenFF),")
println("           Modeller merge, then NVT → NPT → FEP across 11 λ windows.")
println()

# 6. The generated MDSpec, in human-readable form.
println("[6] What the LLM transpiler should produce when reading a kinase")
println("    inhibitor paper. Crucible's contract: this JSON is the deliverable,")
println("    not a runnable script.")
println()
println("    Snippets:")
println("      schema_version:       $(spec.schema_version)")
println("      system.source.type:   $(spec.system.source.type)")
println("      force_field.protein:  $(spec.force_field.protein)")
println("      force_field.ligand:   $(spec.force_field.ligand)")
fep_stage = spec.protocol[end]
println("      FEP windows:          $(length(fep_stage.lambda_windows)) " *
        "($(first(fep_stage.lambda_windows)) → $(last(fep_stage.lambda_windows)))")
println("      FEP duration/window:  $(fep_stage.duration_per_window_ns) ns")
println("      FEP target:           $(fep_stage.target_selection)")
println()

# 7. Concrete next steps.
println("[7] Next steps for prospective work:")
println("       a. Replace ligand_smiles with your candidate analog.")
println("       b. Cross-check predicted ΔG against a literature reference compound.")
println("       c. Bump duration_per_window_ns to 5+ ns for publication-quality.")
println("       d. Run with a different seed (CRUCIBLE_SEED=...) for replicate statistics.")
println("       e. For drug-resistance mutants, run a parallel FEP with the mutant PDB.")
println()
println("    See docs/CANCER_USE_CASES.md for the broader cancer-MD context.")
println()
println("=" ^ 72)
