from __future__ import annotations

import json
import copy
import tempfile
import unittest
from pathlib import Path

from factory.core import artifacts
from .audit_v7 import _index_entities
from .audit_v8 import (
    V7_AUDIT_HASH,
    V7_FILE_SHA256,
    _raw_access_entity,
    _validate_access_entity_claim,
    _validate_access_scope,
    _validate_live_tool_bindings,
    _validate_pinned_v7,
    build_audit_v8,
)


class AuditV8ScaffoldTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(__file__).resolve().parents[2]
        cls.v7_path = cls.root / "factory/catalogue/evidence/interface-audit-v7.json"
        cls.v7 = json.loads(cls.v7_path.read_text(encoding="utf-8"))

    def test_v8_baseline_preserves_v7_rows_and_marks_unvalidated_bridges_pending(self) -> None:
        candidate = build_audit_v8(self.v7_path, root=self.root)
        self.assertEqual(candidate["status"], "incomplete-awaiting-independent-bridge-validation")
        self.assertEqual(candidate["parentAudit"]["auditHash"], V7_AUDIT_HASH)
        self.assertEqual(candidate["parentAudit"]["fileSha256"], V7_FILE_SHA256)
        self.assertEqual(candidate["declarations"], self.v7["declarations"])
        self.assertEqual(candidate["summary"]["newlyPromotedRows"], 0)
        self.assertEqual(candidate["summary"]["remainingActiveUnmappedAmbiguousOrUnexplained"], 264)
        self.assertTrue(any(item["path"] is None and item["state"] == "awaiting reviewed receipt path"
                            for item in candidate["pendingEvidence"]))
        body = dict(candidate)
        audit_hash = body.pop("auditHash")
        self.assertEqual(audit_hash, artifacts.canonical_hash(body))

    def test_mutated_v7_bytes_fail_closed_before_v8_generation(self) -> None:
        altered = json.loads(self.v7_path.read_text(encoding="utf-8"))
        altered["summary"]["exactSourceKitUsrLinks"] += 1
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "interface-audit-v7.json"
            path.write_text(json.dumps(altered), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "bytes differ from committed v7"):
                build_audit_v8(path, root=self.root)

    def test_wrong_sourcekit_authority_is_rejected(self) -> None:
        altered = json.loads(self.v7_path.read_text(encoding="utf-8"))
        altered["sourceKitAuthority"]["evidenceSha256"] = "sha256:" + "0" * 64
        altered.pop("auditHash")
        altered["auditHash"] = artifacts.canonical_hash(altered)
        with self.assertRaisesRegex(ValueError, "does not pin expected immutable SourceKit"):
            _validate_pinned_v7(altered, V7_FILE_SHA256)

    def test_oracle_cleared_access_bridge_is_rechecked_against_raw_sdk_inputs(self) -> None:
        bridge_path = self.root / "factory/catalogue/access-inheritance-spike/derived-access-bridge.json"
        candidate = build_audit_v8(self.v7_path, root=self.root, access_bridge_path=bridge_path)
        self.assertEqual(candidate["summary"]["newlyPromotedRows"], 51)
        self.assertEqual(candidate["summary"]["exactSourceKitUsrLinks"], 2336)
        self.assertEqual(candidate["summary"]["heldSourceKitRows"], 213)
        self.assertEqual(candidate["summary"]["remainingActiveUnmappedAmbiguousOrUnexplained"], 213)
        self.assertEqual(candidate["status"], "incomplete-v8-access-bridge-consumer-review-pending")
        self.assertEqual(51, candidate["summary"]["sourceKitUsrAbsentFromSymbolGraph"]
                         + candidate["summary"]["sourceKitUsrPresentInSymbolGraph"] - 2285)
        self.assertEqual(51, sum(candidate["summary"]["byClassification"].get(name, 0)
                                 - self.v7["summary"]["byClassification"].get(name, 0)
                                 for name in ("matched-sourcekit-usr-in-symbolgraph",
                                              "matched-sourcekit-usr-absent-from-symbolgraph")))

    def test_access_entity_and_extension_scope_faults_fail_closed(self) -> None:
        bridge = json.loads((self.root / "factory/catalogue/access-inheritance-spike/derived-access-bridge.json")
                            .read_text(encoding="utf-8"))
        candidate = next(row for row in bridge["rows"]
                         if any(scope.get("kind") == "extension" for scope in row["lexicalScopes"]))
        module_binding = bridge["modules"][candidate["module"]]
        interface = Path(module_binding["interfacePath"])
        raw_entities = _index_entities(self.root / module_binding["rawOutputPath"])
        entity = _raw_access_entity(candidate, raw_entities)
        _validate_access_entity_claim(candidate, entity)
        with self.assertRaisesRegex(ValueError, "claim differs"):
            _validate_access_entity_claim(dict(candidate, effectiveAccess="internal"), entity)
        with self.assertRaisesRegex(ValueError, "cardinality is 2"):
            _raw_access_entity(candidate, [entity, dict(entity)])
        _validate_access_scope(candidate, interface)
        wrong_target = json.loads(json.dumps(candidate))
        extension = next(scope for scope in wrong_target["lexicalScopes"] if scope["kind"] == "extension")
        extension["resolvedQualifiedName"] = "WrongOwner"
        with self.assertRaisesRegex(ValueError, "independently reparsed source scopes"):
            _validate_access_scope(wrong_target, interface)
        wrong_range = copy.deepcopy(candidate)
        wrong_extension = next(scope for scope in wrong_range["lexicalScopes"] if scope["kind"] == "extension")
        wrong_extension["endLine"] += 1
        with self.assertRaisesRegex(ValueError, "independently reparsed source scopes"):
            _validate_access_scope(wrong_range, interface)
        wrong_owner = copy.deepcopy(candidate)
        wrong_extension = next(scope for scope in wrong_owner["lexicalScopes"] if scope["kind"] == "extension")
        if wrong_extension.get("resolvedOwnerChain"):
            wrong_extension["resolvedOwnerChain"][-1]["qualifiedName"] += ".SameBasename"
            with self.assertRaisesRegex(ValueError, "independently reparsed source scopes"):
                _validate_access_scope(wrong_owner, interface)

    def test_access_bridge_live_tool_binary_hashes_are_rechecked(self) -> None:
        bridge = json.loads((self.root / "factory/catalogue/access-inheritance-spike/derived-access-bridge.json")
                            .read_text(encoding="utf-8"))
        _validate_live_tool_bindings(bridge["bindings"])
        altered = copy.deepcopy(bridge["bindings"]["sourcekitLsp"])
        altered["sha256"] = "sha256:" + "0" * 64
        bad_bindings = copy.deepcopy(bridge["bindings"])
        bad_bindings["sourcekitLsp"] = altered
        with self.assertRaisesRegex(ValueError, "live sourcekitLsp binary differs"):
            _validate_live_tool_bindings(bad_bindings)


if __name__ == "__main__":
    unittest.main()
