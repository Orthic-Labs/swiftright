from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
V7 = ROOT / "factory/shell/extended-demand-mapping-v7/mapping-v7-action-overlay.json"
V6 = ROOT / "factory/shell/extended-demand-mapping-v6/mapping-v6-overlay.json"
REGISTRY = ROOT / "factory/registry/evidence/block-registry.json"
EXPECTED_V7_SHA256 = "9617a692eff9607056e217d50842f543b1dd54795f75720f8ed0f532beb6b5f3"
EXPECTED_V6_SHA256 = "f806795690e20f1221d218ba5531094b97e95d3300ebc9aef229c5633d057a89"
EXPECTED_ROW_KEYS = {
    "f12-extended-001", "f12-extended-002", "f12-extended-013", "f12-extended-014",
    "f12-extended-017", "f12-extended-039", "f12-extended-040", "f12-extended-045",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _require(condition: Any, message: str) -> None:
    if not condition:
        raise ValueError(message)


def _integer(value: Any, expected: int, name: str) -> None:
    _require(type(value) is int and value == expected, f"{name} must be integer {expected}")


def verify(path: Path | str = HERE / "mapping-v8-action-overlay.json") -> dict[str, Any]:
    target = Path(path)
    data = json.loads(target.read_text(encoding="utf-8"))
    prior = json.loads(V7.read_text(encoding="utf-8"))
    base = json.loads(V6.read_text(encoding="utf-8"))
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))

    _require(sha256(V7) == EXPECTED_V7_SHA256, "pinned v7 overlay changed")
    _require(sha256(V6) == EXPECTED_V6_SHA256, "pinned v6 overlay changed")
    _require(prior.get("kind") == "extended-demand-mapping-v7-action-overlay", "unexpected v7 kind")
    _require(prior.get("status") == "requirements-only", "v7 is not requirements-only")
    _integer(prior.get("denominator"), 107, "v7 denominator")
    _require(prior.get("baseOverlayPath") == "factory/shell/extended-demand-mapping-v6/mapping-v6-overlay.json", "v7 lineage path drift")
    _require(prior.get("baseOverlaySha256") == EXPECTED_V6_SHA256 and sha256(V6) == EXPECTED_V6_SHA256, "v7 v6-lineage pin mismatch")
    _require(prior.get("registrySnapshotPath") == "factory/registry/evidence/block-registry.json", "v7 registry path drift")
    _require(prior.get("registrySnapshotSha256") == sha256(REGISTRY), "v7 registry byte pin mismatch")
    _integer(base.get("denominator"), 107, "v6 denominator")
    _require(len(base.get("remainingUnresolved", [])) == 5, "v6 unresolved count drift")
    _require(len(base.get("ambiguousRows", [])) == 3, "v6 ambiguous count drift")

    _require(data.get("kind") == "extended-demand-mapping-v8-action-overlay", "unexpected v8 kind")
    _require(data.get("version") == "8", "unexpected v8 version")
    _require(data.get("status") == "requirements-only", "v8 must remain requirements-only")
    for field in ("denominator", "rowCount", "baseRowCountPreserved"):
        _integer(data.get(field), 107, field)
    _require(data.get("partialOverlapsPreserved") is True, "partial overlap preservation must be true")
    _integer(data.get("newFullDemandResolutions"), 0, "newFullDemandResolutions")
    _integer(data.get("registryPromotion"), 0, "registryPromotion")
    _require(data.get("baseOverlayPath") == "factory/shell/extended-demand-mapping-v7/mapping-v7-action-overlay.json", "base path drift")
    _require(data.get("baseOverlaySha256") == EXPECTED_V7_SHA256 and sha256(V7) == data.get("baseOverlaySha256"), "v7 byte pin mismatch")
    _require(data.get("registrySnapshotPath") == "factory/registry/evidence/block-registry.json", "registry path drift")
    _require(data.get("registrySnapshotSha256") == sha256(REGISTRY), "registry byte pin mismatch")
    blocks = registry.get("blocks")
    _require(isinstance(blocks, list), "registry blocks must be array")
    _integer(data.get("registryBlocksPresent"), len(blocks), "registryBlocksPresent")
    _integer(prior.get("registryBlocksPresent"), len(blocks), "v7 registryBlocksPresent")

    prior_rows = prior.get("rows")
    rows = data.get("rows")
    _require(isinstance(prior_rows, list) and isinstance(rows, list), "rows must be arrays")
    _require(len(prior_rows) == 8 and len(rows) == 8, "overlay must preserve exactly eight held rows")
    prior_by_key = {row.get("rowKey"): row for row in prior_rows}
    _require(len(prior_by_key) == 8 and set(prior_by_key) == EXPECTED_ROW_KEYS, "v7 row key set drift")
    row_keys = [row.get("rowKey") for row in rows]
    _require(len(set(row_keys)) == 8 and set(row_keys) == EXPECTED_ROW_KEYS, "v8 row key set drift")

    for row in rows:
        key = row["rowKey"]
        expected = prior_by_key[key]
        for field in ("demand", "disposition", "priorDisposition", "requiredEvidence"):
            _require(row.get(field) == expected.get(field), f"{key} {field} differs from pinned v7")
        _require(row.get("disposition") == row.get("priorDisposition"), f"{key} disposition changed")
        for field in ("fullDemandResolved", "registryPromotion", "apiIdentityProven"):
            _require(row.get(field) is False, f"{key} {field} must remain false")
        evidence = row.get("requiredEvidence")
        _require(isinstance(evidence, list) and all(isinstance(item, str) and item for item in evidence), f"{key} evidence requirements malformed")

    return {
        "status": "PASS",
        "denominator": 107,
        "unresolvedHeld": 5,
        "ambiguousHeld": 3,
        "rows": 8,
        "newFullDemandResolutions": 0,
        "registryPromotion": 0,
    }


if __name__ == "__main__":
    print(json.dumps(verify(), indent=2, sort_keys=True))
