from __future__ import annotations

from copy import deepcopy
import json
import importlib.util
from pathlib import Path
import sys
import tempfile
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
load_accepted_proof = consumer._load_accepted_proof


ROOT = Path(__file__).resolve().parents[3]
BASE = json.loads((ROOT / "factory/catalogue/evidence/catalogue.json").read_text())
STAMP = "2026-10-11T00:00:00Z"


class ProofLoaderPinTests(unittest.TestCase):
    def test_compressed_proof_passes_stored_and_raw_exact_pins(self):
        calls = []
        class Guard:
            @staticmethod
            def load_artifact(path, expected_sha256, *, expected_raw_sha256, expected_raw_bytes):
                calls.append((path, expected_sha256, expected_raw_sha256, expected_raw_bytes))
                return "accepted"
        path = Path("evidence-v2.json.gz")
        result = load_accepted_proof(
            Guard, path, stored_sha256="sha256:" + "a" * 64,
            raw_sha256="sha256:" + "b" * 64, raw_bytes=138_988_880,
        )
        self.assertEqual(result, "accepted")
        self.assertEqual(calls, [(path, "sha256:" + "a" * 64, "sha256:" + "b" * 64, 138_988_880)])

    def test_compressed_proof_rejects_missing_raw_loader_pins(self):
        class Guard:
            @staticmethod
            def load_artifact(path, expected_sha256):
                return None
        with self.assertRaisesRegex(ConsumerError, "lacks exact raw-byte pin"):
            load_accepted_proof(Guard, Path("evidence.json.gz"),
                                stored_sha256="sha256:" + "a" * 64,
                                raw_sha256="sha256:" + "b" * 64, raw_bytes=100)

    def test_plain_proof_does_not_claim_compressed_raw_pins(self):
        calls = []
        class Guard:
            @staticmethod
            def load_artifact(path, trusted_final_sha256):
                calls.append((path, trusted_final_sha256))
                return "accepted"
        path = Path("evidence.json")
        self.assertEqual(load_accepted_proof(
            Guard, path, stored_sha256="sha256:" + "a" * 64,
            raw_sha256=None, raw_bytes=None,
        ), "accepted")
        self.assertEqual(calls, [(path, "sha256:" + "a" * 64)])


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
        "heldCompilerComponentCount": 0,
        "publicCompilerChildren": [],
        "publicCompilerChildRecordCount": 0,
        "publicCompilerChildUsrCount": 0,
        "heldPublicCompilerChildCount": 0,
        "compilerInventory": [
            {"module": "SwiftUI", "rawEntityIndex": 0, "line": 2,
             "name": "offset(to:allowedFields:maxFieldCount:sign:)", "usr": base_usr,
             "kind": "source.lang.swift.decl.function.method", "category": "source-start-present",
             "childEvidence": None},
            {"module": "SwiftUI", "rawEntityIndex": 1, "line": 3,
             "name": "item()", "usr": added_usr,
             "kind": "source.lang.swift.decl.function.method", "category": "source-start-present",
             "childEvidence": None},
        ],
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


