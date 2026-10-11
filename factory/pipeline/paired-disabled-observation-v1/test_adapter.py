from __future__ import annotations

import copy
import json
import unittest

from adapter import INPUT_MANIFEST_SHA256, ObservationError, build_report, load_pinned_inputs


class PairedDisabledObservationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest, cls.payloads = load_pinned_inputs()
        cls.report = build_report(cls.manifest, cls.payloads)

    def test_counts_hold_parity_and_promotion(self):
        self.assertEqual(self.report["counts"], {
            "macOSRuns": 20, "windowsObservations": 1, "qualifiedWindowsBatches": 0,
            "parity": "held", "registryOrBaselinePromotion": False,
        })

    def test_button_semantics_distinguish_missing_mac_enabled_field(self):
        semantics = self.report["buttonSemantics"]
        self.assertEqual(semantics["windowsUIA"]["enabled"], True)
        self.assertEqual(semantics["macOSRawAX"]["enabled"], "not exposed in raw AX records")
        self.assertTrue(semantics["labelMatch"])
        self.assertEqual(semantics["hitTesting"]["status"], "untested")

    def test_viewport_and_text_correction_metrics_remain_host_scoped(self):
        metrics = self.report["correctionMetrics"]
        self.assertEqual(metrics["windowsViewport"]["initialAbiMetrics"], {"width": 800, "height": 1396, "scale": 2.5})
        self.assertEqual(metrics["windowsViewport"]["actualOwnedClientPixels"], {"width": 800, "height": 600})
        self.assertEqual(metrics["windowsText"]["measuredWidthPX"], 160.27344)
        self.assertEqual(metrics["windowsText"]["snappedWidthPX"], 160.0)
        self.assertEqual(metrics["windowsText"]["lines"], 1)
        self.assertEqual(metrics["macOSContent"]["rootLayoutPointFrame"], {"width": 79, "height": 24})

    def test_raw_mac_timing_separate_from_qualified_timing(self):
        timing = self.report["timing"]
        self.assertEqual(len(timing["rawMacRenderIntervals"]["runs"]), 20)
        self.assertEqual(timing["rawMacRenderIntervals"]["meaning"], "same-process offscreen render begin/end only; not input latency")
        self.assertEqual(timing["qualifiedTiming"], "unavailable")

    def test_manifest_hash_and_exact_payload_set_are_required(self):
        with self.assertRaises(ObservationError):
            build_report(self.manifest + b" ", self.payloads)
        changed = dict(self.payloads)
        changed.pop(next(k for k in changed if k.endswith("/run-020/capture.json")))
        with self.assertRaises(ObservationError):
            build_report(self.manifest, changed)
        self.assertEqual(len(INPUT_MANIFEST_SHA256), 64)

    def test_case_source_or_windows_uia_mutation_is_rejected(self):
        changed = dict(self.payloads)
        case_source = next(k for k in changed if k.endswith("swiftui.disabled.recipe_case_f113195a59446fc4.swift"))
        changed[case_source] = changed[case_source].replace(b"Button", b"Group", 1)
        with self.assertRaises(ObservationError):
            build_report(self.manifest, changed)
        changed = dict(self.payloads)
        uia = next(k for k in changed if k.endswith("native-01/native.uia.json"))
        changed[uia] = changed[uia].replace(b'"enabled":  true', b'"enabled":  false', 1)
        with self.assertRaises(ObservationError):
            build_report(self.manifest, changed)

    def test_report_lists_raw_evidence_hashes_and_preserves_single_windows_observation(self):
        evidence = self.report["evidence"]["rawFiles"]
        self.assertEqual(len(evidence), 78)
        self.assertTrue(all(len(row["sha256"]) == 64 and row["path"] for row in evidence))
        self.assertEqual(self.report["nativeObservation"]["count"], 1)
        self.assertFalse(self.report["nativeObservation"]["occlusionQualified"])
        self.assertFalse(self.report["nativeObservation"]["providerReadbackExport"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
