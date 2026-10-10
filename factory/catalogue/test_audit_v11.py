from __future__ import annotations

import copy
import json
import tempfile
import unittest
from pathlib import Path

from factory.core import artifacts
from .audit_v11 import (
    DUPE_CANDIDATE_SHA256,
    V10_AUDIT_HASH,
    V10_FILE_SHA256,
    _duplicate_guard,
    _load_v10,
    _validate_duplicate_rows,
    build_audit_v11,
)


class AuditV11Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(__file__).resolve().parents[2]
        cls.v10_path = cls.root / "factory/catalogue/evidence/interface-audit-v10-candidate.json"
        cls.v10 = _load_v10(cls.v10_path, root=cls.root)
        cls.duplicate = _validate_duplicate_rows(cls.v10, root=cls.root)
        cls.candidate = build_audit_v11(cls.v10_path, root=cls.root)

    def test_v11_promotes_only_five_exact_duplicate_pairs_and_keeps_inactive_row_held(self) -> None:
        candidate = self.candidate
        self.assertEqual(candidate["parentAudit"]["auditHash"], V10_AUDIT_HASH)
        self.assertEqual(candidate["parentAudit"]["fileSha256"], V10_FILE_SHA256)
        self.assertEqual(candidate["summary"]["exactSourceKitUsrLinks"], 2548)
        self.assertEqual(candidate["summary"]["heldSourceKitRows"], 1)
        self.assertEqual(candidate["summary"]["sourceKitUsrPresentInSymbolGraph"], 140)
        self.assertEqual(candidate["summary"]["sourceKitUsrAbsentFromSymbolGraph"], 2408)
        self.assertEqual(candidate["summary"]["remainingActiveUnmappedAmbiguousOrUnexplained"], 1)
        self.assertEqual(candidate["summary"]["byClassification"]["ambiguous-context-signature"], 1)
        self.assertNotIn("active-compiler-conditional-unmapped", candidate["summary"]["byClassification"])
        self.assertEqual(candidate["duplicateIdentityBridgeEvidence"]["promotedRows"], 5)
        self.assertEqual(candidate["duplicateIdentityBridgeEvidence"]["faultControls"], 120)
        self.assertEqual(candidate["freshCompilerProbe"]["branch"], "selected=active")
        self.assertEqual(candidate["freshCompilerProbe"]["demangledUsrCount"], 5)
        unresolved_v10 = next(row for row in self.v10["declarations"] if row["line"] == 28491
                              and row["module"] == "SwiftUI")
        unresolved_v11 = next(row for row in candidate["declarations"] if row["line"] == 28491
                              and row["module"] == "SwiftUI")
        self.assertEqual(unresolved_v11, unresolved_v10)
        self.assertEqual(candidate["status"], "incomplete-v11-duplicate-identities-validated-inactive-branch-pending")
        body = dict(candidate)
        declared = body.pop("auditHash")
        self.assertEqual(declared, artifacts.canonical_hash(body))

    def test_production_duplicate_guard_rejects_semantic_mutations(self) -> None:
        guard = _duplicate_guard()
        baseline = self.duplicate["promotions"][0]["validationArgs"]
        self.assertTrue(guard.validate_duplicate_identity(**copy.deepcopy(baseline))["accepted"])
        mutations = [
            ("raw usr", "raw_entities", "usr", "s:7SwiftUI999ForgedV", "semantic-usr"),
            ("raw access", "raw_entities", "effective_access", "source.decl.effective_access.internal", "semantic-effective_access"),
            ("raw kind", "raw_entities", "kind", "source.lang.swift.decl.class", "semantic-kind"),
            ("implicit", "raw_entities", "is_implicit", True, "semantic-is_implicit"),
            # The context is part of the frozen exact-row identity and source
            # scope join, so this mutation is rejected before entity context.
            ("row context", "row", "context", ["ForgedOwner"], "exact-row"),
            ("branch", "row", "activeBranch", False, "source-branch"),
            ("scope", "row", "scopeName", "WrongOwner", "source-scope"),
        ]
        for label, key, field, value, expected in mutations:
            changed = copy.deepcopy(baseline)
            target = changed[key]
            if key == "raw_entities":
                for item in target:
                    item[field] = value
            else:
                target[field] = value
            result = guard.validate_duplicate_identity(**changed)
            with self.subTest(label=label):
                self.assertFalse(result["accepted"])
                self.assertIn(expected, result["reasons"])

        changed = copy.deepcopy(baseline)
        changed["raw_records"][1]["text"] += "\n"
        changed["raw_records"][1]["sha256"] = guard.digest_bytes(changed["raw_records"][1]["text"].encode())
        result = guard.validate_duplicate_identity(**changed)
        self.assertFalse(result["accepted"])
        self.assertIn("distinct-records", result["reasons"])

    def test_duplicate_candidate_and_v10_snapshot_mutations_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            bad_candidate = Path(directory) / "duplicate.json"
            source = self.root / "factory/catalogue/duplicate-identity-spike/exact-identity-candidate.json"
            bad_candidate.write_text(source.read_text(encoding="utf-8") + "\n", encoding="utf-8")
            self.assertNotEqual(artifacts.file_hash(bad_candidate), DUPE_CANDIDATE_SHA256)
            bad_v10 = json.loads(self.v10_path.read_text(encoding="utf-8"))
            bad_v10["summary"]["exactSourceKitUsrLinks"] += 1
            altered_v10 = Path(directory) / "v10.json"
            altered_v10.write_text(json.dumps(bad_v10), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "v10 candidate bytes"):
                _load_v10(altered_v10, root=self.root)


if __name__ == "__main__":
    unittest.main()
