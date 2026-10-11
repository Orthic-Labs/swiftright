from __future__ import annotations

from copy import deepcopy
import json
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

from factory.core.artifacts import canonical_hash
spec = importlib.util.spec_from_file_location("public_ancestor_consumer_tested", Path(__file__).with_name("consumer.py"))
consumer = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = consumer
spec.loader.exec_module(consumer)

BASE_CATALOGUE_SHA256 = consumer.BASE_CATALOGUE_SHA256
ConsumerError = consumer.ConsumerError
merge_catalogue = consumer.merge_catalogue
write_candidate_atomic = consumer.write_candidate_atomic


ROOT = Path(__file__).resolve().parents[3]
BASE = json.loads((ROOT / "factory/catalogue/evidence/catalogue.json").read_text())
STAMP = "2026-10-11T00:00:00Z"


def fixture_resolution() -> tuple[dict, set[str]]:
    base_usr = BASE["symbols"][0]["usr"]
    base_path = BASE["symbols"][0]["path"]
    added_usr = "s:11SwiftUI5ProofV4itemyyF"
    source_rows = [
        {
            "key": ["SwiftUI", "arm64e-apple-macos.swiftinterface", 2, "offset(to:allowedFields:maxFieldCount:sign:)"],
            "status": "eligible-compiler-mapped", "lineageV12": True, "usr": base_usr,
            "compilerPath": base_path, "kind": "func", "owner": None,
            "accessRule": "explicit source access", "attributedRestrictions": [],
        },
        {
            "key": ["SwiftUI", "arm64e-apple-macos.swiftinterface", 3, "item()"],
            "status": "eligible-compiler-mapped", "lineageV12": True, "usr": added_usr,
            "compilerPath": "SwiftUI.Proof.item()", "kind": "func", "owner": None,
            "accessRule": "explicit source access", "attributedRestrictions": [],
        },
    ]
    source_rows.extend({
        "key": ["SwiftUI", "arm64e-apple-macos.swiftinterface", line, f"local{line}"],
        "status": "excluded-nonpublic-source", "lineageV12": True,
    } for line in range(4, 12637))
    resolution = {
        "status": consumer.EXPECTED_PROOF_STATUS,
        "rows": source_rows,
        "byStatus": {"eligible-compiler-mapped": 2, "excluded-nonpublic-source": 12633},
        "heldReasons": {},
        "heldNominals": [],
        "heldNominalReasons": {},
        "fullSourceDeclarationStarts": 12635,
        "unreconstructedV12Starts": 0,
        "v12DeclarationStarts": 12635,
        "addedSourceDeclarationStarts": 0,
        "publicCompilerCatalogueUsrCount": 2,
        "compilerRecordCount": 2,
        "compilerRecordCategories": {"source-start-present": 2},
        "compilerInventory": [{"category": "source-start-present"}, {"category": "source-start-present"}],
        "graphPresentPublicCompilerUsrCount": 1,
        "graphAbsentPublicCompilerUsrCount": 1,
        "publicCompilerCatalogue": [
            {
                "usr": base_usr,
                "path": base_path,
                "graphPresent": True,
                "compilerEvidencePresent": True,
                "status": "inventory",
                "sourceDeclarations": [{
                    "sourceKey": source_rows[0]["key"], "compilerPath": base_path,
                    "status": "eligible-compiler-mapped", "kind": "func", "ancestor": None,
                    "accessRule": "explicit source access", "restrictions": [],
                }],
            },
            {
                "usr": added_usr,
                "path": "SwiftUI.Proof.item()",
                "graphPresent": False,
                "compilerEvidencePresent": True,
                "status": "inventory",
                "sourceDeclarations": [{
                    "sourceKey": source_rows[1]["key"], "compilerPath": "SwiftUI.Proof.item()",
                    "status": "eligible-compiler-mapped", "kind": "func", "ancestor": None,
                    "accessRule": "explicit source access", "restrictions": [],
                }],
            },
        ],
    }
    return resolution, {base_usr}


