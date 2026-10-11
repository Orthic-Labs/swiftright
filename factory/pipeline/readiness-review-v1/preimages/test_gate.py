"""Adversarial gate checks; these are synthetic unit evidence only."""

from __future__ import annotations

import unittest
import json
from pathlib import Path
from jsonschema import Draft202012Validator
from referencing import Resource
from referencing.jsonschema import DRAFT202012

from factory.gate.core import _case_set_hash, baseline_case_refs, evaluate_gate, expand_gate_seeded_cases
from factory.recipes.cases import expand_cases
from factory.recipes.recipes import load_recipes
from factory.tools.canonical_json import sha256
from factory.tools.schema_validate import load_registry, validate_artifact


def fixture():
    tuple_value = {
        "id": "test.tuple", "sdk": "test", "macosBuild": "test",
        "toolchains": {"swift": "test"}, "runtimeCommit": "abcdef0",
        "rendererHash": "sha256:" + "1" * 64,
        "hostHashes": {"macos": "sha256:" + "2" * 64, "windows": "sha256:" + "3" * 64},
        "factoryVersion": "0.1", "acceptanceConfigHash": "sha256:" + "4" * 64,
    }
    recipe = {
        "kind": "recipe", "version": "0.1", "id": "test.recipe", "block": "test.block",
        "axes": [{"id": "test.width", "values": [1, 2]}],
    }
    case = {
        "kind": "case", "version": "0.1", "id": "test.case.a",
        "provenance": {"sourceHash": "sha256:" + "5" * 64, "createdAt": "2026-10-10T00:00:00Z", "producer": "test"},
        "recipe": {"id": recipe["id"], "hash": sha256(recipe)}, "block": recipe["block"],
        "inputs": {"test.width": 1}, "expectedCaseSetHash": "", "coverage": "declared", "tuple": tuple_value,
    }
    case["expectedCaseSetHash"] = _case_set_hash([case])
    return recipe, case, tuple_value


def capture(case, tuple_value, platform, run, *, capture_id=None):
    return {
        "kind": "capture", "version": "0.1", "id": capture_id or f"test.{platform}.{run}",
        "case": {"id": case["id"], "hash": sha256(case)}, "platform": platform,
        "tuple": tuple_value, "meta": {"run": run, "conditions": {"independentRun": True, "resetVerified": True}},
        "layout": [], "ax": [], "events": [], "anim": [], "images": [], "text": [],
    }


