from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path

if __package__ in {None, ""}:
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from factory.spikes.timing.f8_timing_spike import EvidenceError, compare, deterministic_example, selftest


class F8TimingSpikeTests(unittest.TestCase):
    def test_bounded_sampling_jitter_passes_and_retains_raw_evidence(self) -> None:
        report = compare(deterministic_example())
        self.assertEqual(report["status"], "pass")
        first = report["results"][0]["runs"][0]
        self.assertEqual(first["derived"]["durationUs"], 99_000)
        self.assertIn("presentedFramesUs", first["rawTiming"])

    def test_seeded_adversarial_controls_are_not_accepted(self) -> None:
        report = selftest()
        self.assertEqual(report["status"], "pass")
        self.assertEqual(report["controls"]["bounded-jitter"], "pass")
        for name, outcome in report["controls"].items():
            if name != "bounded-jitter":
                self.assertIn(outcome, {"fail", "rejected"}, name)

    def test_duplicate_case_id_is_rejected(self) -> None:
        document = deterministic_example()
        document["cases"].append(copy.deepcopy(document["cases"][0]))
        with self.assertRaises(EvidenceError):
            compare(document)

    def test_missing_presentation_channel_is_rejected(self) -> None:
        document = deterministic_example()
        del document["cases"][0]["observations"][0]["presentedFramesUs"]
        with self.assertRaises(EvidenceError):
            compare(document)


if __name__ == "__main__":
    unittest.main()
