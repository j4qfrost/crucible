"""Schema-version migrations — Python port of `src/spec/Migrations.jl`.

Forward-only. Every wire-format change adds an entry to `_MIGRATIONS`.
The framework guarantees historical transcripts (option-3 fine-tune
flywheel) remain loadable across schema bumps.
"""

from __future__ import annotations

import copy
import json
from typing import Callable

from .spec import SCHEMA_VERSION

_MIGRATIONS: dict[tuple[str, str], Callable[[dict], dict]] = {}


def register_migration(from_v: str, to_v: str, f: Callable[[dict], dict]) -> None:
    _MIGRATIONS[(from_v, to_v)] = f


def migrate(json_text: str, *, target: str = SCHEMA_VERSION) -> str:
    """Walk the registered migrations from the input's `schema_version` to
    `target`. Returns the migrated JSON. Errors if no path exists."""
    obj = json.loads(json_text)
    src = str(obj.get("schema_version", "unknown"))
    if src == target:
        return json_text
    chain = _migration_chain(src, target)
    if not chain:
        raise ValueError(f"no migration path from {src} to {target}")
    for step in chain:
        f = _MIGRATIONS[step]
        obj = f(obj)
        obj["schema_version"] = step[1]
    return json.dumps(obj)


def _migration_chain(from_v: str, to_v: str) -> list[tuple[str, str]]:
    chain: list[tuple[str, str]] = []
    cursor = from_v
    visited = {cursor}
    while cursor != to_v:
        next_step = None
        for (src, dst) in _MIGRATIONS:
            if src == cursor and dst not in visited:
                next_step = (src, dst)
                break
        if next_step is None:
            return []
        chain.append(next_step)
        cursor = next_step[1]
        visited.add(cursor)
    return chain


# -----------------------------------------------------------------------------
# Bootstrap migrations — must match Julia exactly.

def _migrate_v0_1_to_v0_2(obj: dict) -> dict:
    obj = copy.deepcopy(obj)
    sys = obj.get("system")
    if isinstance(sys, dict):
        src = sys.get("source")
        if isinstance(src, dict) and "ligand_smiles" not in src:
            src["ligand_smiles"] = None
        sol = sys.get("solvent")
        if isinstance(sol, dict) and "membrane" not in sol:
            sol["membrane"] = None
    ff = obj.get("force_field")
    if isinstance(ff, dict) and "lipid" not in ff:
        ff["lipid"] = None
    return obj


def _identity(obj: dict) -> dict:
    return obj


def _migrate_v0_3_to_v0_4(obj: dict) -> dict:
    """0.3.0 → 0.4.0 — adds `system.solvent.padding_nm` (nullable)."""
    obj = copy.deepcopy(obj)
    sys = obj.get("system")
    if isinstance(sys, dict):
        sol = sys.get("solvent")
        if isinstance(sol, dict) and "padding_nm" not in sol:
            sol["padding_nm"] = None
    return obj


register_migration("0.1.0", "0.2.0", _migrate_v0_1_to_v0_2)
register_migration("0.2.0", "0.3.0", _identity)
register_migration("0.3.0", "0.4.0", _migrate_v0_3_to_v0_4)
