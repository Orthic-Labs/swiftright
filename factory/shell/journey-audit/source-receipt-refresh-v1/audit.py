"""Source-only audit of F12 receipts & 107 demand-to-journey associations.

Historical inventory/demand files stay immutable. This packet reports current
receipt state & joins each demand to its owning journey's source receipts.
It never promotes registry IDs or runtime evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
SHELL = HERE.parents[1]


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def receipt_state(receipt: dict[str, Any]) -> dict[str, Any]:
    path = Path(receipt["path"])
    result: dict[str, Any] = {
        "id": receipt["id"],
        "path": str(path),
        "historicalSha256": receipt["sha256"],
        "historicalLine": receipt["line"],
        "historicalText": receipt["text"],
    }
    try:
        raw = path.read_bytes()
    except OSError as exc:
        result.update({"state": "missing", "error": str(exc)})
        return result
    current_hash = sha256_bytes(raw)
    lines = raw.decode("utf-8", errors="replace").splitlines()
    exact_hits = [index + 1 for index, line in enumerate(lines) if line.strip() == receipt["text"]]
    historical_line_matches = (
        1 <= receipt["line"] <= len(lines)
        and lines[receipt["line"] - 1].strip() == receipt["text"]
    )
    if current_hash == receipt["sha256"] and historical_line_matches:
        state = "unchanged_exact"
    elif exact_hits:
        state = "changed_hash_anchor_present"
    else:
        state = "changed_hash_anchor_missing"
    result.update(
        {
            "currentSha256": current_hash,
            "currentBytes": len(raw),
            "currentExactLineHits": exact_hits,
            "historicalLineMatches": historical_line_matches,
            "state": state,
        }
    )
    return result


def build(inventory: dict[str, Any], demand: dict[str, Any]) -> dict[str, Any]:
    journeys = inventory["journeys"]
    evidence_by_id = {entry["id"]: entry for entry in inventory["evidence"]}
    demand_by_text = {row["demand"]: row for row in demand["unmapped_demands"]}
    rows: list[dict[str, Any]] = []
    for journey in journeys:
        refs = [receipt_state(evidence_by_id[evidence_id]) for evidence_id in journey["evidence_ids"]]
        receipt_states = {ref["state"] for ref in refs}
        association_state = "source-receipt-current" if receipt_states == {"unchanged_exact"} else "source-receipt-drift"
        for extended in journey["extended_demands"]:
            demand_row = demand_by_text[extended]
            rows.append(
                {
                    "demand": extended,
                    "journeyId": journey["id"],
                    "status": demand_row["status"],
                    "registryBlockId": demand_row["registry_block_id"],
                    "associationKind": "journey-evidence-association-only",
                    "sourceProof": False,
                    "associationState": association_state,
                    "evidenceIds": list(journey["evidence_ids"]),
                    "evidenceRefs": [
                        {
                            "id": ref["id"],
                            "path": ref["path"],
                            "historicalSha256": ref["historicalSha256"],
                            "currentSha256": ref.get("currentSha256"),
                            "state": ref["state"],
                        }
                        for ref in refs
                    ],
                }
            )
    rows.sort(key=lambda row: row["demand"])
    receipt_audit = [receipt_state(entry) for entry in inventory["evidence"]]
    state_counts: dict[str, int] = {}
    for entry in receipt_audit:
        state_counts[entry["state"]] = state_counts.get(entry["state"], 0) + 1
    return {
        "kind": "f12-source-receipt-refresh-audit",
        "version": 1,
        "status": "source-only-no-promotion",
        "inputs": {
            "inventoryPath": "factory/shell/inventory.json",
            "inventorySha256": sha256_bytes((SHELL / "inventory.json").read_bytes()),
            "demandPath": "factory/shell/demand.json",
            "demandSha256": sha256_bytes((SHELL / "demand.json").read_bytes()),
        },
        "counts": {
            "journeys": len(journeys),
            "demands": len(rows),
            "historicalEvidenceReceipts": len(receipt_audit),
            "receiptStateCounts": state_counts,
            "registryMappings": sum(row["registryBlockId"] is not None for row in rows),
        },
        "holds": {
            "unresolvedDemands": sum(row["status"] == "unmapped" for row in rows),
            "sourceInventoryOnlyDemands": sum(row["status"] == "source_inventory_only" for row in rows),
            "registryPromotion": 0,
            "sourceProofRows": 0,
        },
        "receiptAudit": receipt_audit,
        "rows": rows,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=HERE / "evidence/current-source-receipt-audit.json")
    args = parser.parse_args()
    inventory = json.loads((SHELL / "inventory.json").read_text(encoding="utf-8"))
    demand = json.loads((SHELL / "demand.json").read_text(encoding="utf-8"))
    result = build(inventory, demand)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": "PASS", "journeys": result["counts"]["journeys"], "demands": result["counts"]["demands"], "receiptStateCounts": result["counts"]["receiptStateCounts"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
