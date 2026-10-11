from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from mapping_v2 import MappingV2Error, build_candidate, load_inputs


class CurrentSourceBindingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.base, cls.catalogue, cls.manifest, cls.snapshots = load_inputs()
        cls.candidate = build_candidate(cls.base, cls.catalogue, cls.manifest, cls.snapshots)

    def test_exact_current_lines_bind_only_two_direct_reference_rows(self):
        rows = {r["rowKey"]: r for r in self.candidate["rows"]}
        self.assertEqual(set(rows), {"f12-extended-004", "f12-extended-006"})
        self.assertEqual(self.candidate["denominator"], {
            "extendedDemandRows": 107,
            "sourceBoundDirectReferenceRows": 2,
            "registryMappedRows": 0,
        })
        self.assertEqual([u["line"] for u in rows["f12-extended-004"]["currentUsageReferences"]], [30, 31, 34])
        self.assertEqual([u["line"] for u in rows["f12-extended-006"]["currentUsageReferences"]], [53, 16])
        self.assertTrue(all(u["registryBlockIds"] == [] for r in json.loads(self.base)["rows"]
                            if r["rowKey"] in rows for u in r["catalogueIdentityReferences"]))

    def test_old_indent_mismatch_is_explicit_and_not_normalized(self):
        for row in self.candidate["rows"]:
            drift = row["historicalAnchorDrift"]
            self.assertEqual(drift["recordedText"], "private func persist() {")
            self.assertEqual(drift["capturedExactText"], "    private func persist() {")
            self.assertFalse(drift["exactAnchorMatches"])
            self.assertFalse(drift["normalizationApplied"])
            self.assertTrue(drift["recordedSha256MatchesCapturedBytes"])

    def test_current_source_snapshot_bytes_are_fully_pinned(self):
        changed = dict(self.snapshots)
        key = next(k for k in changed if "slice-editor" in k)
        changed[key] = changed[key].replace(b"            List {", b"            Group {")
        with self.assertRaises(MappingV2Error):
            build_candidate(self.base, self.catalogue, self.manifest, changed)

    def test_whitespace_change_is_not_normalized(self):
        changed = dict(self.snapshots)
        key = next(k for k in changed if "slice-editor" in k)
        changed[key] = changed[key].replace(b"            List {", b"           List {", 1)
        manifest = json.loads(self.manifest)
        import hashlib
        for row in manifest["sources"]:
            if row["snapshotPath"] == key:
                row["bytes"] = len(changed[key])
                row["sha256"] = hashlib.sha256(changed[key]).hexdigest()
        manifest_bytes = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
        # Rehashed caller data still fails the independently pinned manifest hash.
        with self.assertRaises(MappingV2Error):
            build_candidate(self.base, self.catalogue, manifest_bytes, changed)

    def test_changed_base_catalogue_or_manifest_rejected(self):
        for args in (
            (self.base + b" ", self.catalogue, self.manifest, self.snapshots),
            (self.base, self.catalogue + b" ", self.manifest, self.snapshots),
            (self.base, self.catalogue, self.manifest + b" ", self.snapshots),
        ):
            with self.assertRaises(MappingV2Error):
                build_candidate(*args)

    def test_missing_snapshot_rejected(self):
        with self.assertRaises(MappingV2Error):
            build_candidate(self.base, self.catalogue, self.manifest, {})

    def test_overloaded_binding_remains_ambiguous_in_v1(self):
        base = json.loads(self.base)
        binding = next(r for r in base["rows"] if r["demand"] == "Binding(get:set:)" )
        self.assertEqual(binding["disposition"], "ambiguous-catalogue-candidates")
        self.assertEqual(len(binding["ambiguousCatalogueCandidates"]), 2)
        self.assertIsNone(binding["registryBlockId"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
