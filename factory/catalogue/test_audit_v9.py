from __future__ import annotations

import json
import copy
import importlib.util
import tempfile
import unittest
from pathlib import Path

from factory.core import artifacts
from .audit_v9 import (
    CONTEXT_EVIDENCE_SHA256,
    V8_AUDIT_HASH,
    V8_FILE_SHA256,
    _load_v8,
    _bridge_module,
    _evaluate_context_claim,
    _parse_context_trees,
    _require_file_hash,
    _validate_input_join,
    _validate_context_bridge,
    build_audit_v9,
)


class AuditV9Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(__file__).resolve().parents[2]
        cls.v8_path = cls.root / "factory/catalogue/evidence/interface-audit-v8-candidate.json"
        cls.v8 = json.loads(cls.v8_path.read_text(encoding="utf-8"))
        cls.v7 = json.loads((cls.root / "factory/catalogue/evidence/interface-audit-v7.json").read_text(encoding="utf-8"))
        cls.bridge_path = cls.root / "factory/catalogue/residual-investigation/context-bridge-evidence.json"
        cls.bridge = _bridge_module()
        cls.evidence = json.loads(cls.bridge_path.read_text(encoding="utf-8"))
        cls.v7_authority = json.loads((cls.root / "factory/catalogue/evidence/interface-audit-v7.json").read_text(encoding="utf-8"))
        cls.links = json.loads((cls.root / "factory/catalogue/compiler-cursor-spike/link-evidence.json").read_text(encoding="utf-8"))
        cls.link_by_key = {(row["module"], row["line"], row["name"]): row for row in cls.links["rows"]}
        cls.interface_rows = {(row["module"], row["line"], row["name"]): row
                              for row in json.loads((cls.root / "factory/catalogue/evidence/interface-audit-v6.json").read_text(encoding="utf-8"))["declarations"]}
        cls.module_records = {item["module"]: item for item in cls.v7_authority["sourceKitAuthority"]["interfaces"]}
        cls.raw_by_module = {module: __import__("factory.catalogue.audit_v7", fromlist=["_index_entities"])._index_entities(cls.root / record["indexOutput"])
                             for module, record in cls.module_records.items()}
        cls.trees = cls.bridge.parse_sections((cls.root / "factory/catalogue/residual-investigation/swift-demangle-expand-v1.txt").read_text(encoding="utf-8"))
        cls.investigator = cls.bridge.load_investigator()

    def test_candidate_preserves_v8_and_promotes_only_173_cleared_context_rows(self) -> None:
        candidate = build_audit_v9(self.v8_path, root=self.root, context_bridge_path=self.bridge_path)
        self.assertEqual(candidate["parentAudit"]["auditHash"], V8_AUDIT_HASH)
        self.assertEqual(candidate["parentAudit"]["fileSha256"], V8_FILE_SHA256)
        self.assertEqual(candidate["summary"]["newlyPromotedRows"], 224)
        self.assertEqual(candidate["summary"]["exactSourceKitUsrLinks"], 2509)
        self.assertEqual(candidate["summary"]["heldSourceKitRows"], 40)
        self.assertEqual(candidate["summary"]["sourceKitUsrPresentInSymbolGraph"], 135)
        self.assertEqual(candidate["summary"]["sourceKitUsrAbsentFromSymbolGraph"], 2374)
        self.assertEqual(candidate["summary"]["remainingActiveUnmappedAmbiguousOrUnexplained"], 40)
        self.assertEqual(candidate["summary"]["byClassification"]["unexplained"], 34)
        self.assertEqual(candidate["contextBridgeEvidence"]["promotedRows"], 173)
        self.assertEqual(candidate["contextBridgeEvidence"]["heldModuleAliasRows"], 33)
        self.assertEqual(candidate["status"], "incomplete-v9-context-bridge-consumer-validated")
        body = dict(candidate)
        declared_hash = body.pop("auditHash")
        self.assertEqual(declared_hash, artifacts.canonical_hash(body))

    def test_v8_snapshot_and_context_evidence_are_hash_pinned(self) -> None:
        _load_v8(self.v8_path)
        altered_v8 = json.loads(self.v8_path.read_text(encoding="utf-8"))
        altered_v8["summary"]["exactSourceKitUsrLinks"] += 1
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "v8.json"
            path.write_text(json.dumps(altered_v8), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "bytes differ"):
                _load_v8(path)
            bridge = json.loads(self.bridge_path.read_text(encoding="utf-8"))
            bridge["rows"][0]["raw"]["usr"] = "s:forged"
            bridge_path = Path(directory) / "context.json"
            bridge_path.write_text(json.dumps(bridge), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "evidence differs"):
                _validate_context_bridge(bridge_path, self.v8, root=self.root)
        self.assertEqual(artifacts.file_hash(self.bridge_path), CONTEXT_EVIDENCE_SHA256)

    def test_33_nominal_module_aliases_remain_held(self) -> None:
        candidate = build_audit_v9(self.v8_path, root=self.root, context_bridge_path=self.bridge_path)
        held = next(item for item in candidate["pendingEvidence"]
                    if item["kind"] == "unsupported-compiler-nominal-module-alias")
        self.assertEqual(held["expectedRows"], 33)
        self.assertEqual(held["state"], "held-no-alias-inference")
        self.assertEqual(candidate["summary"]["heldSourceKitReasons"]["raw-sourcekit-context-does-not-match-interface-context"], 33)

    def _accepted_fixture(self, *, extension: bool = False):
        for claim in self.evidence["rows"]:
            link = self.link_by_key[(claim["module"], claim["line"], claim["name"])]
            if not claim["bridge"]["proposedBridgeEligible"]:
                continue
            if extension and claim["compilerOwner"].get("extensionModule") is None:
                continue
            entities = [entity for entity in self.raw_by_module[claim["module"]]
                        if entity.get("line") == claim["line"]
                        and entity.get("name") == claim["raw"]["name"]]
            if len(entities) == 1:
                scopes = self.interface_rows[(claim["module"], claim["line"], claim["name"])]
                scopes = scopes["v6Evidence"]["enclosingScopes"]
                tree = self.trees["$s" + claim["raw"]["usr"][2:]]
                return copy.deepcopy(link), copy.deepcopy(claim), copy.deepcopy(entities[0]), copy.deepcopy(tree), copy.deepcopy(scopes)
        self.fail("no matching reviewed context bridge fixture")

    def _sync_mutated_owner_claim(self, link, claim, entity, tree, scopes):
        owner = self.bridge.structural_owner(tree, claim["name"])
        expected_module = self.bridge.expected_nominal_module(link, scopes)
        module_provenance = claim["bridge"]["moduleProvenance"]
        module_provenance.update({
            "expectedNominalModule": expected_module,
            "compilerNominalModule": owner.get("nominalModule"),
            "compilerExtensionModule": owner.get("extensionModule"),
            "nominalModuleExact": owner.get("nominalModule") == expected_module,
            "extensionModuleExact": owner.get("extensionModule") is None or owner.get("extensionModule") == link["module"],
        })
        claim["compilerOwner"] = owner
        owner_match = self.bridge.owner_matches_row(link, owner, expected_module)
        kind_match = self.investigator.kind_matches(link["kind"], entity["kind"])
        access_match = self.investigator.access_matches(link, entity)
        context_match = self.investigator.context_matches(link, entity)
        access_level = entity.get("effective_access", "").rsplit(".", 1)[-1]
        raw_identity = self.bridge.raw_entity_matches(link, [entity], self.investigator)
        claim["bridge"].update({
            "structuralOwnerExact": owner_match,
            "kindMatch": kind_match,
            "accessMatch": access_match,
            "strictContextMatch": context_match,
            "proposedBridgeEligible": bool(raw_identity and owner_match and kind_match and access_match
                                            and not context_match and access_level in {"public", "open"}),
        })

    def test_production_context_gate_rejects_access_kind_and_duplicate_faults(self) -> None:
        link, claim, entity, tree, scopes = self._accepted_fixture()
        good = _evaluate_context_claim(link, claim, [entity], tree, scopes, self.bridge, self.investigator)
        self.assertTrue(good["eligible"])

        private_link, private_claim, private_entity, private_tree, private_scopes = self._accepted_fixture()
        private_link["signature"] = private_link["signature"].replace("public", "private", 1)
        private_entity["effective_access"] = "source.decl.effective_access.private"
        private_claim["raw"]["effective_access"] = private_entity["effective_access"]
        private_claim["bridge"]["accessMatch"] = True
        private_claim["bridge"]["proposedBridgeEligible"] = False
        rejected = _evaluate_context_claim(private_link, private_claim, [private_entity], private_tree,
                                          private_scopes, self.bridge, self.investigator)
        self.assertFalse(rejected["eligible"])
        self.assertEqual(rejected["accessLevel"], "private")

        kind_link, kind_claim, kind_entity, kind_tree, kind_scopes = self._accepted_fixture()
        kind_link["kind"] = "actor"
        kind_entity["kind"] = "source.lang.swift.decl.class"
        kind_claim["interfaceKind"] = "actor"
        kind_claim["raw"]["kind"] = kind_entity["kind"]
        kind_claim["bridge"]["kindMatch"] = False
        kind_claim["bridge"]["proposedBridgeEligible"] = False
        rejected = _evaluate_context_claim(kind_link, kind_claim, [kind_entity], kind_tree,
                                          kind_scopes, self.bridge, self.investigator)
        self.assertFalse(rejected["eligible"])

        with self.assertRaisesRegex(ValueError, "cardinality is 2"):
            _evaluate_context_claim(link, claim, [entity, copy.deepcopy(entity)], tree, scopes,
                                    self.bridge, self.investigator)

    def test_production_context_gate_rejects_altered_owner_module_generic_and_local_trees(self) -> None:
        link, claim, entity, tree, scopes = self._accepted_fixture(extension=True)
        self.bridge.mutate_nominal_module(tree, claim["compilerOwner"]["nominalModule"], "__wrong_module__")
        self._sync_mutated_owner_claim(link, claim, entity, tree, scopes)
        rejected = _evaluate_context_claim(link, claim, [entity], tree, scopes, self.bridge, self.investigator)
        self.assertFalse(rejected["eligible"])

        link, claim, entity, tree, scopes = self._accepted_fixture()
        tree.setdefault("children", []).append({"kind": "DependentGenericSignature", "text": None,
            "children": [{"kind": "Identifier", "text": claim["name"], "children": []}]})
        self._sync_mutated_owner_claim(link, claim, entity, tree, scopes)
        with self.assertRaisesRegex(ValueError, "generic-reference"):
            _evaluate_context_claim(link, claim, [entity], tree, scopes, self.bridge, self.investigator)

        link, claim, entity, tree, scopes = self._accepted_fixture()
        owner_node = next(node for node in self.bridge.walk_nodes(tree) if node.get("kind") in self.bridge.OWNER_KINDS)
        owner_node.setdefault("children", []).append({"kind": "Function", "text": "__local__", "children": []})
        self._sync_mutated_owner_claim(link, claim, entity, tree, scopes)
        rejected = _evaluate_context_claim(link, claim, [entity], tree, scopes, self.bridge, self.investigator)
        self.assertFalse(rejected["eligible"])

    def test_production_provenance_helpers_reject_source_request_demangle_and_tool_drift(self) -> None:
        module_record = self.module_records["SwiftUI"]
        for group, path_key, hash_key in (("interfaces", "path", "sha256"),
                                          ("rawIndexOutputs", "indexOutput", "indexOutputSha256"),
                                          ("rawIndexRequests", "indexRequest", "indexRequestSha256")):
            record = self.evidence["inputs"][group]["SwiftUI"]
            joined = _validate_input_join(record, expected_path=module_record[path_key],
                expected_sha=module_record[hash_key], root=self.root, label=f"test {group}")
            self.assertTrue(joined.is_file())
        with tempfile.TemporaryDirectory() as directory:
            fake = Path(directory) / "request.yaml"
            fake.write_text("not the pinned request", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "path/hash"):
                _validate_input_join({"path": str(fake), "sha256": artifacts.file_hash(fake)},
                    expected_path=module_record["indexRequest"], expected_sha=module_record["indexRequestSha256"],
                    root=self.root, label="test request")
            with self.assertRaisesRegex(ValueError, "tool bytes"):
                _require_file_hash(fake, self.evidence["inputs"]["swiftDemangle"]["sha256"], "tool")
        expected_usrs = set(self.trees)
        parsed = _parse_context_trees(self.bridge,
            self.root / "factory/catalogue/residual-investigation/swift-demangle-expand-v1.txt",
            self.evidence["inputs"]["expandedOutput"]["sha256"], expected_usrs)
        self.assertEqual(len(parsed), 206)
        with self.assertRaisesRegex(ValueError, "USR set"):
            _parse_context_trees(self.bridge,
                self.root / "factory/catalogue/residual-investigation/swift-demangle-expand-v1.txt",
                self.evidence["inputs"]["expandedOutput"]["sha256"], {"$swrong"})


if __name__ == "__main__":
    unittest.main()