class GateAdversarialTests(unittest.TestCase):
    def evaluate(self, **overrides):
        recipe, case, tuple_value = fixture()
        args = {
            "recipe": recipe, "cases": [case], "expected_cases": [case], "captures": [],
            "tuple_value": tuple_value, "seed": 47,
            "random_case_factory": lambda seed: expand_gate_seeded_cases(recipe, tuple_value, seed),
        }
        args.update(overrides)
        return evaluate_gate(**args)["report"]["issues"]

    def test_missing_recipe_case_is_rejected(self):
        recipe, _, tuple_value = fixture()
        issues = self.evaluate(cases=[], expected_cases=[fixture()[1]])
        self.assertTrue(any("incomplete" in issue for issue in issues))

    def test_altered_capture_case_hash_is_rejected(self):
        recipe, case, tuple_value = fixture()
        c = capture(case, tuple_value, "macos", 1)
        c["case"]["hash"] = "sha256:" + "0" * 64
        self.assertTrue(any("case hash" in issue for issue in self.evaluate(captures=[c])))

    def test_wrong_seed_is_rejected(self):
        recipe, _, tuple_value = fixture()
        def wrong(seed):
            result = expand_gate_seeded_cases(recipe, tuple_value, seed)
            result[0]["seed"] += 1
            return result
        self.assertTrue(any("seed/coverage mismatch" in issue for issue in self.evaluate(random_case_factory=wrong)))

    def test_tuple_mismatch_is_rejected(self):
        recipe, case, tuple_value = fixture()
        wrong = dict(tuple_value, sdk="wrong")
        self.assertTrue(any("tuple mismatch" in issue for issue in self.evaluate(captures=[capture(case, wrong, "macos", 1)])))

    def test_duplicate_capture_ids_are_rejected(self):
        recipe, case, tuple_value = fixture()
        c = capture(case, tuple_value, "macos", 1, capture_id="duplicate")
        self.assertTrue(any("capture IDs" in issue for issue in self.evaluate(captures=[c, dict(c)])))

    def test_missing_fault_control_is_rejected(self):
        rule = {"id": "normalize.role", "faultControlHash": "sha256:" + "6" * 64}
        self.assertTrue(any("fault control missing" in issue for issue in self.evaluate(normalizer_rules=[rule])))

    def test_unreviewed_promotion_is_rejected(self):
        request = {"reviewer": "nobody", "at": "now", "decision": "candidate", "candidateHash": "x", "diffHash": "y", "tupleHash": "z"}
        issues = self.evaluate(promotion_request=request)
        self.assertTrue(any("not accepted" in issue for issue in issues))
        self.assertTrue(any("tuple binding" in issue for issue in issues))

    def protected_fixture(self, seed=19):
        recipe = next(item for item in load_recipes() if item["block"] == "swiftui.toggle")
        _, _, tuple_value = fixture()
        tuple_value["acceptanceConfigHash"] = "sha256:" + "0" * 64
        draft = expand_cases(recipe, tuple_value, seed=seed)["cases"]
        config = {
            "kind": "acceptance-candidate", "version": "0.1", "mode": "qualified",
            "review": "accepted", "normalizers": [],
            "baseline": {"version": "1", "recipes": [{
                "recipe": {"id": recipe["id"], "hash": sha256(recipe)},
                "seed": seed, "cases": baseline_case_refs(draft),
            }]},
        }
        tuple_value["acceptanceConfigHash"] = sha256(config)
        cases = expand_cases(recipe, tuple_value, seed=seed)["cases"]
        return recipe, cases, tuple_value, config

    def test_truncated_baseline_with_recomputed_case_hash_is_rejected(self):
        recipe, cases, tuple_value, config = self.protected_fixture()
        shortened = cases[:-1]
        shortened_hash = _case_set_hash(shortened)
        for case in shortened:
            case["expectedCaseSetHash"] = shortened_hash
        result = evaluate_gate(
            recipe=recipe, cases=shortened, expected_cases=shortened, captures=[],
            tuple_value=tuple_value, acceptance_config=config, normalizer_rules=[], seed=47,
        )
        self.assertIn(
            "supplied baseline cases differ from complete trusted recipe expansion",
            result["report"]["issues"],
        )

    def test_external_baseline_seed_cannot_replace_protected_seed(self):
        recipe, _, tuple_value, config = self.protected_fixture(seed=19)
        foreign_cases = expand_cases(recipe, tuple_value, seed=23)["cases"]
        result = evaluate_gate(
            recipe=recipe, cases=foreign_cases, expected_cases=foreign_cases, captures=[],
            tuple_value=tuple_value, acceptance_config=config, normalizer_rules=[], seed=47,
        )
        self.assertIn(
            "supplied baseline cases differ from complete trusted recipe expansion",
            result["report"]["issues"],
        )

    def test_valid_pinned_projection_accepts_provenance_timestamp_drift(self):
        recipe, cases, tuple_value, config = self.protected_fixture()
        # Existing snapshot provenance may differ; semantic case content remains exact.
        drifted = json.loads(json.dumps(cases))
        for case in drifted:
            case["provenance"]["createdAt"] = "2026-10-11T00:00:00Z"
            case["expectedCaseSetHash"] = _case_set_hash(drifted)
        result = evaluate_gate(
            recipe=recipe, cases=drifted, expected_cases=drifted, captures=[],
            tuple_value=tuple_value, acceptance_config=config, normalizer_rules=[], seed=47,
        )
        self.assertFalse(any("baseline" in issue or "protected" in issue for issue in result["report"]["issues"]))

    def test_unreviewed_baseline_config_cannot_pass_review_gate(self):
        recipe, cases, tuple_value, config = self.protected_fixture()
        config["review"] = "pending-maintainer-review"
        tuple_value["acceptanceConfigHash"] = sha256(config)
        # Cases contain old tuple binding, so rebuild the pinned artifacts using updated tuple.
        cases = expand_cases(recipe, tuple_value, seed=19)["cases"]
        result = evaluate_gate(
            recipe=recipe, cases=cases, expected_cases=cases, captures=[],
            tuple_value=tuple_value, acceptance_config=config, normalizer_rules=[], seed=47,
        )
        self.assertIn("acceptance configuration lacks accepted review", result["report"]["issues"])

    def test_gate_seeded_case_is_additional_to_pinned_baseline(self):
        recipe, cases, tuple_value, config = self.protected_fixture()
        result = evaluate_gate(
            recipe=recipe, cases=cases, expected_cases=cases, captures=[],
            tuple_value=tuple_value, acceptance_config=config, normalizer_rules=[], seed=47,
        )
        report_ids = {ref["id"] for ref in result["report"]["cases"]}
        baseline_ids = {case["id"] for case in cases}
        self.assertEqual(len(baseline_ids) + 1, len(report_ids))
        self.assertTrue(baseline_ids.issubset(report_ids))
        self.assertFalse(any("baseline" in issue or "protected" in issue for issue in result["report"]["issues"]))

    def test_receipt_matches_factory_receipt_schema(self):
        recipe, case, tuple_value = fixture()
        result = evaluate_gate(
            recipe=recipe, cases=[case], expected_cases=[case], captures=[], tuple_value=tuple_value,
            seed=47, random_case_factory=lambda value: expand_gate_seeded_cases(recipe, tuple_value, value),
        )
        registry, documents = load_registry(Path(__file__).resolve().parents[1] / "spec" / "schema")
        self.assertEqual([], validate_artifact(result["receipt"], registry, documents))
        report_schema_path = Path(__file__).with_name("gate-report.schema.json")
        report_schema = json.loads(report_schema_path.read_text())
        Draft202012Validator.check_schema(report_schema)
        registry = registry.with_resource(report_schema["$id"], Resource(report_schema, DRAFT202012))
        validator = Draft202012Validator(report_schema, registry=registry)
        self.assertEqual([], [error.message for error in validator.iter_errors(result["report"])])


if __name__ == "__main__":
    unittest.main()
