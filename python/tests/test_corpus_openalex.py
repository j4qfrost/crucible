"""Tests for the OpenAlex client. HTTP is mocked at `_http_get`."""

from __future__ import annotations

from unittest.mock import patch

import pytest

from crucible.corpus.openalex import (
    OpenAlexClient,
    OpenAlexError,
    _abstract_from_inverted_index,
    _strip_id,
)


def test_strip_id_handles_url_form():
    assert _strip_id("https://openalex.org/A5042929423") == "A5042929423"
    assert _strip_id("A5042929423") == "A5042929423"
    assert _strip_id(None) is None


def test_abstract_from_inverted_index_reconstructs_word_order():
    idx = {"the": [0, 4], "molecular": [1], "dynamics": [2], "of": [3], "system": [5]}
    out = _abstract_from_inverted_index(idx)
    assert out == "the molecular dynamics of the system"


def test_abstract_from_inverted_index_handles_missing():
    assert _abstract_from_inverted_index(None) is None
    assert _abstract_from_inverted_index({}) is None


def test_build_url_includes_polite_pool_email():
    c = OpenAlexClient(mailto="alice@example.com")
    url = c._build_url("/authors", search="john")
    assert "mailto=alice%40example.com" in url
    assert "search=john" in url


def test_build_url_omits_mailto_when_not_set(monkeypatch):
    monkeypatch.delenv("CRUCIBLE_OPENALEX_EMAIL", raising=False)
    c = OpenAlexClient()
    url = c._build_url("/authors", search="john")
    assert "mailto=" not in url


def test_find_author_parses_payload():
    c = OpenAlexClient()
    fake = {
        "results": [{
            "id": "https://openalex.org/A5042929423",
            "display_name": "John D. Chodera",
            "orcid": "https://orcid.org/0000-0003-0542-119X",
            "works_count": 245,
            "summary_stats": {"h_index": 56},
            "last_known_institution": {"display_name": "Memorial Sloan Kettering"},
        }],
    }
    with patch.object(c, "_http_get", return_value=fake):
        a = c.find_author("John Chodera")
    assert a is not None
    assert a.author_id == "A5042929423"
    assert a.display_name == "John D. Chodera"
    assert a.h_index == 56
    assert a.last_known_inst == "Memorial Sloan Kettering"


def test_find_author_returns_none_on_no_results():
    c = OpenAlexClient()
    with patch.object(c, "_http_get", return_value={"results": []}):
        assert c.find_author("Nobody Realname") is None


def test_list_works_paginates_and_parses():
    c = OpenAlexClient(per_page=2, max_pages=3)
    page_1 = {
        "results": [_fake_work("W1", "Alchemical FEP review"),
                    _fake_work("W2", "openmmtools 1.0")],
        "meta": {"next_cursor": "cursor2"},
    }
    page_2 = {
        "results": [_fake_work("W3", "Implicit-solvent free energy")],
        "meta": {"next_cursor": None},
    }
    with patch.object(c, "_http_get", side_effect=[page_1, page_2]):
        works = list(c.list_works("A5042929423", since=2018))
    assert [w.work_id for w in works] == ["W1", "W2", "W3"]
    assert works[0].title == "Alchemical FEP review"
    assert works[0].authors[0].author_id == "A5042929423"
    assert works[0].referenced_work_ids == ["W999"]


def test_list_works_stops_on_empty_page():
    c = OpenAlexClient(per_page=10, max_pages=10)
    empty = {"results": [], "meta": {"next_cursor": None}}
    with patch.object(c, "_http_get", return_value=empty) as m:
        works = list(c.list_works("A1"))
    assert works == []
    # Single call, no infinite loop
    assert m.call_count == 1


def test_http_get_raises_openalex_error_on_bad_json():
    c = OpenAlexClient()
    import urllib.request
    class _FakeResp:
        def __init__(self, body): self.body = body
        def __enter__(self): return self
        def __exit__(self, *exc): pass
        def read(self): return self.body
    with patch("urllib.request.urlopen", return_value=_FakeResp(b"not json")):
        with pytest.raises(OpenAlexError):
            c._http_get("https://api.openalex.org/foo")


# -----------------------------------------------------------------------------
# Helpers

def _fake_work(wid: str, title: str) -> dict:
    return {
        "id": f"https://openalex.org/{wid}",
        "doi": "https://doi.org/10.1000/x",
        "display_name": title,
        "title": title,
        "publication_year": 2022,
        "abstract_inverted_index": {"abstract": [0]},
        "primary_location": {
            "source": {"display_name": "JCTC"},
            "pdf_url": None,
        },
        "open_access": {"is_oa": True, "oa_url": f"https://example.com/{wid}.pdf"},
        "cited_by_count": 17,
        "authorships": [{
            "author": {"id": "https://openalex.org/A5042929423",
                       "display_name": "John D. Chodera"},
            "is_corresponding": True,
        }],
        "referenced_works": ["https://openalex.org/W999"],
        "concepts": [
            {"id": "https://openalex.org/C123", "score": 0.9},
        ],
    }
