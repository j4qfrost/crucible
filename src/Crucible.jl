module Crucible

using JSON3
using JSONSchema
using Mustache
using Unitful
using Printf
using SHA
using TOML
using UUIDs

include("spec/units.jl")
include("spec/MDSpec.jl")
include("spec/KineticsSpec.jl")
include("spec/Diff.jl")
include("spec/Migrations.jl")
include("spec/Observables.jl")

include("backends/SimBackend.jl")
include("backends/OpenMMBackend.jl")
include("backends/MollyBackend.jl")
include("backends/KineticsBackend.jl")
include("backends/Router.jl")

include("ligand/Parameterizer.jl")

include("validation/Gates.jl")

include("adapters/InputAdapter.jl")
include("adapters/PDFAdapter.jl")
include("adapters/ArxivAdapter.jl")
include("adapters/BioRxivAdapter.jl")
include("adapters/NotesAdapter.jl")

include("llm/Provider.jl")
include("llm/AnthropicProvider.jl")
include("llm/LocalProvider.jl")
include("llm/RecordedProvider.jl")
include("llm/Transcripts.jl")

include("renderers/Renderer.jl")
include("renderers/PlutoRenderer.jl")
include("renderers/NotebookRenderer.jl")
include("renderers/MarkdownRenderer.jl")
include("renderers/WebRenderer.jl")

include("cloud/Advisor.jl")

export MDSpec, SystemSpec, ForceFieldSpec, Stage, Observable, Provenance,
       SpecDiff, diff_specs, migrate_spec_json, register_migration!,
       read_observable_csv, summarize_observable,
       SimBackend, MollyBackend, OpenMMBackend, KineticsBackend, route_backend,
       KineticsSpec, Species, Reaction,
       LigandParameterizer, OpenFFParameterizer, ParameterizedLigand, parameterize,
       validate_spec, ValidationReport,
       LLMProvider, AnthropicProvider, LocalProvider, RecordedProvider, transpile,
       TranscriptStore, open_transcript_store, close_transcript_store, log_transcript, transcript_count, export_transcripts_jsonl,
       InputAdapter, PDFAdapter, ArxivAdapter, BioRxivAdapter, NotesAdapter,
       PaperRepr, ingest,
       Renderer, PlutoRenderer, NotebookRenderer, MarkdownRenderer, render,
       advise

end # module Crucible
