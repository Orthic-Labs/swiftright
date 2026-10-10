from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
from typing import Any


HERE = Path(__file__).resolve().parent


def check_evidence_entry(entry: dict[str, Any]) -> list[str]:
    """Check one source receipt against current bytes and recorded line."""
    path = Path(entry["path"])
    problems: list[str] = []
    try:
        raw = path.read_bytes()
    except OSError as exc:
        return [f"{entry['id']}: source missing/unreadable: {path} ({exc.strerror})"]
    digest = hashlib.sha256(raw).hexdigest()
    if digest != entry["sha256"]:
        problems.append(f"{entry['id']}: SHA-256 changed: {path}")
    lines = raw.decode("utf-8", errors="replace").splitlines()
    line = entry["line"]
    if line < 1 or line > len(lines) or lines[line - 1].strip() != entry["text"]:
        problems.append(f"{entry['id']}: recorded line {line} changed or moved: {path}")
    return problems


def validate_map(inventory: dict[str, Any], demand: dict[str, Any]) -> list[str]:
    problems: list[str] = []
    journeys = inventory.get("journeys", [])
    ids = [j.get("id") for j in journeys]
    if len(ids) != len(set(ids)):
        problems.append("inventory: duplicate journey id")
    evidence_ids = {e.get("id") for e in inventory.get("evidence", [])}
    for journey in journeys:
        if not journey.get("evidence_ids"):
            problems.append(f"{journey.get('id')}: no source evidence")
        for ref in journey.get("evidence_ids", []):
            if ref not in evidence_ids:
                problems.append(f"{journey.get('id')}: unknown evidence id {ref}")
    pilot = set(demand.get("pilot_blocks", {}).get("shared_pilot_block_ids", []))
    demand_by_id = {d.get("journey_id"): d for d in demand.get("journey_demands", [])}
    if set(ids) != set(demand_by_id):
        problems.append("demand: journey ids do not match inventory")
    for journey in journeys:
        for block in journey.get("pilot_blocks", []):
            if block not in pilot:
                problems.append(f"{journey['id']}: unregistered pilot block id {block}")
        mapped = demand_by_id.get(journey["id"], {})
        if mapped.get("pilot_blocks") != journey.get("pilot_blocks"):
            problems.append(f"{journey['id']}: pilot block map differs from inventory")
        if mapped.get("service_dependencies") != journey.get("service_dependencies"):
            problems.append(f"{journey['id']}: service map differs from inventory")
    unmapped = {d.get("demand") for d in demand.get("unmapped_demands", []) if d.get("registry_block_id") is None}
    expected = {x for j in journeys for x in j.get("extended_demands", [])}
    if unmapped != expected:
        problems.append("demand: unmapped demand list differs from journey inventory")
    return problems


def scan(inventory_path: Path = HERE / "inventory.json", demand_path: Path = HERE / "demand.json") -> list[str]:
    try:
        inventory = json.loads(inventory_path.read_text(encoding="utf-8"))
        demand = json.loads(demand_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"cannot load F12 artifacts: {exc}"]
    problems = validate_map(inventory, demand)
    for entry in inventory.get("evidence", []):
        problems.extend(check_evidence_entry(entry))
    if not problems:
        print(f"F12 evidence OK: {len(inventory['evidence'])} source receipts, {len(inventory['journeys'])} journeys, {len(demand['unmapped_demands'])} unmapped demands")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description="Rescan F12 source receipts and demand-map consistency.")
    parser.add_argument("--inventory", type=Path, default=HERE / "inventory.json")
    parser.add_argument("--demand", type=Path, default=HERE / "demand.json")
    args = parser.parse_args()
    problems = scan(args.inventory, args.demand)
    if problems:
        print("F12 evidence check failed:", file=sys.stderr)
        for problem in problems:
            print(f"- {problem}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
