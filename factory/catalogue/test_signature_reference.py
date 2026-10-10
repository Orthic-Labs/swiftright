from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class SignatureReferenceEvidenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.reference = json.loads((ROOT / "factory/catalogue/evidence/sdk-signature-reference.json").read_text())
        cls.catalogue = json.loads((ROOT / "factory/catalogue/evidence/catalogue.json").read_text())
        cls.audit = json.loads((ROOT / "factory/catalogue/evidence/interface-audit-v5.json").read_text())
        cls.usrs = {symbol["usr"] for symbol in cls.catalogue["symbols"]}

    def test_requested_api_groups_have_sdk_graph_candidates(self) -> None:
        expected = {"shapes", "zstack", "overlay", "image-sizing", "font", "line-limit",
                    "layout-geometry", "scroll-view", "frame-padding", "preference-key", "labels-hidden"}
        self.assertEqual(set(self.reference["groups"]), expected)
        self.assertTrue(all(self.reference["groups"][group] for group in expected))

    def test_every_reference_usr_resolves_to_pinned_catalogue(self) -> None:
        for rows in self.reference["groups"].values():
            for row in rows:
                self.assertEqual(row["usr"], row["precise"])
                self.assertIn(row["usr"], self.usrs)
                self.assertTrue(row["graphFiles"])

    def test_reference_hash_covers_evidence_payload(self) -> None:
        from factory.core.artifacts import canonical_hash
        unhashed = dict(self.reference)
        reference_hash = unhashed.pop("referenceHash")
        self.assertEqual(reference_hash, canonical_hash(unhashed))
        self.assertEqual(self.reference["catalogue"]["sha256"], self.reference["provenance"]["inputs"][0]["hash"])

    def test_layout_adapters_retain_geometry_types_and_distinct_alignments(self) -> None:
        rows = self.reference["groups"]["layout-geometry"]
        signatures = ["".join(fragment.get("spelling", "") for fragment in row["declarationFragments"]) for row in rows]
        self.assertTrue(any("-> CGSize" in signature for signature in signatures))
        self.assertTrue(any("bounds: CGRect" in signature for signature in signatures))
        alignments = [signature for signature in signatures if "explicitAlignment" in signature]
        self.assertTrue(any("HorizontalAlignment" in signature for signature in alignments))
        self.assertTrue(any("VerticalAlignment" in signature for signature in alignments))
        self.assertTrue(any("cache: inout Self.Cache" in signature for signature in signatures))

    def test_ambiguous_or_unmapped_interface_rows_stay_labeled(self) -> None:
        self.assertEqual(self.reference["summary"]["auditHash"], self.audit["auditHash"])
        self.assertEqual(self.reference["summary"]["auditStatus"], "incomplete-context-signature-audit")
        candidates = [row for rows in self.reference["groups"].values() for row in rows
                      if row["interfaceCandidateEvidence"]]
        self.assertTrue(any(evidence["classification"] == "ambiguous-context-signature"
                            for row in candidates for evidence in row["interfaceCandidateEvidence"]))
        self.assertNotEqual(self.reference["status"], "complete")


if __name__ == "__main__":
    unittest.main()