class CatalogueMergeTests(unittest.TestCase):
    def merge(self, resolution=None, graph_usrs=None, base=None):
        if resolution is None:
            resolution, defaults = fixture_resolution()
            graph_usrs = defaults if graph_usrs is None else graph_usrs
        return merge_catalogue(
            BASE if base is None else base,
            resolution,
            raw_graph_usrs=graph_usrs,
            proof_hash="sha256:" + "a" * 64,
            guard_hash="sha256:" + "b" * 64,
            link_hash=consumer.IMMUTABLE_LINK_SHA256,
            proof_input_refs=[],
            created_at=STAMP,
        )

    def test_additive_merge_preserves_base_rows_and_graph_metadata(self):
        resolution, graph_usrs = fixture_resolution()
        result = self.merge(resolution, graph_usrs)
        self.assertEqual(result["symbols"][:len(BASE["symbols"])], BASE["symbols"])
        self.assertEqual(result["symbolGraph"], BASE["symbolGraph"])
        self.assertEqual(len(result["symbols"]), len(BASE["symbols"]) + 1)
        self.assertEqual(result["symbols"][-1], {
            "usr": "s:11SwiftUI5ProofV4itemyyF",
            "precise": "s:11SwiftUI5ProofV4itemyyF",
            "path": "SwiftUI.Proof.item()",
            "status": "inventory",
        })
        output = Path(__file__).with_name(".candidate-atomic-test.json")
        try:
            digest = write_candidate_atomic(output, result)
            self.assertTrue(digest.startswith("sha256:"))
            self.assertEqual(json.loads(output.read_text()), result)
        finally:
            output.unlink(missing_ok=True)

    def test_rejects_output_outside_owned_folder(self):
        with self.assertRaisesRegex(ConsumerError, "consumer-owned folder"):
            write_candidate_atomic(Path("/tmp/not-owned.json"), {})

    def test_explicit_hidden_reason_is_copied_from_proof(self):
        resolution, graph_usrs = fixture_resolution()
        row = resolution["publicCompilerCatalogue"][-1]
        row.update(status="hidden", hiddenReason="macOS-unavailable: SwiftUI:42 @available(macOS, unavailable)")
        row["sourceDeclarations"][0]["status"] = "public-compiler-mapped-attributed-unavailable"
        source = resolution["rows"][1]
        source["status"] = "public-compiler-mapped-attributed-unavailable"
        source["attributedRestrictions"] = [{"category": "macOS-unavailable", "attribute": {"text": "@available(macOS, unavailable)"}}]
        row["sourceDeclarations"][0]["restrictions"] = source["attributedRestrictions"]
        resolution["byStatus"]["eligible-compiler-mapped"] -= 1
        resolution["byStatus"]["public-compiler-mapped-attributed-unavailable"] = 1
        result = self.merge(resolution, graph_usrs)
        self.assertEqual(result["symbols"][-1]["status"], "hidden")
        self.assertEqual(result["symbols"][-1]["hiddenReason"], row["hiddenReason"])

    def test_compiler_access_exclusion_is_accounted_without_catalogue_entry(self):
        resolution, graph_usrs = fixture_resolution()
        source = resolution["rows"][2]
        source["status"] = "excluded-nonpublic-compiler-access"
        resolution["byStatus"]["excluded-nonpublic-source"] -= 1
        resolution["byStatus"]["excluded-nonpublic-compiler-access"] = 1

        result = self.merge(resolution, graph_usrs)
        self.assertEqual(result["symbols"][:len(BASE["symbols"])], BASE["symbols"])
        self.assertEqual(len(result["symbols"]), len(BASE["symbols"]) + 1)
        self.assertEqual(result["symbols"][-1]["usr"], "s:11SwiftUI5ProofV4itemyyF")

    def test_rejects_tampered_base_or_shared_metadata(self):
        changed = deepcopy(BASE)
        changed["symbolGraph"]["target"] += ".1"
        with self.assertRaisesRegex(ConsumerError, "base catalogue canonical hash"):
            self.merge(base=changed)
        self.assertEqual(canonical_hash(BASE), BASE_CATALOGUE_SHA256)

    def test_rejects_incomplete_or_held_proof(self):
        resolution, graph_usrs = fixture_resolution()
        resolution["status"] = "incomplete-held-source-universe-reconciliation"
        with self.assertRaisesRegex(ConsumerError, "not final/complete"):
            self.merge(resolution, graph_usrs)
        resolution["status"] = consumer.EXPECTED_PROOF_STATUS
        resolution["rows"].append({
            "status": "held-unresolved", "lineageV12": False,
            "key": ["SwiftUI", "arm64e-apple-macos.swiftinterface", 30000, "held"],
        })
        resolution["fullSourceDeclarationStarts"] += 1
        resolution["addedSourceDeclarationStarts"] = 1
        resolution["byStatus"]["held-unresolved"] = 1
        with self.assertRaisesRegex(ConsumerError, "retains held"):
            self.merge(resolution, graph_usrs)

    def test_rejects_path_drift_and_mixed_source_classification(self):
        resolution, graph_usrs = fixture_resolution()
        resolution["publicCompilerCatalogue"][-1]["path"] = "SwiftUI.Other.item()"
        with self.assertRaisesRegex(ConsumerError, "path differs"):
            self.merge(resolution, graph_usrs)
        resolution, graph_usrs = fixture_resolution()
        source = {
            "key": ["SwiftUI", "arm64e-apple-macos.swiftinterface", 12650, "item()"],
            "status": "public-compiler-mapped-documentation-hidden", "lineageV12": False,
            "usr": "s:11SwiftUI5ProofV4itemyyF", "compilerPath": "SwiftUI.Proof.item()",
            "kind": "func", "owner": None, "accessRule": "explicit source access",
            "attributedRestrictions": [],
        }
        resolution["rows"].append(source)
        resolution["fullSourceDeclarationStarts"] += 1
        resolution["addedSourceDeclarationStarts"] += 1
        resolution["byStatus"]["public-compiler-mapped-documentation-hidden"] = 1
        resolution["publicCompilerCatalogue"][-1]["sourceDeclarations"].append({
            "sourceKey": source["key"], "compilerPath": source["compilerPath"],
            "status": source["status"], "kind": source["kind"], "ancestor": None,
            "accessRule": source["accessRule"], "restrictions": [],
        })
        with self.assertRaisesRegex(ConsumerError, "mixed or missing"):
            self.merge(resolution, graph_usrs)

    def test_rejects_missing_coverage_graph_disagreement_and_extra_usr(self):
        resolution, graph_usrs = fixture_resolution()
        resolution["graphAbsentPublicCompilerUsrCount"] = 0
        with self.assertRaisesRegex(ConsumerError, "addition count"):
            self.merge(resolution, graph_usrs)
        resolution, graph_usrs = fixture_resolution()
        resolution["publicCompilerCatalogue"][-1]["graphPresent"] = True
        with self.assertRaisesRegex(ConsumerError, "graph membership mismatch"):
            self.merge(resolution, graph_usrs)
        resolution, graph_usrs = fixture_resolution()
        resolution["publicCompilerCatalogue"].append(deepcopy(resolution["publicCompilerCatalogue"][-1]))
        resolution["publicCompilerCatalogueUsrCount"] += 1
        with self.assertRaisesRegex(ConsumerError, "repeats compiler USR"):
            self.merge(resolution, graph_usrs)
        resolution, graph_usrs = fixture_resolution()
        extra = deepcopy(resolution["publicCompilerCatalogue"][-1])
        extra["usr"] = "s:11SwiftUI5ExtraV4itemyyF"
        extra["precise"] = extra["usr"]
        resolution["publicCompilerCatalogue"].append(extra)
        resolution["publicCompilerCatalogueUsrCount"] += 1
        resolution["graphAbsentPublicCompilerUsrCount"] += 1
        with self.assertRaisesRegex(ConsumerError, "source coverage differs"):
            self.merge(resolution, graph_usrs)

    def test_rejects_bad_proof_or_guard_hash(self):
        resolution, graph_usrs = fixture_resolution()
        with self.assertRaisesRegex(ConsumerError, "proof hash is malformed"):
            merge_catalogue(BASE, resolution, raw_graph_usrs=graph_usrs, proof_hash="bad",
                            guard_hash="sha256:" + "b" * 64, link_hash=consumer.IMMUTABLE_LINK_SHA256,
                            proof_input_refs=[], created_at=STAMP)
        with self.assertRaisesRegex(ConsumerError, "guard hash is malformed"):
            merge_catalogue(BASE, resolution, raw_graph_usrs=graph_usrs,
                            proof_hash="sha256:" + "a" * 64, guard_hash="bad",
                            link_hash=consumer.IMMUTABLE_LINK_SHA256, proof_input_refs=[], created_at=STAMP)

    def test_rejects_malformed_source_key_lineage_and_unknown_status(self):
        for field, value, message in [
            ("key", "SwiftUI.anything", "exactly four fields"),
            ("lineageV12", "true", "must be boolean"),
            ("status", "excluded-something-unreviewed", "status is unknown"),
        ]:
            resolution, graph_usrs = fixture_resolution()
            resolution["rows"][2][field] = value
            if field == "status":
                resolution["byStatus"]["excluded-nonpublic-source"] -= 1
                resolution["byStatus"][value] = 1
            with self.subTest(field=field), self.assertRaisesRegex(ConsumerError, message):
                self.merge(resolution, graph_usrs)

    def test_unset_final_pins_leave_candidate_untouched(self):
        output = consumer.OUTPUT_PATH
        before = output.read_bytes() if output.exists() else None
        with self.assertRaisesRegex(ConsumerError, "pins have not been cleared"):
            consumer.build_final_candidate(created_at=STAMP)
        self.assertEqual(output.read_bytes() if output.exists() else None, before)

    def test_atomic_replace_failure_preserves_destination_and_cleans_temp(self):
        resolution, graph_usrs = fixture_resolution()
        candidate = self.merge(resolution, graph_usrs)
        destination = Path(__file__).with_name(".replace-failure-test.json")
        destination.write_bytes(b"preexisting artifact")
        try:
            with patch.object(consumer.os, "replace", side_effect=OSError("fault")):
                with self.assertRaisesRegex(OSError, "fault"):
                    write_candidate_atomic(destination, candidate)
            self.assertEqual(destination.read_bytes(), b"preexisting artifact")
            self.assertEqual(list(destination.parent.glob(f".{destination.name}.*.tmp")), [])
        finally:
            destination.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
