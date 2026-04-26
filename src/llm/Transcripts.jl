# TranscriptStore — DuckDB-backed append-only log of LLM transpile sessions.
#
# Phase A of the option-3 roadmap: every (paper_text, MDSpec, validation,
# user_edits) tuple is logged so we can later fine-tune a chem-specialized
# model on (paper, MDSpec) pairs. Same engine as user's sidequest dart_duckdb
# stack — keeps the toolchain consistent.
#
# Schema (transcripts table):
#   id            UUID primary key
#   ts            TIMESTAMP — when the transpile happened
#   provider      VARCHAR — :anthropic | :local | :recorded | ...
#   model         VARCHAR — provider-specific model id
#   paper_kind    VARCHAR — :pdf | :arxiv | :biorxiv | :notes
#   paper_id      VARCHAR — path / arXiv ID / DOI / "<inline>"
#   paper_title   VARCHAR
#   paper_text    TEXT — the body fed to the LLM
#   spec_json     TEXT — emitted MDSpec (or empty string if transpile failed)
#   raw_response  TEXT — provider's full response (for audit)
#   cost_usd      DOUBLE
#   validation_ok BOOLEAN
#   errors        TEXT — JSON array of validator error strings
#   warnings      TEXT — JSON array of validator warning strings
#
# Append-only. Default db path is $XDG_DATA_HOME/crucible/transcripts.duckdb
# (~/.local/share/crucible/transcripts.duckdb on Linux), overridable via
# `CRUCIBLE_TRANSCRIPT_DB` env var or per-call argument.

using DuckDB
using DBInterface
using Dates

const _DEFAULT_DB_FILENAME = "transcripts.duckdb"

function default_transcript_db()::String
    if haskey(ENV, "CRUCIBLE_TRANSCRIPT_DB")
        return ENV["CRUCIBLE_TRANSCRIPT_DB"]
    end
    base = get(ENV, "XDG_DATA_HOME", joinpath(homedir(), ".local", "share"))
    joinpath(base, "crucible", _DEFAULT_DB_FILENAME)
end

const _SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS transcripts (
    id            UUID PRIMARY KEY,
    ts            TIMESTAMP NOT NULL,
    provider      VARCHAR   NOT NULL,
    model         VARCHAR,
    paper_kind    VARCHAR   NOT NULL,
    paper_id      VARCHAR,
    paper_title   VARCHAR,
    paper_text    VARCHAR   NOT NULL,
    spec_json     VARCHAR,
    raw_response  VARCHAR,
    cost_usd      DOUBLE    DEFAULT 0.0,
    validation_ok BOOLEAN,
    errors        VARCHAR,
    warnings      VARCHAR
);
"""

mutable struct TranscriptStore
    path::String
    db::DuckDB.DB
    con::DuckDB.Connection
end

"""
    open_transcript_store(; path = default_transcript_db()) -> TranscriptStore

Opens (or creates) the DuckDB at `path`, ensures the schema, and returns a
handle. Caller is responsible for closing via `close_transcript_store(store)`.
"""
function open_transcript_store(; path::AbstractString = default_transcript_db())::TranscriptStore
    isdir(dirname(path)) || mkpath(dirname(path))
    db = DuckDB.DB(path)
    con = DBInterface.connect(db)
    DBInterface.execute(con, _SCHEMA_SQL)
    TranscriptStore(path, db, con)
end

function close_transcript_store(store::TranscriptStore)
    DBInterface.close!(store.con)
    DuckDB.close_database(store.db)
    nothing
end

"""
    log_transcript(store, paper, result; validation = nothing) -> UUID

Append a row for one transpile session. Returns the row's UUID.
`paper` is a `PaperRepr`; `result` is a `TranspileResult`; `validation`
is an optional `ValidationReport`.
"""
function log_transcript(store::TranscriptStore,
                        paper::PaperRepr,
                        result::TranspileResult;
                        validation::Union{Nothing,ValidationReport} = nothing)::UUID
    id = uuid4()
    ok = validation === nothing ? nothing : validation.ok
    errors_json   = validation === nothing ? "[]" : JSON3.write(validation.errors)
    warnings_json = validation === nothing ? "[]" : JSON3.write(validation.warnings)
    DBInterface.execute(store.con, """
        INSERT INTO transcripts
            (id, ts, provider, model, paper_kind, paper_id, paper_title,
             paper_text, spec_json, raw_response, cost_usd,
             validation_ok, errors, warnings)
        VALUES
            (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
        string(id),
        Dates.now(),
        String(result.provider_name),
        result.model,
        String(paper.source_kind),
        paper.source_id,
        paper.title,
        paper.body_text,
        result.spec_json,
        result.raw_response,
        result.cost_estimate_usd,
        ok,
        errors_json,
        warnings_json,
    ))
    id
end

"""
    transcript_count(store) -> Int

Total number of logged transcripts.
"""
function transcript_count(store::TranscriptStore)::Int
    res = DBInterface.execute(store.con, "SELECT COUNT(*) AS n FROM transcripts")
    first(res).n
end
