#!/usr/bin/env julia
# Cross-language round-trip: read MDSpec JSON from stdin (one JSON per line),
# parse with Crucible.spec_from_json, serialize back with Crucible.spec_to_json,
# emit the serialized form to stdout (one JSON per line).
#
# Used by python/tests/test_cross_language_consistency.py to pin the
# cross-language invariant: a spec emitted by the Python pydantic models
# must round-trip byte-equivalent through the Julia loader.
#
# Single Julia process per pytest run amortizes the ~3s startup over N specs.
#
# Usage:
#     cat python_emitted.jsonl | julia --project=. tools/cross_lang_roundtrip.jl
#
# Exits non-zero on any parse failure (which is itself a useful test signal).

using Crucible

for line in eachline(stdin)
    line = strip(line)
    isempty(line) && continue
    try
        spec = Crucible.spec_from_json(line)
        # Re-serialize and emit. The downstream Python test compares
        # parsed-as-dict equality, not byte equality (key order isn't a
        # contract; field values are).
        println(Crucible.spec_to_json(spec))
    catch err
        @error "cross_lang_roundtrip: parse failure" err=string(err) line=line
        rethrow()
    end
end
