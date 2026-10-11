from __future__ import annotations

import copy
import sys
import unittest
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import mapping  # noqa: E402


class ExtendedDemandMappingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.inputs = mapping.load_pinned_inputs()
        cls.snapshots = mapping.load_pinned_source_snapshots()
        cls.candidate = mapping.build_mapping(*(cls.inputs[key] for key in cls.inputs), cls.snapshots)
        cls.by_demand = {row["demand"]: row for row in cls.candidate["rows"]}

    def test_all_rows_retained_without_registry_promotion(self):
        self.assertEqual(len(self.candidate["rows"]), 107)
        self.assertEqual(self.candidate["denominator"]["registryMappedRows"], 0)
        self.assertTrue(all(row["registryBlockId"] is None for row in self.candidate["rows"]))
        self.assertEqual(Counter(r["disposition"] for r in self.candidate["rows"]), {
            "ambiguous-catalogue-candidates": 3,
            "exact-catalogue-reference-only": 2,
            "non-swiftui-source-inventory": 46,
            "service-or-platform": 27,
            "unmapped": 29,
        })

    def test_exact_sdk_references_are_separate_from_curated_registry(self):
        row = self.by_demand["List/ForEach/onMove"]
        self.assertEqual({x["path"] for x in row["catalogueIdentityReferences"]}, {
            "SwiftUI.List", "SwiftUI.ForEach", "SwiftUI.DynamicViewContent.onMove(perform:)"
        })
        self.assertTrue(all(x["registryBlockIds"] == [] for x in row["catalogueIdentityReferences"]))
        row = self.by_demand["TextField/FocusState"]
        self.assertEqual({x["path"] for x in row["catalogueIdentityReferences"]}, {"SwiftUI.TextField", "SwiftUI.FocusState"})
        self.assertTrue(all(x["registryBlockIds"] == [] for x in row["catalogueIdentityReferences"]))

    def test_overloaded_or_broad_names_remain_ambiguous(self):
        binding = self.by_demand["Binding(get:set:)"]
        self.assertEqual(binding["disposition"], "ambiguous-catalogue-candidates")
        self.assertEqual(len(binding["ambiguousCatalogueCandidates"]), 2)
        self.assertEqual(binding["registryBlockId"], None)
        self.assertEqual(self.by_demand["Button actions"]["disposition"], "ambiguous-catalogue-candidates")
        self.assertEqual(self.by_demand["radio/checkbox controls"]["disposition"], "ambiguous-catalogue-candidates")

    def test_historical_and_live_inventory_receipts_are_distinguished(self):
        self.assertEqual(Counter(r["inventoryEvidenceFreshness"] for r in self.candidate["rows"]), {"current": 34, "stale": 73})
        self.assertEqual(Counter(v["observed"]["status"] for v in self.candidate["inventoryEvidence"].values()), {"current": 28, "stale": 28})
        stale = [r for r in self.candidate["rows"] if r["inventoryEvidenceFreshness"] == "stale"]
        self.assertTrue(all(r["inventoryEvidenceIds"] for r in stale))
        self.assertTrue(all(self.candidate["inventoryEvidence"][eid]["observed"]["status"] in {"stale", "missing"}
                            for row in stale for eid in row["inventoryEvidenceIds"]
                            if self.candidate["inventoryEvidence"][eid]["observed"]["status"] != "current"))

    def test_exact_input_bytes_are_required_and_pinned(self):
        with self.assertRaisesRegex(mapping.MappingError, "exact raw bytes"):
            bad_inputs = dict(self.inputs)
            bad_inputs["demand"] = {}
            mapping.build_mapping(*(bad_inputs[k] for k in bad_inputs), self.snapshots)
        altered = dict(self.inputs)
        altered["demand"] = altered["demand"] + b" "
        with self.assertRaisesRegex(mapping.MappingError, "pinned input changed: demand"):
            mapping.build_mapping(*(altered[k] for k in altered), self.snapshots)
        altered = dict(self.inputs)
        altered["catalogue"] = altered["catalogue"][:-1] + b" "
        with self.assertRaisesRegex(mapping.MappingError, "pinned input changed: catalogue"):
            mapping.build_mapping(*(altered[k] for k in altered), self.snapshots)

    def test_source_snapshot_corruption_or_coverage_gap_rejects(self):
        changed = dict(self.snapshots)
        first = next(iter(changed))
        changed[first] = changed[first] + b"x"
        with self.assertRaisesRegex(mapping.MappingError, "source snapshot bytes do not match manifest"):
            mapping.build_mapping(*(self.inputs[k] for k in self.inputs), changed)
        missing = dict(self.snapshots)
        missing.pop(first)
        with self.assertRaisesRegex(mapping.MappingError, "source snapshot bytes are missing"):
            mapping.build_mapping(*(self.inputs[k] for k in self.inputs), missing)

    def test_candidate_validator_rejects_row_drift_or_promotion(self):
        mapping.validate_candidate(self.candidate, self.inputs, self.snapshots)
        bad = copy.deepcopy(self.candidate)
        bad["rows"].pop()
        with self.assertRaisesRegex(mapping.MappingError, "independent exact-input reconstruction"):
            mapping.validate_candidate(bad, self.inputs, self.snapshots)
        bad = copy.deepcopy(self.candidate)
        bad["rows"][0]["registryBlockId"] = "swiftui.toggle"
        with self.assertRaisesRegex(mapping.MappingError, "independent exact-input reconstruction"):
            mapping.validate_candidate(bad, self.inputs, self.snapshots)
        bad = copy.deepcopy(self.candidate)
        target = next(row for row in bad["rows"] if row["demand"] == "List/ForEach/onMove")
        target["catalogueIdentityReferences"][0]["usr"] = "s:forged"
        with self.assertRaisesRegex(mapping.MappingError, "independent exact-input reconstruction"):
            mapping.validate_candidate(bad, self.inputs, self.snapshots)


if __name__ == "__main__":
    unittest.main(verbosity=2)
