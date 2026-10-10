from __future__ import annotations

import sys
import unittest
import json
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.schema_validate import ValidationSetupError, load_registry, validate_artifact
from tools.canonical_json import CanonicalJSONError, loads


ROOT = Path(__file__).resolve().parents[1]
EXAMPLES = ROOT / "spec" / "examples" / "rectangle-v0.1"


def catalogue() -> dict:
    return {
        "kind": "catalogue",
        "version": "0.1",
        "id": "catalogue/test",
        "provenance": {
            "sourceHash": "sha256:" + "0" * 64,
            "createdAt": "2026-10-10T00:00:00Z",
            "producer": "factory-test",
        },
        "symbolGraph": {
            "sdk": "test-sdk",
            "compiler": "test-compiler",
            "target": "test-target",
            "flagsHash": "sha256:" + "1" * 64,
            "interfaceAuditHash": "sha256:" + "2" * 64,
        },
        "symbols": [{"usr": "u:test", "precise": "p:test", "path": "Test.symbol", "status": "inventory"}],
    }


def example(name: str) -> dict:
    return json.loads((EXAMPLES / name).read_text(encoding="utf-8"))


class SchemaValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.registry, cls.documents = load_registry(ROOT / "spec" / "schema")

    def test_selects_local_schema_identifier_from_kind(self) -> None:
        self.assertEqual(validate_artifact(catalogue(), self.registry, self.documents), [])

    def test_reports_schema_fault(self) -> None:
        artifact = catalogue()
        artifact["symbols"] = []
        self.assertTrue(validate_artifact(artifact, self.registry, self.documents))

    def test_enforces_rfc3339_timestamp_format(self) -> None:
        artifact = catalogue()
        artifact["provenance"]["createdAt"] = "not-a-timestamp"
        self.assertTrue(validate_artifact(artifact, self.registry, self.documents))

    def test_refuses_nonlocal_schema_identifier(self) -> None:
        artifact = catalogue()
        artifact["$schema"] = "https://example.invalid/fetch-me.json"
        with self.assertRaises(ValidationSetupError):
            validate_artifact(artifact, self.registry, self.documents)

    def test_common_schema_cannot_bypass_artifact_root_rules(self) -> None:
        artifact = {
            "$schema": "https://swiftright.dev/factory/spec/v0.1/common.schema.json",
            "kind": "verdict",
            "version": "0.1",
        }
        with self.assertRaises(ValidationSetupError):
            validate_artifact(artifact, self.registry, self.documents)

    def test_blocked_block_requires_a_detail_and_accepts_evidence(self) -> None:
        artifact = example("example-block-registry.json")
        block = artifact["blocks"][0]
        block["progress"] = "blocked"
        block["blocked"] = {
            "reason": "independent witness unavailable",
            "openedAt": "2026-10-10T00:00:00Z",
            "owner": "factory-test",
            "evidence": [{"id": "evidence/test", "hash": "sha256:" + "3" * 64}],
        }
        self.assertEqual(validate_artifact(artifact, self.registry, self.documents), [])
        del block["blocked"]
        self.assertTrue(validate_artifact(artifact, self.registry, self.documents))

    def test_tagged_values_are_valid_in_nested_case_recipe_and_capture_values(self) -> None:
        tagged = {"decimal": {"$decimal": "1.25"}, "special": {"$number": "+Infinity"}}
        case = example("example-case.json")
        case["inputs"]["measurements"] = tagged
        self.assertEqual(validate_artifact(case, self.registry, self.documents), [])
        recipe = example("example-recipe.json")
        recipe["assertions"][0]["expected"] = {"nested": tagged}
        self.assertEqual(validate_artifact(recipe, self.registry, self.documents), [])
        capture = example("capture-macos-candidate.json")
        capture["meta"]["conditions"]["measurements"] = tagged
        self.assertEqual(validate_artifact(capture, self.registry, self.documents), [])

    def test_invalid_tags_and_bare_float_are_rejected(self) -> None:
        case = example("example-case.json")
        case["inputs"]["ambiguous"] = {"$decimal": "1", "extra": 2}
        self.assertTrue(validate_artifact(case, self.registry, self.documents))
        with self.assertRaises(CanonicalJSONError):
            loads('{"kind":"case","inputs":{"width":1.5}}')

    def test_blocked_verdict_allows_incomplete_disagreeing_repeats(self) -> None:
        verdict = example("example-verdict.json")
        self.assertEqual(verdict["status"], "blocked")
        self.assertLess(verdict["repeatability"]["mac"]["runs"], 20)
        self.assertFalse(verdict["repeatability"]["mac"]["semanticAgreement"])
        self.assertEqual(validate_artifact(verdict, self.registry, self.documents), [])


if __name__ == "__main__":
    unittest.main()
