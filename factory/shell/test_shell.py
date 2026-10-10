from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from factory.shell.__main__ import check_evidence_entry, validate_map


HERE = Path(__file__).resolve().parent


class ShellInventoryTests(unittest.TestCase):
    def test_missing_and_changed_source_receipts_fail(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "source.ts"
            path.write_text("export function route() {}\n", encoding="utf-8")
            raw = path.read_bytes()
            receipt = {"id": "route", "path": str(path), "sha256": hashlib.sha256(raw).hexdigest(), "line": 1, "text": "export function route() {}"}
            self.assertEqual(check_evidence_entry(receipt), [])
            path.unlink()
            self.assertTrue(any("missing" in e for e in check_evidence_entry(receipt)))
            path.write_text("export function changed() {}\n", encoding="utf-8")
            failures = check_evidence_entry(receipt)
            self.assertTrue(any("SHA-256 changed" in e for e in failures))
            self.assertTrue(any("line 1 changed" in e for e in failures))

    def test_inventory_and_demand_map_are_consistent(self) -> None:
        inventory = json.loads((HERE / "inventory.json").read_text(encoding="utf-8"))
        demand = json.loads((HERE / "demand.json").read_text(encoding="utf-8"))
        self.assertEqual(validate_map(inventory, demand), [])
        demand["journey_demands"].pop()
        self.assertTrue(any("journey ids do not match" in e for e in validate_map(inventory, demand)))

    def test_unknown_pilot_block_and_stale_service_mapping_fail(self) -> None:
        inventory = json.loads((HERE / "inventory.json").read_text(encoding="utf-8"))
        demand = json.loads((HERE / "demand.json").read_text(encoding="utf-8"))
        inventory["journeys"][0]["pilot_blocks"].append("unregistered")
        demand["journey_demands"][0]["service_dependencies"].append("stale adapter")
        failures = validate_map(inventory, demand)
        self.assertTrue(any("unregistered pilot block id" in e for e in failures))
        self.assertTrue(any("service map differs" in e for e in failures))


if __name__ == "__main__":
    unittest.main()
