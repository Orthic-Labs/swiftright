from __future__ import annotations

import unittest
import re
from unittest.mock import patch

from factory.core.artifacts import canonical_hash
from factory.recipes.cases import (
    CaseManifestError,
    _axis_rows,
    expand_cases,
    _planned_cases,
    validate_case_manifest,
)
from factory.recipes.recipes import load_recipes
from factory.recipes.recipes import WITNESSES


class RecipeExpansionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.recipes = load_recipes()

    def test_all_drafts_validate_and_keep_review_pending(self) -> None:
        self.assertEqual(len(self.recipes), 10)
        self.assertTrue(all(r["provenance"]["review"]["decision"] == "candidate"
                            for r in self.recipes))

    def test_every_axis_drives_an_explicit_witness_placeholder(self) -> None:
        for recipe in self.recipes:
            witness = recipe["witnesses"][0]
            source = (WITNESSES / f'{witness["id"]}.swift').read_text(encoding="utf-8")
            placeholders = set(re.findall(r"\{\{([^{}]+)\}\}", source))
            axes = {axis["id"] for axis in recipe["axes"]}
            self.assertEqual(placeholders, axes, recipe["block"])

    def test_pairwise_rows_cover_each_value_and_each_value_pair(self) -> None:
        axes = [
            {"id": "color-scheme", "values": ["light", "dark"], "coverage": "pairwise"},
            {"id": "scale", "values": [1, 2, 3], "coverage": "pairwise"},
            {"id": "direction", "values": ["ltr", "rtl"], "coverage": "pairwise"},
        ]
        rows, coverage = _axis_rows(axes, seed=42)
        self.assertEqual(coverage, "pairwise")
        self.assertEqual(rows, _axis_rows(axes, seed=42)[0])
        for axis in axes:
            self.assertEqual(set(axis["values"]), {row[axis["id"]] for row in rows})
        for left in range(len(axes)):
            for right in range(left + 1, len(axes)):
                pairs = {(row[axes[left]["id"]], row[axes[right]["id"]]) for row in rows}
                wanted = {(a, b) for a in axes[left]["values"] for b in axes[right]["values"]}
                self.assertEqual(pairs, wanted)

    def test_full_product_axis_expands_every_combination(self) -> None:
        recipe = next(r for r in self.recipes if r["block"] == "swiftui.custom-layout")
        planned = _planned_cases(recipe, seed=0)
        axis_cases = [case for case in planned if case.coverage == "full-product"]
        product_size = 1
        for axis in recipe["axes"]:
            product_size *= len(axis["values"])
        self.assertEqual(len(axis_cases), product_size)

    def test_exact_manifest_rejects_missing_case(self) -> None:
        recipe = next(r for r in self.recipes if r["block"] == "swiftui.image")
        planned = _planned_cases(recipe, seed=11)
        expected_ids = [case.case_id for case in planned]
        descriptors = [{"id": case.case_id, "inputs": case.inputs, "coverage": case.coverage}
                       for case in planned]
        descriptors.sort(key=lambda row: (row["id"], canonical_hash(row["inputs"])))
        expected_hash = canonical_hash(descriptors)
        case_artifacts = [{"id": case_id, "expectedCaseSetHash": expected_hash}
                          for case_id in expected_ids]
        expansion = {
            "manifest": {
                "caseIds": expected_ids,
                "expectedCaseSetHash": expected_hash,
                "expectedCases": [{"id": case["id"], "hash": canonical_hash(case)}
                                   for case in case_artifacts],
            },
            "cases": case_artifacts,
        }
        validate_case_manifest(expansion)
        with self.assertRaisesRegex(CaseManifestError, "case set mismatch"):
            validate_case_manifest(expansion, expansion["cases"][:-1])
        modified = [dict(case) for case in case_artifacts]
        modified[0]["id"] += ".modified"
        with self.assertRaisesRegex(CaseManifestError, "case set mismatch"):
            validate_case_manifest(expansion, modified)
        altered = [dict(case) for case in case_artifacts]
        altered[0]["input"] = "changed"
        with self.assertRaisesRegex(CaseManifestError, "case content differs"):
            validate_case_manifest(expansion, altered)

    def test_case_artifacts_are_stable_when_wall_clock_advances(self) -> None:
        recipe = next(r for r in self.recipes if r["block"] == "swiftui.image")
        tuple_value = {
            "id": "test-tuple.image",
            "sdk": "test-sdk",
            "macosBuild": "test-build",
            "toolchains": {"swift": "test-swift"},
            "runtimeCommit": "abcdef0",
            "rendererHash": "sha256:" + "1" * 64,
            "hostHashes": {"macos": "sha256:" + "2" * 64},
            "factoryVersion": "0.1",
            "acceptanceConfigHash": "sha256:" + "3" * 64,
        }
        with patch("factory.core.artifacts.datetime") as clock:
            clock.now.side_effect = ["2040-01-01T00:00:00Z", "2041-01-01T00:00:00Z"]
            first = expand_cases(recipe, tuple_value, seed=19)
            second = expand_cases(recipe, tuple_value, seed=19)
        clock.now.assert_not_called()
        self.assertEqual(first, second)
        self.assertTrue(all(case["provenance"]["createdAt"] == recipe["provenance"]["createdAt"]
                            for case in first["cases"]))

    def test_explicit_snapshot_timestamp_pins_full_case_hashes(self) -> None:
        recipe = next(r for r in self.recipes if r["block"] == "swiftui.image")
        tuple_value = {
            "id": "test-tuple.image", "sdk": "test-sdk", "macosBuild": "test-build",
            "toolchains": {"swift": "test-swift"}, "runtimeCommit": "abcdef0",
            "rendererHash": "sha256:" + "1" * 64,
            "hostHashes": {"macos": "sha256:" + "2" * 64}, "factoryVersion": "0.1",
            "acceptanceConfigHash": "sha256:" + "3" * 64,
        }
        timestamp = "2042-01-02T03:04:05Z"
        first = expand_cases(recipe, tuple_value, seed=19, snapshot_created_at=timestamp)
        second = expand_cases(recipe, tuple_value, seed=19, snapshot_created_at=timestamp)
        self.assertEqual(first, second)
        self.assertTrue(all(case["provenance"]["createdAt"] == timestamp
                            for case in first["cases"]))


if __name__ == "__main__":
    unittest.main()
