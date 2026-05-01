-- Corpus schema (DuckDB).
--
-- Adjacency-tables-as-graph: works, authors, concepts, institutions
-- are nodes; work_authors, work_references, work_concepts,
-- work_institutions are edges. SQL with recursive CTEs handles every
-- query the corpus needs (papers-by-author, coauthor pairs,
-- one-hop / two-hop citation walks). See docs/CORPUS_DESIGN.md.

CREATE TABLE IF NOT EXISTS works (
    work_id          TEXT PRIMARY KEY,
    doi              TEXT,
    title            TEXT,
    abstract         TEXT,
    publication_year INTEGER,
    venue            TEXT,
    cited_by_count   INTEGER DEFAULT 0,
    is_oa            BOOLEAN DEFAULT FALSE,
    pdf_url          TEXT,
    fetched_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS authors (
    author_id        TEXT PRIMARY KEY,
    display_name     TEXT NOT NULL,
    orcid            TEXT,
    h_index          INTEGER,
    works_count      INTEGER,
    last_known_inst  TEXT,
    fetched_at       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS work_authors (
    work_id          TEXT,
    author_id        TEXT,
    position         INTEGER,
    is_corresponding BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (work_id, author_id)
);

CREATE TABLE IF NOT EXISTS work_references (
    citing_work_id   TEXT,
    cited_work_id    TEXT,
    PRIMARY KEY (citing_work_id, cited_work_id)
);

CREATE TABLE IF NOT EXISTS concepts (
    concept_id       TEXT PRIMARY KEY,
    display_name     TEXT,
    level            INTEGER
);

CREATE TABLE IF NOT EXISTS work_concepts (
    work_id          TEXT,
    concept_id       TEXT,
    score            DOUBLE,
    PRIMARY KEY (work_id, concept_id)
);

CREATE INDEX IF NOT EXISTS works_year_idx       ON works (publication_year);
CREATE INDEX IF NOT EXISTS work_authors_aid_idx ON work_authors (author_id);
CREATE INDEX IF NOT EXISTS work_concepts_cid_idx ON work_concepts (concept_id);
CREATE INDEX IF NOT EXISTS work_refs_citing_idx ON work_references (citing_work_id);
CREATE INDEX IF NOT EXISTS work_refs_cited_idx  ON work_references (cited_work_id);
