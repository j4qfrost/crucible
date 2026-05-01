"""OpenAlex API client — read-only.

Uses the polite pool when `CRUCIBLE_OPENALEX_EMAIL` is set or
`OpenAlexClient(mailto=…)` is passed explicitly. No auth required.

Tests should mock `_http_get` rather than hit the network. A live
smoke test exists under `tests/test_corpus_openalex_live.py` gated by
`CRUCIBLE_LIVE_OPENALEX=1`.

OpenAlex IDs are URLs (`https://openalex.org/A5042929423`); we strip
the prefix and store the bare `A…` / `W…` / `C…` / `I…` token. This
keeps the DuckDB store self-contained.
"""

from __future__ import annotations

import json
import os
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from typing import Iterable, Optional


OPENALEX_BASE = "https://api.openalex.org"


class OpenAlexError(RuntimeError):
    """Raised when OpenAlex returns an error or unexpected payload."""


def _strip_id(s: Optional[str]) -> Optional[str]:
    """`https://openalex.org/A5042929423` → `A5042929423`."""
    if s is None:
        return None
    return s.rsplit("/", 1)[-1]


@dataclass
class Author:
    author_id: str                          # OpenAlex A…
    display_name: str
    orcid: Optional[str] = None
    h_index: Optional[int] = None
    works_count: Optional[int] = None
    last_known_inst: Optional[str] = None


@dataclass
class WorkAuthor:
    author_id: str
    display_name: str
    position: int
    is_corresponding: bool = False


@dataclass
class Work:
    work_id: str                            # OpenAlex W…
    doi: Optional[str]
    title: str
    abstract: Optional[str]
    publication_year: Optional[int]
    venue: Optional[str]
    cited_by_count: int = 0
    is_oa: bool = False
    pdf_url: Optional[str] = None
    authors: list[WorkAuthor] = field(default_factory=list)
    referenced_work_ids: list[str] = field(default_factory=list)
    concept_ids: list[tuple[str, float]] = field(default_factory=list)


# -----------------------------------------------------------------------------
# Abstract reconstruction (OpenAlex stores abstracts as inverted indices).

def _abstract_from_inverted_index(idx: Optional[dict]) -> Optional[str]:
    if not idx:
        return None
    positions: list[tuple[int, str]] = []
    for word, ps in idx.items():
        for p in ps:
            positions.append((p, word))
    positions.sort()
    return " ".join(word for _, word in positions)


# -----------------------------------------------------------------------------
# Client

