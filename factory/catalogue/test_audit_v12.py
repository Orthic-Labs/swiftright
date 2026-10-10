from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from factory.core import artifacts
from . import audit_v12


class AuditV12Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(__file__).resolve().parents[2]
        cls.candidate = audit_v12.build_audit_v12(root=cls.root)
        cls.v11 = audit_v12._load_v11(cls.root)
        cls.guard = audit_v12._load_inactive_guard(str(cls.root))
        cls.validator = cls.guard.Validator()

    def test_single_inactive_exclusion_preserves_all_exact_links_and_other_rows(self) -> None:
        candidate = self.candidate
        summary = candidate["summary"]
        self.assertEqual(candidate["parentAudit"]["auditHash"], audit_v12.V11_AUDIT_HASH)
        self.assertEqual(summary["exactSourceKitUsrLinks"], 2548)
        self.assertEqual(summary["heldSourceKitRows"], 0)
        self.assertEqual(summary["inactiveExcludedInterfaceRows"], 1)
        self.assertEqual(summary["remainingActiveUnmappedAmbiguousOrUnexplained"], 0)
        self.assertEqual(summary["sourceKitUsrPresentInSymbolGraph"], 140)
        self.assertEqual(summary["sourceKitUsrAbsentFromSymbolGraph"], 2408)
        self.assertEqual(candidate["inactiveCompilerExclusionEvidence"]["exactLinksAdded"], 0)
        self.assertEqual(candidate["inactiveCompilerExclusionEvidence"]["exclusions"], 1)
        self.assertIn("public-ancestor-eligibility-and-global-interface-completeness",
                      candidate["pendingEvidence"][0]["kind"])
        self.assertEqual(candidate["status"],
                         "incomplete-v12-one-inactive-branch-excluded-public-ancestor-eligibility-unproven")

        old_by_key = {(row.get("module"), row.get("interface"), row.get("line"), row.get("name")): row
                      for row in self.v11["declarations"]}
        new_by_key = {(row.get("module"), row.get("interface"), row.get("line"), row.get("name")): row
                      for row in candidate["declarations"]}
        self.assertEqual(old_by_key.keys(), new_by_key.keys())
        target = tuple(audit_v12.INACTIVE_KEY)
        self.assertEqual(len(old_by_key), 12635)
        self.assertEqual(len([key for key in old_by_key if key != target and old_by_key[key] != new_by_key[key]]), 0)
        old = old_by_key[target]
        new = new_by_key[target]
        self.assertEqual(old["classification"], "ambiguous-context-signature")
        self.assertEqual(new["classification"], "inactive-compiler-conditional")
        self.assertNotIn("symbol", new)
        self.assertEqual(new["inactiveCompilerEvidence"]["graphCandidateStatus"], "remains-ambiguous-not-linked")

        body = dict(candidate)
        declared = body.pop("auditHash")
        self.assertEqual(declared, artifacts.canonical_hash(body))

    def test_inactive_production_validator_rejects_source_raw_and_probe_faults(self) -> None:
        baseline = dict(self.validator.inputs)
        self.assertEqual(self.validator.validate(), json.loads(
            (self.root / audit_v12.INACTIVE_DIR / "inactive-branch-evidence.json").read_text()
        )["resolution"])
        faults = [
            ("inactive source signature", "source", baseline["source"].replace("any SwiftUI.Widget)", "some SwiftUI.Widget)", 1)),
            ("sourcekit member access", "index", baseline["index"].replace("source.decl.effective_access.public", "source.decl.effective_access.private", 1)),
            ("compiler selected branch", "processResults", baseline["processResults"].replace("selected=InlineAlways", "selected=else", 1)),
            ("demangle owner", "trees", baseline["trees"].replace('text="WidgetBundleBuilder"', 'text="WrongOwner"', 1)),
            ("inactive cursor request", "cursorRequest", baseline["cursorRequest"].replace("1605000", "1605001", 1)),
        ]
        for label, key, changed in faults:
            altered = dict(baseline)
            altered[key] = changed
            with self.subTest(label=label):
                self.assertNotEqual(changed, baseline[key])
                with self.assertRaises(ValueError):
                    self.validator.validate(altered)

    def test_parent_and_evidence_pins_fail_closed_on_candidate_mutation(self) -> None:
        evidence_path = self.root / audit_v12.INACTIVE_DIR / "inactive-branch-evidence.json"
        evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
        forged = copy.deepcopy(evidence)
        forged["resolution"]["inactiveRawEntityCount"] = 1
        self.assertNotEqual(artifacts.canonical_hash(forged), artifacts.canonical_hash(evidence))
        with self.assertRaises(ValueError):
            audit_v12._reconstruct_inactive_evidence(forged, self.validator)


if __name__ == "__main__":
    unittest.main()