def parent_api_exclusion_fixture() -> tuple[dict, set[str]]:
    resolution, graph_usrs = fixture_resolution()
    owner_row, parent_row = resolution["rows"][2:4]
    owner_row.update(key=["SwiftUI", "arm64e-apple-macos.swiftinterface", 4, "PrivateBox"],
                     kind="struct", explicitAccess="private", scopeLines=[],
                     conditions=[],
                     reason="explicit actual source declaration access private")
    parent_row.update(key=["SwiftUI", "arm64e-apple-macos.swiftinterface", 5, "value"],
                      kind="var", explicitAccess=None, scopeLines=[4],
                      conditions=[],
                      reason="enclosing nominal ancestor nonpublic/unspecified")
    owner_usr = "s:7SwiftUI10PrivateBoxV"
    parent_usr = "s:7SwiftUI10PrivateBoxV5valueSivp"
    child_usr = "s:7SwiftUI10PrivateBoxV5valueSivg"
    owner_raw = {
        "line": 4, "name": "PrivateBox", "kind": "source.lang.swift.decl.struct",
        "usr": owner_usr, "effective_access": "source.decl.effective_access.private",
    }
    typed_owner = {"line": 4, "name": "PrivateBox", "kind": "struct_decl", "access": "private"}
    typed_property = {"line": 5, "name": "value", "kind": "var_decl", "access": "public"}
    owner_tree = {"kind": "Structure", "children": [
        {"kind": "Module", "text": "SwiftUI", "index": None, "children": []},
        {"kind": "Identifier", "text": "PrivateBox", "index": None, "children": []},
    ], "text": None, "index": None}
    owner_record = {
        "module": "SwiftUI", "rawEntityIndex": 2, "line": 4, "name": "PrivateBox",
        "usr": owner_usr, "kind": owner_raw["kind"],
        "effectiveAccess": owner_raw["effective_access"], "category": "source-start-present",
        "childEvidence": None,
    }
    parent_record = {
        "module": "SwiftUI", "rawEntityIndex": 3, "line": 5, "name": "value",
        "usr": parent_usr, "kind": "source.lang.swift.decl.var.instance",
        "effectiveAccess": "source.decl.effective_access.public", "category": "source-start-present",
        "childEvidence": None,
    }
    source_key = parent_row["key"]
    anchor = {"sourceKey": source_key, "usr": parent_usr,
              "kind": parent_record["kind"], "rawCardinality": 1}
    child = {
        "usr": child_usr, "parentUsr": parent_usr, "parentSourceKey": source_key,
        "kind": "source.lang.swift.decl.function.accessor.getter", "typedAccess": "public",
        "typedAST": {"kind": "accessor_decl", "family": "get", "line": 5,
                     "access": "public", "propertyName": "value",
                     "owners": [typed_owner, typed_property]},
        "parentSourceStatus": "excluded-nonpublic-source",
        "parentRawCardinality": 1, "conditions": [],
        "tree": {"children": [{"kind": "Variable", "children": [owner_tree]}]},
        "status": "excluded-nonpublic-parent-api",
        "reason": "public typed component is capped by exact source/raw/typed nonpublic enclosing nominal",
        "effectivePublic": False,
        "nonpublicOwnerEvidence": [{
            "sourceScope": {"line": 4, "name": "PrivateBox", "kind": "struct", "explicitAccess": "private",
                            "scopeLines": [], "path": ["PrivateBox"], "conditions": []},
            "rawNominal": owner_raw, "typedNominalAST": typed_owner, "nominalTree": owner_tree,
        }],
    }
    child_record = {
        "module": "SwiftUI", "rawEntityIndex": 4, "line": 5, "name": "getter:value",
        "usr": child_usr, "kind": child["kind"],
        "effectiveAccess": None, "category": "source-property-accessor",
        "parentAnchor": anchor, "childEvidence": child,
    }
    resolution["compilerInventory"].extend([owner_record, parent_record, child_record])
    resolution["compilerRecordCount"] = 5
    resolution["compilerRecordCategories"] = {"source-start-present": 4, "source-property-accessor": 1}
    return resolution, graph_usrs


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

    def test_public_accessor_capped_by_exact_nonpublic_parent_is_not_promoted(self):
        resolution, graph_usrs = parent_api_exclusion_fixture()
        result = self.merge(resolution, graph_usrs)
        self.assertEqual(len(result["symbols"]), len(BASE["symbols"]) + 1)
        self.assertEqual(result["symbols"][-1]["usr"], "s:11SwiftUI5ProofV4itemyyF")
        child = resolution["compilerInventory"][-1]["childEvidence"]
        child["effectivePublic"] = True
        with self.assertRaisesRegex(ConsumerError, "false effectivePublic"):
            self.merge(resolution, graph_usrs)

    def test_nonpublic_parent_witnesses_require_exact_source_raw_typed_and_tree_links(self):
        mutations = [
            (lambda c: c.update(nonpublicOwnerEvidence=[]), "lacks owner witnesses"),
            (lambda c: c["nonpublicOwnerEvidence"][0]["rawNominal"].update(usr="s:wrong"), "unique exact raw compiler entity"),
            (lambda c: c["nonpublicOwnerEvidence"][0]["typedNominalAST"].update(access="public"), "typed nonpublic owner AST"),
            (lambda c: c["nonpublicOwnerEvidence"][0].update(nominalTree={"kind": "Variable", "children": [], "text": None, "index": None}), "not an expanded nominal node"),
            (lambda c: c["nonpublicOwnerEvidence"][0]["nominalTree"]["children"][1].update(text="WrongNominal"), "demangle tree identity differs"),
            (lambda c: c["nonpublicOwnerEvidence"][0]["nominalTree"]["children"][0]["children"].append({"kind": "Function"}), "module leaf has noncanonical expanded shape"),
            (lambda c: c["nonpublicOwnerEvidence"].append(deepcopy(c["nonpublicOwnerEvidence"][0])), "witness is duplicated"),
            (lambda c: c["nonpublicOwnerEvidence"][0]["sourceScope"].update(conditions=[{"ifLine": 99}]), "matching excluded source nominal row"),
            (lambda c: c.update(parentRawCardinality=True), "parent cardinality/conditional binding"),
            (lambda c: c["typedAST"].update(access="internal"), "typed accessor AST access/kind/family/line"),
            (lambda c: c["typedAST"].update(kind="function_decl"), "typed accessor AST access/kind/family/line"),
            (lambda c: c["typedAST"].update(family="set"), "typed accessor AST access/kind/family/line"),
            (lambda c: c["typedAST"].update(line=99), "typed accessor AST access/kind/family/line"),
            (lambda c: c["typedAST"].update(propertyName="other"), "property name differs"),
            (lambda c: c["typedAST"].update(owners=[]), "lacks exact source property/subscript owner"),
            (lambda c: c.update(rawAccess="internal"), "contradictory raw accessor access"),
        ]
        for mutate, message in mutations:
            with self.subTest(message=message):
                resolution, graph_usrs = parent_api_exclusion_fixture()
                record = resolution["compilerInventory"][-1]
                if message == "contradictory raw accessor access":
                    record["effectiveAccess"] = "source.decl.effective_access.internal"
                else:
                    mutate(record["childEvidence"])
                with self.assertRaisesRegex(ConsumerError, message):
                    self.merge(resolution, graph_usrs)

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

    def test_rejects_compiler_child_missing_exact_parent_or_inventory_join(self):
        resolution, graph_usrs = fixture_resolution()
        child = {
            "usr": "s:11SwiftUI5ProofV5valueSivg",
            "parentUsr": "s:11SwiftUI5ProofV5valueSivp",
            "parentSourceKey": ["SwiftUI", "arm64e-apple-macos.swiftinterface", 3, "item()"],
            "kind": "source.lang.swift.decl.function.accessor.getter",
            "typedAccess": "public", "parentSourceStatus": "eligible-compiler-mapped",
            "status": "eligible-compiler-mapped",
        }
        parent_anchor = {
            "sourceKey": resolution["rows"][1]["key"], "usr": resolution["rows"][1]["usr"],
            "kind": resolution["compilerInventory"][1]["kind"], "rawCardinality": 1,
        }
        inventory_row = {
            "module": "SwiftUI", "rawEntityIndex": 2, "line": 3, "name": "item.getter",
            "usr": child["usr"], "kind": child["kind"], "category": "source-property-accessor",
            "parentAnchor": parent_anchor, "childEvidence": child,
        }
        resolution["compilerInventory"].append(inventory_row)
        resolution["compilerRecordCount"] += 1
        resolution["compilerRecordCategories"] = {
            "source-start-present": 2, "source-property-accessor": 1,
        }
        grouped_child = deepcopy(child)
        grouped_child["rawCardinality"] = 1
        grouped_child["rawOccurrences"] = [{
            "module": "SwiftUI", "rawEntityIndex": 2, "parentAnchor": parent_anchor,
        }]
        resolution["publicCompilerChildren"] = [grouped_child]
        resolution["publicCompilerChildRecordCount"] = 1
        resolution["publicCompilerChildUsrCount"] = 1
        with self.assertRaisesRegex(ConsumerError, "differs from raw inventory anchor"):
            self.merge(resolution, graph_usrs)
        child["parentUsr"] = resolution["rows"][1]["usr"]
        resolution["publicCompilerChildren"][0] = deepcopy(child)
        resolution["publicCompilerChildren"][0]["rawCardinality"] = 1
        resolution["publicCompilerChildren"][0]["rawOccurrences"] = [{
            "module": "SwiftUI", "rawEntityIndex": 2, "parentAnchor": parent_anchor,
        }]
        result = self.merge(resolution, graph_usrs)
        self.assertEqual(len(result["symbols"]), len(BASE["symbols"]) + 1)
        self.assertNotIn(child["usr"], {symbol["usr"] for symbol in result["symbols"]})
        resolution["publicCompilerChildRecordCount"] = 2
        with self.assertRaisesRegex(ConsumerError, "raw-record denominator"):
            self.merge(resolution, graph_usrs)
        resolution["publicCompilerChildRecordCount"] = 1
        resolution["publicCompilerChildUsrCount"] = 2
        with self.assertRaisesRegex(ConsumerError, "USR denominator"):
            self.merge(resolution, graph_usrs)
        resolution["publicCompilerChildUsrCount"] = 1
        resolution["publicCompilerChildren"][0]["rawCardinality"] = True
        with self.assertRaisesRegex(ConsumerError, "raw cardinality is malformed"):
            self.merge(resolution, graph_usrs)
        resolution["publicCompilerChildren"][0]["rawCardinality"] = 1
        child["usr"] = "s:forged-child"
        with self.assertRaisesRegex(ConsumerError, "USR/kind differs"):
            self.merge(resolution, graph_usrs)
        child["usr"] = "s:11SwiftUI5ProofV5valueSivg"
        child["kind"] = "source.lang.swift.decl.function.accessor.setter"
        with self.assertRaisesRegex(ConsumerError, "USR/kind differs"):
            self.merge(resolution, graph_usrs)
        child["kind"] = "source.lang.swift.decl.function.accessor.getter"
        inventory_row["kind"] = "source.lang.swift.decl.generic_type_param"
        with self.assertRaisesRegex(ConsumerError, "wrong raw kind"):
            self.merge(resolution, graph_usrs)
        inventory_row["kind"] = "source.lang.swift.decl.function.accessor.getter"
        child["status"] = "public-compiler-mapped-documentation-hidden"
        with self.assertRaisesRegex(ConsumerError, "same public parent API"):
            self.merge(resolution, graph_usrs)
        child["status"] = "eligible-compiler-mapped"
        child["typedAccess"] = "private"
        with self.assertRaisesRegex(ConsumerError, "invalid classification"):
            self.merge(resolution, graph_usrs)
        child["status"] = "excluded-nonpublic-compiler-access"
        resolution["publicCompilerChildren"] = []
        resolution["publicCompilerChildRecordCount"] = 0
        resolution["publicCompilerChildUsrCount"] = 0
        self.merge(resolution, graph_usrs)

    def test_rejects_compiler_record_with_forged_parent_anchor(self):
        resolution, graph_usrs = fixture_resolution()
        record = {
            "module": "SwiftUI", "rawEntityIndex": 2, "line": 3, "name": "item.getter",
            "usr": "s:11SwiftUI5ProofV5valueSivg",
            "kind": "source.lang.swift.decl.function.accessor.getter",
            "category": "source-property-accessor",
            "childEvidence": {
                "usr": "s:11SwiftUI5ProofV5valueSivg",
                "parentUsr": "s:forged-parent",
                "parentSourceKey": resolution["rows"][1]["key"],
                "kind": "source.lang.swift.decl.function.accessor.getter",
                "typedAccess": "public", "parentSourceStatus": "eligible-compiler-mapped",
                "status": "eligible-compiler-mapped",
            },
        }
        record["parentAnchor"] = {
            "sourceKey": resolution["rows"][1]["key"], "usr": "s:forged-parent",
            "kind": resolution["compilerInventory"][1]["kind"], "rawCardinality": 1,
        }
        resolution["compilerInventory"].append(record)
        resolution["compilerRecordCount"] += 1
        resolution["compilerRecordCategories"] = {
            "source-start-present": 2, "source-property-accessor": 1,
        }
        with self.assertRaisesRegex(ConsumerError, "parent anchor differs"):
            self.merge(resolution, graph_usrs)

    def test_nonaccessor_child_status_and_physical_disagreement_are_exact(self):
        resolution, graph_usrs = fixture_resolution()
        parent_record = resolution["compilerInventory"][1]
        anchor = {
            "sourceKey": resolution["rows"][1]["key"], "usr": resolution["rows"][1]["usr"],
            "kind": parent_record["kind"], "rawCardinality": 1,
        }
        record = {
            "module": "SwiftUI", "rawEntityIndex": 2, "line": 3, "name": "T",
            "usr": "s:11SwiftUI1TV", "kind": "source.lang.swift.decl.generic_type_param",
            "category": "source-generic-parameter", "parentAnchor": anchor,
            "childEvidence": {
            "status": "forged-status", "tree": {"kind": "GenericParameter"},
            "parentUsr": anchor["usr"], "parentSourceKey": anchor["sourceKey"],
            },
        }
        resolution["compilerInventory"].append(record)
        resolution["compilerRecordCount"] += 1
        resolution["compilerRecordCategories"] = {
            "source-start-present": 2, "source-generic-parameter": 1,
        }
        with self.assertRaisesRegex(ConsumerError, "unknown exact status"):
            self.merge(resolution, graph_usrs)
        record["childEvidence"].update(
            status="attributed-physical-parent-component-tree-disagreement",
            childTree={"kind": "Function"}, parentTree={"kind": "Property"},
            typedPhysicalParent={"kind": "Variable"},
            canonicalIdentityTransferred=False,
        )
        self.merge(resolution, graph_usrs)
        for field in ("childTree", "parentTree", "typedPhysicalParent"):
            original = record["childEvidence"][field]
            for forged in (None, [], "tree"):
                record["childEvidence"][field] = forged
                with self.assertRaisesRegex(ConsumerError, "paired trees/parent"):
                    self.merge(resolution, graph_usrs)
            record["childEvidence"][field] = original
        record["childEvidence"]["canonicalIdentityTransferred"] = True
        with self.assertRaisesRegex(ConsumerError, "transferred canonical identity"):
            self.merge(resolution, graph_usrs)

    def test_typed_component_tree_must_be_an_object(self):
        resolution, graph_usrs = fixture_resolution()
        parent_record = resolution["compilerInventory"][1]
        anchor = {
            "sourceKey": resolution["rows"][1]["key"], "usr": resolution["rows"][1]["usr"],
            "kind": parent_record["kind"], "rawCardinality": 1,
        }
        record = {
            "module": "SwiftUI", "rawEntityIndex": 2, "line": 3, "name": "T",
            "usr": "s:11SwiftUI1TV", "kind": "source.lang.swift.decl.generic_type_param",
            "category": "source-generic-parameter", "parentAnchor": anchor,
            "childEvidence": {
                "status": "attributed-typed-parent-component", "tree": {"kind": "GenericParameter"},
                "parentUsr": anchor["usr"], "parentSourceKey": anchor["sourceKey"],
            },
        }
        resolution["compilerInventory"].append(record)
        resolution["compilerRecordCount"] += 1
        resolution["compilerRecordCategories"] = {
            "source-start-present": 2, "source-generic-parameter": 1,
        }
        self.merge(resolution, graph_usrs)
        for forged in (None, [], "tree"):
            record["childEvidence"]["tree"] = forged
            with self.assertRaisesRegex(ConsumerError, "exact typed tree"):
                self.merge(resolution, graph_usrs)

    def test_raw_graph_archive_fallback_and_original_precedence(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            graph_a = b'{"symbols":[{"precise":"usr-a"}]}'
            graph_b = b'{"symbols":[{"precise":"usr-b"}]}'
            (root / "a.json").write_bytes(graph_a)
            closure = consumer._digest(json.dumps(["usr-a", "usr-b"], separators=(",", ":")).encode())
            link = {
                "kind": "sourcekit-interface-index-link-spike",
                "rawGraphInputs": [
                    {"path": "a.json", "sha256": consumer._digest(graph_a)},
                    {"path": "b.json", "sha256": consumer._digest(graph_b)},
                ],
                "rawGraphUsrClosure": {"rawGraphUsrCount": 2, consumer.GRAPH_USR_SET_KEY: closure},
            }
            archive_root = root / "archived"
            archive_root.mkdir()
            (archive_root / "a.json").write_bytes(graph_a)
            (archive_root / "b.json").write_bytes(graph_b)
            calls = []
            def loader(descriptors):
                calls.append(descriptors)
                return {name: archive_root / name for name in ("a.json", "b.json")}

            self.assertEqual(consumer.raw_graph_usr_closure(link, str(root), archive_loader=loader),
                             {"usr-a", "usr-b"})
            self.assertEqual(len(calls), 1)
            (root / "a.json").write_bytes(b"tampered")
            with self.assertRaisesRegex(ConsumerError, "present original raw graph bytes changed"):
                consumer.raw_graph_usr_closure(link, str(root), archive_loader=loader)

    def test_raw_graph_archive_rejects_wrong_reconstructed_bytes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            graph = b'{"symbols":[{"precise":"usr-a"}]}'
            bad = b'{"symbols":[{"precise":"usr-other"}]}'
            link = {
                "kind": "sourcekit-interface-index-link-spike",
                "rawGraphInputs": [{"path": "missing.json", "sha256": consumer._digest(graph)}],
                "rawGraphUsrClosure": {
                    "rawGraphUsrCount": 1,
                    consumer.GRAPH_USR_SET_KEY: consumer._digest(b'["usr-a"]'),
                },
            }
            reconstructed = Path(temp) / "bad.json"
            reconstructed.write_bytes(bad)
            with self.assertRaisesRegex(ConsumerError, "actual raw graph bytes changed"):
                consumer.raw_graph_usr_closure(
                    link, temp, archive_loader=lambda _descriptors: {"missing.json": reconstructed}
                )

    def test_unset_final_pins_leave_candidate_untouched(self):
        output = consumer.OUTPUT_PATH
        before = output.read_bytes() if output.exists() else None
        with patch.object(consumer, "FINAL_GUARD_SHA256", None), \
             patch.object(consumer, "FINAL_PROOF_PATH", None), \
             patch.object(consumer, "FINAL_PROOF_SHA256", None), \
             patch.object(consumer, "FINAL_PROOF_RAW_SHA256", None), \
             patch.object(consumer, "FINAL_PROOF_RAW_BYTES", None):
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

    def _manifest_for(self, artifact, resolution, *, candidate_name="candidate.json"):
        return consumer.build_derivation_manifest(
            artifact, resolution,
            candidate_path=Path(__file__).with_name(candidate_name),
            proof_hash="sha256:" + "a" * 64,
            guard_hash="sha256:" + "b" * 64,
            link_hash=consumer.IMMUTABLE_LINK_SHA256,
            proof_input_refs=[],
        )

    def test_candidate_manifest_binds_base_proof_counts_and_bytes(self):
        resolution, graph_usrs = fixture_resolution()
        artifact = self.merge(resolution, graph_usrs)
        candidate_path = Path(__file__).with_name(".candidate-manifest-test.json")
        manifest_path = Path(__file__).with_name(".candidate-manifest-test.manifest.json")
        manifest = self._manifest_for(artifact, resolution, candidate_name=candidate_path.name)
        try:
            candidate_hash, manifest_hash = consumer.write_candidate_bundle_atomic(
                candidate_path, manifest_path, artifact, manifest, resolution=resolution,
            )
            self.assertEqual(candidate_hash, consumer._digest(candidate_path.read_bytes()))
            self.assertEqual(manifest_hash, consumer._digest(manifest_path.read_bytes()))
            loaded = json.loads(manifest_path.read_text())
            self.assertEqual(loaded["candidate"]["sha256"], candidate_hash)
            self.assertEqual(loaded["base"]["rawSourceHash"], consumer.BASE_SOURCE_SHA256)
            self.assertEqual(loaded["proof"]["acceptedResolutionCanonicalHash"],
                             artifact["provenance"]["sourceHash"])
            tampered = deepcopy(loaded)
            tampered["coverage"]["outputSymbolCount"] += 1
            with self.assertRaisesRegex(ConsumerError, "counts disagree"):
                consumer.write_candidate_bundle_atomic(candidate_path, manifest_path, artifact, tampered,
                                                       resolution=resolution)
            for field in ("publicCompilerChildGroups", "publicCompilerChildRecords",
                          "publicCompilerChildOccurrences"):
                tampered = deepcopy(loaded)
                tampered["coverage"][field] += 1
                with self.subTest(field=field), self.assertRaisesRegex(ConsumerError, "counts disagree"):
                    consumer.write_candidate_bundle_atomic(candidate_path, manifest_path, artifact, tampered,
                                                           resolution=resolution)
            tampered = deepcopy(loaded)
            tampered["coverage"]["publicCompilerChildGroups"] = False
            with self.assertRaisesRegex(ConsumerError, "numeric coverage fields"):
                consumer.write_candidate_bundle_atomic(candidate_path, manifest_path, artifact, tampered,
                                                       resolution=resolution)
            tampered = deepcopy(loaded)
            tampered["coverage"]["compilerRecordCategoryCounts"]["source-start-present"] = 2.0
            with self.assertRaisesRegex(ConsumerError, "nested counts"):
                consumer.write_candidate_bundle_atomic(candidate_path, manifest_path, artifact, tampered,
                                                       resolution=resolution)
            tampered = deepcopy(loaded)
            tampered["base"]["symbolCount"] = float(consumer.BASE_SYMBOL_COUNT)
            with self.assertRaisesRegex(ConsumerError, "base provenance"):
                consumer.write_candidate_bundle_atomic(candidate_path, manifest_path, artifact, tampered,
                                                       resolution=resolution)
            self.assertEqual(candidate_path.read_bytes(), consumer.dump_bytes(artifact))
            self.assertEqual(json.loads(manifest_path.read_text()), loaded)
        finally:
            candidate_path.unlink(missing_ok=True)
            manifest_path.unlink(missing_ok=True)

    def test_candidate_manifest_pair_rolls_back_if_sidecar_replace_fails(self):
        resolution, graph_usrs = fixture_resolution()
        artifact = self.merge(resolution, graph_usrs)
        candidate_path = Path(__file__).with_name(".candidate-pair-rollback.json")
        manifest_path = Path(__file__).with_name(".candidate-pair-rollback.manifest.json")
        previous_candidate, previous_manifest = b"old-candidate", b"old-manifest"
        candidate_path.write_bytes(previous_candidate)
        manifest_path.write_bytes(previous_manifest)
        manifest = self._manifest_for(artifact, resolution, candidate_name=candidate_path.name)
        actual_replace = consumer.os.replace
        calls = 0

        def replace_with_one_fault(source, destination):
            nonlocal calls
            calls += 1
            if calls == 2:
                raise OSError("sidecar replace fault")
            return actual_replace(source, destination)

        try:
            with patch.object(consumer.os, "replace", side_effect=replace_with_one_fault):
                with self.assertRaisesRegex(OSError, "sidecar replace fault"):
                    consumer.write_candidate_bundle_atomic(
                        candidate_path, manifest_path, artifact, manifest, resolution=resolution,
                    )
            self.assertEqual(candidate_path.read_bytes(), previous_candidate)
            self.assertEqual(manifest_path.read_bytes(), previous_manifest)
            self.assertEqual(list(candidate_path.parent.glob(f".{candidate_path.name}.*.tmp")), [])
            self.assertEqual(list(manifest_path.parent.glob(f".{manifest_path.name}.*.tmp")), [])
        finally:
            candidate_path.unlink(missing_ok=True)
            manifest_path.unlink(missing_ok=True)


if __name__ == "__main__":
    unittest.main()
