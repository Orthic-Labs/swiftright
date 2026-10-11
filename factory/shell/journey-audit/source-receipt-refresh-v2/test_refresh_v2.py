from __future__ import annotations

import copy
import unittest

import refresh


class RefreshV2Tests(unittest.TestCase):
    def setUp(self) -> None:
        candidate, demand, history = refresh.make_candidate()
        self.candidate = candidate
        self.demand = demand
        self.history = history

    def test_current_candidate_accepts_actual_hashes_and_anchors(self) -> None:
        refresh.validate_candidate(self.candidate, self.demand)
        self.assertEqual(len(self.candidate["evidence"]), 56)
        self.assertEqual(sum(item["resolution"] == "semantic-anchor-updated" for item in self.history), 1)
        settings = next(item for item in self.history if item["id"] == "settings-panel")
        self.assertEqual(settings["currentLine"], 173)
        self.assertEqual(settings["currentText"], 'export function SettingsPanel(props: SettingsPanelProps) {')

    def test_hash_and_anchor_faults_reject(self) -> None:
        mutated = copy.deepcopy(self.candidate)
        mutated["evidence"][0]["sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            refresh.validate_candidate(mutated, self.demand)
        mutated = copy.deepcopy(self.candidate)
        mutated["evidence"][0]["line"] += 1
        with self.assertRaises(ValueError):
            refresh.validate_candidate(mutated, self.demand)

    def test_demand_associations_preserve_107_holds_without_promotion(self) -> None:
        rows = refresh.demand_associations(self.candidate, self.demand)
        refresh.validate_associations(self.candidate, self.demand, rows)
        self.assertEqual(len(rows), 107)
        self.assertEqual(len({row["demand"] for row in rows}), 107)
        self.assertEqual(sum(row["status"] == "unmapped" for row in rows), 61)
        self.assertEqual(sum(row["status"] == "source_inventory_only" for row in rows), 46)
        self.assertTrue(all(row["registryBlockId"] is None for row in rows))
        self.assertTrue(all(row["sourceProof"] is False for row in rows))

    def test_association_faults_reject(self) -> None:
        rows = refresh.demand_associations(self.candidate, self.demand)
        with self.assertRaises(ValueError):
            refresh.validate_associations(self.candidate, self.demand, rows[:-1])
        rows[0]["status"] = "resolved"
        with self.assertRaises(ValueError):
            refresh.validate_associations(self.candidate, self.demand, rows)


if __name__ == "__main__":
    unittest.main()
