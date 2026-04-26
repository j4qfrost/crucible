# NotesAdapter — pass-through for raw text the user pasted into the notebook.

struct NotesAdapter <: InputAdapter end

function ingest(::NotesAdapter, text::AbstractString)::PaperRepr
    PaperRepr(
        source_kind = :notes,
        source_id   = "<inline>",
        body_text   = String(text),
    )
end