class OpenAlexClient:
    def __init__(
        self,
        *,
        mailto: Optional[str] = None,
        per_page: int = 200,
        max_pages: int = 50,
        user_agent: str = "crucible-corpus/0.3.0",
    ) -> None:
        self.mailto = mailto or os.environ.get("CRUCIBLE_OPENALEX_EMAIL")
        self.per_page = per_page
        self.max_pages = max_pages
        self.user_agent = user_agent

    # ------------------------------------------------------------------
    # HTTP — single seam to mock in tests.

    def _http_get(self, url: str) -> dict:
        req = urllib.request.Request(
            url,
            headers={"User-Agent": self.user_agent, "Accept": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                payload = resp.read().decode("utf-8")
        except Exception as exc:
            raise OpenAlexError(f"GET {url} failed: {exc}") from exc
        try:
            return json.loads(payload)
        except json.JSONDecodeError as exc:
            raise OpenAlexError(f"non-JSON response from {url}: {exc}") from exc

    def _build_url(self, path: str, **params: object) -> str:
        if self.mailto and "mailto" not in params:
            params["mailto"] = self.mailto
        flat = {k: v for k, v in params.items() if v is not None}
        if flat:
            return f"{OPENALEX_BASE}{path}?{urllib.parse.urlencode(flat)}"
        return f"{OPENALEX_BASE}{path}"

    # ------------------------------------------------------------------
    # Authors

    def find_author(self, name: str) -> Optional[Author]:
        """Find the highest-relevance author matching `name`."""
        url = self._build_url("/authors", search=name, **{"per-page": 1})
        data = self._http_get(url)
        results = data.get("results", [])
        if not results:
            return None
        return self._parse_author(results[0])

    def get_author(self, author_id: str) -> Author:
        url = self._build_url(f"/authors/{author_id}")
        data = self._http_get(url)
        return self._parse_author(data)

    @staticmethod
    def _parse_author(d: dict) -> Author:
        last_inst = None
        lki = d.get("last_known_institution")
        if isinstance(lki, dict):
            last_inst = lki.get("display_name")
        summary = d.get("summary_stats") or {}
        return Author(
            author_id=_strip_id(d.get("id")) or "",
            display_name=d.get("display_name") or "",
            orcid=d.get("orcid"),
            h_index=summary.get("h_index"),
            works_count=d.get("works_count"),
            last_known_inst=last_inst,
        )

    # ------------------------------------------------------------------
    # Works

    def list_works(
        self,
        author_id: str,
        *,
        since: Optional[int] = None,
        concept_id: Optional[str] = None,
    ) -> Iterable[Work]:
        """Yield all works by `author_id`, paginated. Optional filters."""
        filters = [f"author.id:{author_id}"]
        if since is not None:
            filters.append(f"from_publication_date:{since}-01-01")
        if concept_id is not None:
            filters.append(f"concepts.id:{concept_id}")
        cursor = "*"
        for _ in range(self.max_pages):
            url = self._build_url(
                "/works",
                filter=",".join(filters),
                cursor=cursor,
                **{"per-page": self.per_page},
            )
            data = self._http_get(url)
            results = data.get("results") or []
            for r in results:
                yield self._parse_work(r)
            meta = data.get("meta") or {}
            cursor = meta.get("next_cursor")
            if not cursor or not results:
                return

    def get_work(self, work_id: str) -> Work:
        url = self._build_url(f"/works/{work_id}")
        return self._parse_work(self._http_get(url))

    @staticmethod
    def _parse_work(d: dict) -> Work:
        primary_loc = d.get("primary_location") or {}
        venue = None
        src = primary_loc.get("source") or {}
        if isinstance(src, dict):
            venue = src.get("display_name")
        oa = d.get("open_access") or {}
        authorships = d.get("authorships") or []
        wauthors: list[WorkAuthor] = []
        for i, a in enumerate(authorships, start=1):
            author_obj = a.get("author") or {}
            wauthors.append(WorkAuthor(
                author_id=_strip_id(author_obj.get("id")) or "",
                display_name=author_obj.get("display_name") or "",
                position=i,
                is_corresponding=bool(a.get("is_corresponding")),
            ))
        refs = [_strip_id(r) or "" for r in (d.get("referenced_works") or [])]
        concepts_raw = d.get("concepts") or []
        concept_pairs: list[tuple[str, float]] = []
        for c in concepts_raw:
            cid = _strip_id(c.get("id"))
            score = c.get("score")
            if cid and score is not None:
                concept_pairs.append((cid, float(score)))
        return Work(
            work_id=_strip_id(d.get("id")) or "",
            doi=d.get("doi"),
            title=d.get("title") or d.get("display_name") or "",
            abstract=_abstract_from_inverted_index(d.get("abstract_inverted_index")),
            publication_year=d.get("publication_year"),
            venue=venue,
            cited_by_count=d.get("cited_by_count") or 0,
            is_oa=bool(oa.get("is_oa")),
            pdf_url=oa.get("oa_url") or primary_loc.get("pdf_url"),
            authors=wauthors,
            referenced_work_ids=[r for r in refs if r],
            concept_ids=concept_pairs,
        )

    # ------------------------------------------------------------------
    # Concepts (for filtering — e.g. "molecular dynamics" concept ID)

    def find_concept(self, name: str) -> Optional[dict]:
        url = self._build_url("/concepts", search=name, **{"per-page": 1})
        data = self._http_get(url)
        results = data.get("results") or []
        if not results:
            return None
        d = results[0]
        return {
            "concept_id": _strip_id(d.get("id")),
            "display_name": d.get("display_name"),
            "level": d.get("level"),
        }
