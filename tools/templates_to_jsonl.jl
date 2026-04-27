# tools/templates_to_jsonl.jl — export every Crucible template as an
# (paper_text_stub, MDSpec_json) JSONL pair, for the option-3
# fine-tune corpus.
#
# Each template has a hand-written `notes` field that doubles as the
# matching paper-text stub for training. Real training pairs come from
# logged user sessions (TranscriptStore); this script seeds the corpus
# with idealized examples that demonstrate "what good extraction looks
# like" for each method category.
#
# Usage:
#   julia --project tools/templates_to_jsonl.jl > seed.jsonl
#   julia --project tools/templates_to_jsonl.jl --out seed.jsonl
#
# Trade-off chosen: each template's `notes` becomes the "paper text"
# stub. Real papers are dramatically wordier; this is fine for SFT-style
# training where short prompts pair with structured outputs, but
# downstream training code may want to expand the stubs into longer
# prose via a second LLM call before final training.

using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Crucible
import JSON3

function main(args)
    out_path = ""
    i = 1
    while i <= length(args)
        if args[i] == "--out" && i+1 <= length(args)
            out_path = args[i+1]; i += 2
        else
            i += 1
        end
    end
    sink = isempty(out_path) ? stdout : open(out_path, "w")
    n = 0
    try
        for name in list_templates()
            spec = get_template(name)
            entry = Dict{String,Any}(
                "id"             => "template:$(name)",
                "paper_text"     => spec.notes,
                "spec_json"      => JSON3.read(Crucible.spec_to_json(spec), Dict),
                "schema_version" => spec.schema_version,
                "method_kind"    => String(name),
                "split"          => "synthetic_seed",
            )
            println(sink, JSON3.write(entry))
            n += 1
        end
    finally
        sink === stdout || close(sink)
    end
    println(stderr, "wrote $(n) entries", isempty(out_path) ? "" : " to $(out_path)")
end

main(ARGS)
