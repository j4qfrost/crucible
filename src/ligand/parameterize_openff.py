#!/usr/bin/env python3
"""SMILES -> AMBER parm7/rst7 via openff-toolkit + Interchange.

Invoked as a subprocess by Crucible.OpenFFParameterizer (Julia). Emits a
single JSON status line on stdout for the Julia caller to parse.

Inputs (positional):
    smiles      e.g. "CCO" (ethanol) or "Cc1ccc(cc1)NC(=O)c2cccnc2"
    output_dir  directory to write ligand.parm7, ligand.rst7, ligand.pdb
    sage_version e.g. "2.2.0"

Optional env:
    CRUCIBLE_LIGAND_NAME    residue name in the topology (default LIG)
    CRUCIBLE_OPENFF_VERBOSE 1 to log progress to stderr

Exits 0 on success, non-zero on failure. The error path always emits a
JSON line with {"status":"error","error":"..."} so the Julia caller can
present a friendly message.

Hard rule (per Crucible's design): this script never invents force-field
parameters. The OpenFF Sage release supplies typing + LibraryCharges /
AM1-BCC. We do not patch missing parameters silently.
"""

from __future__ import annotations

import json
import os
import sys
import traceback
from pathlib import Path


def _emit(payload: dict) -> None:
    print(json.dumps(payload), flush=True)


def main() -> int:
    if len(sys.argv) < 4:
        _emit({"status": "error",
               "error": "usage: parameterize_openff.py <smiles> <output_dir> <sage_version>"})
        return 2

    smiles = sys.argv[1]
    output_dir = Path(sys.argv[2])
    sage_version = sys.argv[3]
    ligand_name = os.environ.get("CRUCIBLE_LIGAND_NAME", "LIG")
    verbose = os.environ.get("CRUCIBLE_OPENFF_VERBOSE") == "1"

    output_dir.mkdir(parents=True, exist_ok=True)

    try:
        from openff.toolkit import Molecule, ForceField
        from openff.units import unit as off_unit
    except ImportError as e:
        _emit({"status": "error",
               "error": f"openff-toolkit not installed ({e}). pip install openff-toolkit openff-interchange rdkit"})
        return 3

    try:
        if verbose:
            print(f"[openff] SMILES = {smiles!r}", file=sys.stderr)
        mol = Molecule.from_smiles(smiles, allow_undefined_stereo=True)
        mol.name = ligand_name
        mol.generate_conformers(n_conformers=1)
        if verbose:
            print(f"[openff] generated 1 conformer for {ligand_name}", file=sys.stderr)
    except Exception as e:
        _emit({"status": "error",
               "error": f"SMILES parse / conformer generation failed: {e}"})
        return 4

    try:
        ff_filename = f"openff-{sage_version}.offxml"
        if verbose:
            print(f"[openff] loading {ff_filename}", file=sys.stderr)
        forcefield = ForceField(ff_filename)
    except Exception as e:
        _emit({"status": "error",
               "error": f"could not load OpenFF Sage {sage_version}: {e}"})
        return 5

    try:
        if verbose:
            print(f"[openff] computing AM1-BCC charges (this may take 10-60s)", file=sys.stderr)
        mol.assign_partial_charges(partial_charge_method="am1bcc")
    except Exception as e:
        _emit({"status": "error",
               "error": f"AM1-BCC charge assignment failed (need RDKit + AmberTools or NAGL): {e}"})
        return 6

    try:
        interchange = forcefield.create_interchange(
            topology=mol.to_topology(),
            charge_from_molecules=[mol],
        )
    except Exception as e:
        _emit({"status": "error",
               "error": f"Interchange construction failed: {e}"})
        return 7

    parm7 = output_dir / "ligand.parm7"
    rst7 = output_dir / "ligand.rst7"
    pdb = output_dir / "ligand.pdb"

    try:
        interchange.to_prmtop(parm7)
        interchange.to_inpcrd(rst7)
        interchange.to_pdb(pdb)
    except Exception as e:
        _emit({"status": "error",
               "error": f"AMBER export failed: {e}"})
        return 8

    _emit({
        "status": "ok",
        "smiles": smiles,
        "ligand_name": ligand_name,
        "forcefield": f"openff_sage_{sage_version.replace('.', '_')}",
        "topology_path": str(parm7),
        "coordinates_path": str(rst7),
        "pdb_path": str(pdb),
        "n_atoms": int(mol.n_atoms),
        "total_charge": float(sum(c.m_as(off_unit.elementary_charge)
                                  for c in mol.partial_charges)),
    })
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        _emit({"status": "error",
               "error": f"unexpected: {traceback.format_exc()}"})
        sys.exit(99)
