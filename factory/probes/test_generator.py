"""Deterministic factory probe source emission checks."""

from __future__ import annotations

import json
import hashlib
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

from factory.probes import ProbeError, generate_probe
from factory.tools import canonical_json


class ProbeGeneratorTests(unittest.TestCase):
    def setUp(self) -> None:
        example = ROOT / "spec" / "examples" / "rectangle-v0.1"
        self.recipe = canonical_json.load(ROOT / "recipes" / "data" / "swiftui.image.json")
        self.case = canonical_json.load(example / "example-case.json")
        recipe_hash = canonical_json.sha256(self.recipe)
        self.case.update(
            {
                "id": "swiftui.image.generator-test",
                "recipe": {"id": self.recipe["id"], "hash": recipe_hash},
                "block": self.recipe["block"],
                "inputs": {axis["id"]: axis["values"][0] for axis in self.recipe["axes"]},
            }
        )
        self.case["provenance"]["inputs"] = [{"id": self.recipe["id"], "hash": recipe_hash}]

    def test_source_and_manifest_are_deterministic(self) -> None:
        with tempfile.TemporaryDirectory() as first_dir, tempfile.TemporaryDirectory() as second_dir:
            first = generate_probe(self.recipe, self.case, first_dir)
            second = generate_probe(self.recipe, self.case, second_dir)
            self.assertEqual(first, second)
            source_name = first["sourceFile"]
            source_a = (Path(first_dir) / source_name).read_bytes()
            source_b = (Path(second_dir) / source_name).read_bytes()
            self.assertEqual(source_a, source_b)
            self.assertEqual(first["sourceHash"], "sha256:" + hashlib.sha256(source_a).hexdigest())
            self.assertIn(b"#if os(Windows)\nimport SwiftRightRuntime", source_a)
            self.assertIn(b"#else\nimport SwiftUI\n#endif", source_a)
            self.assertTrue(first["channels"]["transparency"]["viewIsolatedFromInstrumentation"])

    def test_rejects_undeclared_case_inputs(self) -> None:
        unsupported = json.loads(json.dumps(self.case))
        unsupported["inputs"] = {"unknownAxis": 1}
        with tempfile.TemporaryDirectory() as output:
            with self.assertRaisesRegex(ProbeError, "unsupported case inputs"):
                generate_probe(self.recipe, unsupported, output)

    def test_case_axis_values_specialize_generated_source(self) -> None:
        alternate = json.loads(json.dumps(self.case))
        alternate["id"] = "swiftui.image.generator-test-alternate"
        alternate["inputs"]["scale"] = 3
        alternate["inputs"]["color-scheme"] = "dark"
        with tempfile.TemporaryDirectory() as first_dir, tempfile.TemporaryDirectory() as second_dir:
            first = generate_probe(self.recipe, self.case, first_dir)
            second = generate_probe(self.recipe, alternate, second_dir)
            source_a = (Path(first_dir) / first["sourceFile"]).read_text(encoding="utf-8")
            source_b = (Path(second_dir) / second["sourceFile"]).read_text(encoding="utf-8")
            self.assertNotEqual(source_a, source_b)
            self.assertIn(".environment(\\.displayScale, 1)", source_a)
            self.assertIn(".environment(\\.displayScale, 3)", source_b)
            self.assertEqual(second["environmentInputs"]["colorScheme"], "dark")

    def test_foundation_is_imported_only_for_foundation_geometry_types(self) -> None:
        example = ROOT / "spec" / "examples" / "rectangle-v0.1" / "example-case.json"
        with tempfile.TemporaryDirectory() as output:
            for block in ("swiftui.custom-layout", "swiftui.preference-key", "swiftui.disabled"):
                recipe = canonical_json.load(ROOT / "recipes" / "data" / f"{block}.json")
                case = canonical_json.load(example)
                recipe_hash = canonical_json.sha256(recipe)
                case.update(
                    {
                        "id": f"swiftui.probe.foundation-test.{block.split('.')[-1]}",
                        "recipe": {"id": recipe["id"], "hash": recipe_hash},
                        "block": block,
                        "inputs": {axis["id"]: axis["values"][0] for axis in recipe["axes"]},
                    }
                )
                case["provenance"]["inputs"] = [{"id": recipe["id"], "hash": recipe_hash}]
                result = generate_probe(recipe, case, output)
                source = (Path(output) / result["sourceFile"]).read_text(encoding="utf-8")
                self.assertEqual("import Foundation" in source, block in {"swiftui.custom-layout", "swiftui.preference-key"})

    def test_explicit_factory_witness_root_binds_font_pilot_source(self) -> None:
        pilot = ROOT / "resources" / "fonts" / "pilot"
        recipe = canonical_json.load(pilot / "recipe.json")
        case_path = next(
            path for path in (pilot / "cases").glob("*.json")
            if "instrumentation-transparency" not in path.name
        )
        case = canonical_json.load(case_path)
        with tempfile.TemporaryDirectory() as output:
            result = generate_probe(recipe, case, output, witness_root=pilot)
            source = (Path(output) / result["sourceFile"]).read_text(encoding="utf-8")
            self.assertIn(".font(.custom(\"Tinos-Regular\", size: 18))", source)
            self.assertEqual(
                result["witness"]["resourcePath"],
                "factory/resources/fonts/pilot/swiftui.text.bundled-font.tinos-pilot.witness.swift",
            )
        with tempfile.TemporaryDirectory() as external_root, tempfile.TemporaryDirectory() as output:
            with self.assertRaisesRegex(ProbeError, "inside the factory subtree"):
                generate_probe(recipe, case, output, witness_root=external_root)


if __name__ == "__main__":
    unittest.main()
