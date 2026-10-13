from __future__ import annotations

import json
import unittest
from pathlib import Path

import audit


class SourceReceiptAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        shell = audit.SHELL
        self.inventory = json.loads((shell / "inventory.json").read_text(encoding="utf-8"))
        self.demand = json.loads((shell / "demand.json").read_text(encoding="utf-8"))
        self.result = audit.build(self.inventory, self.demand)

    def test_exact_107_associations_preserve_holds(self) -> None:
        self.assertEqual(self.result["counts"]["journeys"], 26)
        self.assertEqual(self.result["counts"]["demands"], 107)
        self.assertEqual(self.result["counts"]["registryMappings"], 0)
        self.assertEqual(self.result["holds"]["registryPromotion"], 0)
        self.assertEqual(self.result["holds"]["sourceProofRows"], 0)
        self.assertEqual(
            {row["status"] for row in self.result["rows"]},
            {"unmapped", "source_inventory_only"},
        )

    def test_each_row_has_known_journey_and_receipt_refs(self) -> None:
        journey_ids = {journey["id"] for journey in self.inventory["journeys"]}
        evidence_ids = {entry["id"] for entry in self.inventory["evidence"]}
        self.assertEqual(len({row["demand"] for row in self.result["rows"]}), 107)
        for row in self.result["rows"]:
            self.assertIn(row["journeyId"], journey_ids)
            self.assertTrue(set(row["evidenceIds"]).issubset(evidence_ids))
            self.assertIsNone(row["registryBlockId"])
            self.assertFalse(row["sourceProof"])

    def test_current_receipt_state_is_explicit(self) -> None:
        allowed = {"unchanged_exact", "changed_hash_anchor_present", "changed_hash_anchor_missing", "missing"}
        self.assertTrue(set(self.result["counts"]["receiptStateCounts"]).issubset(allowed))
        self.assertEqual(sum(self.result["counts"]["receiptStateCounts"].values()), 56)


if __name__ == "__main__":
    unittest.main()
