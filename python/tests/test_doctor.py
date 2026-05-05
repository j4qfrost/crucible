"""Tests for the `crucible-py doctor` subcommand (v1.82)."""

from __future__ import annotations

import json

import pytest

from crucible.__main__ import main


def test_doctor_basic_runs_clean(capsys, monkeypatch):
    # Drop env vars that would change the output.
    for var in ("CRUCIBLE_PROVIDER", "ANTHROPIC_API_KEY",
                "CRUCIBLE_OPENALEX_EMAIL", "CRUCIBLE_LOCAL_ENDPOINT",
                "CRUCIBLE_HEKATE_PUBLISH_EVENTS"):
        monkeypatch.delenv(var, raising=False)
    rc = main(["doctor"])
    assert rc == 0
    out = capsys.readouterr()
    assert "schema_version" in out.out
    assert "all checks passed" in out.err


def test_doctor_offline_flags_anthropic_key(capsys, monkeypatch):
    """`--offline` with ANTHROPIC_API_KEY set should error out."""
    monkeypatch.setenv("ANTHROPIC_API_KEY", "sk-ant-test")
    monkeypatch.delenv("CRUCIBLE_OPENALEX_EMAIL", raising=False)
    monkeypatch.delenv("CRUCIBLE_HEKATE_PUBLISH_EVENTS", raising=False)
    rc = main(["doctor", "--offline"])
    assert rc >= 1
    err = capsys.readouterr().err
    assert "doctor failed" in err


def test_doctor_offline_flags_hekate_publish(capsys, monkeypatch):
    """`--offline` with hekate-publish enabled should error."""
    monkeypatch.delenv("ANTHROPIC_API_KEY", raising=False)
    monkeypatch.delenv("CRUCIBLE_OPENALEX_EMAIL", raising=False)
    monkeypatch.setenv("CRUCIBLE_HEKATE_PUBLISH_EVENTS", "1")
    rc = main(["doctor", "--offline"])
    assert rc >= 1


def test_doctor_offline_clean_passes(capsys, monkeypatch):
    """With every air-gap-friendly env var set correctly, --offline
    finishes with at most warnings."""
    for var in ("ANTHROPIC_API_KEY", "CRUCIBLE_OPENALEX_EMAIL",
                "CRUCIBLE_HEKATE_PUBLISH_EVENTS"):
        monkeypatch.delenv(var, raising=False)
    monkeypatch.setenv("CRUCIBLE_LOCAL_ENDPOINT", "http://127.0.0.1:11434/v1")
    rc = main(["doctor", "--offline"])
    assert rc == 0    # warnings don't fail; only errors do


def test_doctor_offline_warns_on_non_local_endpoint(capsys, monkeypatch):
    """Public-network endpoint should warn (not error)."""
    for var in ("ANTHROPIC_API_KEY", "CRUCIBLE_OPENALEX_EMAIL",
                "CRUCIBLE_HEKATE_PUBLISH_EVENTS"):
        monkeypatch.delenv(var, raising=False)
    monkeypatch.setenv("CRUCIBLE_LOCAL_ENDPOINT", "https://api.openai.com/v1")
    rc = main(["doctor", "--offline"])
    out = capsys.readouterr()
    assert rc == 0    # only a warning
    assert "private-net" in out.out


def test_doctor_json_output(capsys, monkeypatch):
    for var in ("ANTHROPIC_API_KEY", "CRUCIBLE_OPENALEX_EMAIL",
                "CRUCIBLE_HEKATE_PUBLISH_EVENTS",
                "CRUCIBLE_LOCAL_ENDPOINT", "CRUCIBLE_PROVIDER"):
        monkeypatch.delenv(var, raising=False)
    rc = main(["doctor", "--format", "json"])
    assert rc == 0
    parsed = json.loads(capsys.readouterr().out)
    assert isinstance(parsed, list)
    names = {row["name"] for row in parsed}
    assert "schema_version" in names
    assert "pydantic" in names
