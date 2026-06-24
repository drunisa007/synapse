"""Shared Council Review contract fixtures."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

_FIXTURE_DIR = Path(__file__).resolve().parents[4] / "council_review_contract" / "fixtures"
_FORBIDDEN_FRAGMENTS = (
    "raw_prompt",
    "raw_provider_key",
    "provider_key",
    "credential_id",
    "backend_config",
    "sk-",
)


def council_review_fixture(name: str) -> dict[str, Any]:
    data = json.loads((_FIXTURE_DIR / f"{name}.json").read_text(encoding="utf-8"))
    _resolve_refs(data)
    return data


def council_review_contract_fixture(name: str = "approve") -> dict[str, Any]:
    return council_review_fixture(name)["request"]


def assert_no_forbidden_contract_fixture_fragments(value: object) -> None:
    text = json.dumps(value, sort_keys=True)
    lowered = text.lower()
    for fragment in _FORBIDDEN_FRAGMENTS:
        assert fragment not in lowered


def _resolve_refs(data: dict[str, Any]) -> None:
    request = data.get("request")
    settings = data.get("synapse_create_request", {}).get("settings", {})
    if settings.get("council_review") == {"$ref": "request"}:
        settings["council_review"] = request
