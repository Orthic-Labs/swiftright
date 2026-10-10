from __future__ import annotations

import copy
import unittest

from factory.comparison import ComparisonError, compare_case
from factory.core.artifacts import canonical_hash, provenance


TUPLE = {
    "id": "test.tuple", "sdk": "sdk", "macosBuild": "build",
    "toolchains": {"swift": "swift"}, "runtimeCommit": "1234567",
    "rendererHash": "sha256:" + "1" * 64,
    "hostHashes": {"macos": "sha256:" + "2" * 64, "windows": "sha256:" + "3" * 64},
    "factoryVersion": "0.1", "acceptanceConfigHash": "sha256:" + "0" * 64,
}


def artifacts():
    config = {
        "reviewedBounds": {"id": "review.bounds", "hash": "sha256:" + "a" * 64},
        "sr0Closed": {"id": "review.sr0", "hash": "sha256:" + "b" * 64},
        "paintQualification": {"id": "review.paint", "hash": "sha256:" + "c" * 64},
        "normalizers": {},
        "timing": {
            "reviewed": True, "faultControlsPassed": True,
            "reviewEvidence": {"id": "review.timing", "hash": "sha256:" + "d" * 64},
            "faultControlEvidence": {"id": "control.timing", "hash": "sha256:" + "e" * 64},
            "durationNs": {"startKind": "start", "endKind": "end", "min": 90, "max": 110},
            "velocityMilliPerSecond": {"min": 0, "max": 200_000_000_000},
            "presentedFrameStallNs": {"frameIntervalNs": 10, "min": 0, "max": 10},
        },
    }
    case = {
        "kind": "case", "version": "0.1", "id": "test.case",
        "provenance": provenance({"source": "unit"}),
        "recipe": {"id": "test.recipe", "hash": "sha256:" + "4" * 64},
        "block": "test.block", "inputs": {}, "expectedCaseSetHash": "sha256:" + "5" * 64,
        "coverage": "declared", "tuple": {**TUPLE, "acceptanceConfigHash": canonical_hash(config)},
    }
    captures = []
    for platform in ("macos", "windows"):
        capture = {
            "kind": "capture", "version": "0.1", "id": f"test.{platform}.run-1",
            "provenance": provenance({"capture": platform}),
            "case": {"id": case["id"], "hash": canonical_hash(case)}, "platform": platform,
            "tuple": case["tuple"],
            "meta": {"run": 1, "host": {"id": f"test.host.{platform}", "hash": case["tuple"]["hostHashes"][platform]},
                     "conditions": {}, "clock": {"clockId": f"{platform}.clock", "correlationHash": "sha256:" + "6" * 64}},
            "layout": [{"probeTag": "root", "viewIdentity": "root", "frame": {"x": 0, "y": 0, "width": 10, "height": 10}}],
            "ax": [], "events": [
                {"id": "event.start", "kind": "start", "timeNs": 0, "clockId": f"{platform}.clock"},
                {"id": "event.end", "kind": "end", "timeNs": 100, "clockId": f"{platform}.clock"},
            ],
            "anim": [{"id": "anim.primary", "stimulusTimeNs": 0, "transactionTimeNs": 1,
                      "samples": [{"timeNs": 0, "value": 0}, {"timeNs": 10, "value": 1}],
                      "presentedFrames": [{"timeNs": 0, "imageHash": "sha256:" + "7" * 64},
                                          {"timeNs": 10, "imageHash": "sha256:" + "8" * 64}]}],
            "images": [], "text": [],
        }
        captures.append(capture)
    return case, captures, config


class CompareCaseTests(unittest.TestCase):
    def test_candidate_with_one_run_per_side_stays_blocked_and_reports_refs(self):
        case, captures, config = artifacts()
        verdict = compare_case(case, captures, config)
        self.assertEqual(verdict["status"], "blocked")
        self.assertEqual(verdict["repeatability"]["mac"]["runs"], 1)
        self.assertEqual(len(verdict["macCaptures"]), 1)
        self.assertEqual(verdict["timing"]["rawEvidence"], verdict["macCaptures"] + verdict["windowsCaptures"])

    def test_semantic_mutation_rejected(self):
        case, captures, config = artifacts()
        changed = copy.deepcopy(captures)
        changed[1]["layout"][0]["frame"]["width"] = 11
        verdict = compare_case(case, changed, config)
        self.assertEqual(next(row for row in verdict["semantic"]["results"] if row["channel"] == "layout")["status"], "fail")
        self.assertEqual(verdict["status"], "fail")

    def test_timing_stall_exceeds_bound(self):
        case, captures, config = artifacts()
        captures[0]["anim"][0]["presentedFrames"][1]["timeNs"] = 40
        verdict = compare_case(case, captures, config)
        self.assertEqual(verdict["timing"]["status"], "fail")

    def test_missing_windows_cannot_pass(self):
        case, captures, config = artifacts()
        verdict = compare_case(case, captures[:1], config)
        self.assertEqual(verdict["status"], "blocked")
        self.assertTrue(all(row["status"] != "pass" for row in verdict["semantic"]["results"]))

    def test_wrong_case_binding_is_rejected(self):
        case, captures, config = artifacts()
        captures[0]["case"]["hash"] = "sha256:" + "9" * 64
        with self.assertRaises(ComparisonError):
            compare_case(case, captures, config)

    def test_sampling_timestamps_do_not_change_repeatability(self):
        case, captures, config = artifacts()
        second = copy.deepcopy(captures[0])
        second["id"] = "test.macos.run-2"
        second["meta"]["run"] = 2
        second["events"][0]["timeNs"] = 1234
        second["events"][1]["timeNs"] = 1334
        second["anim"][0]["stimulusTimeNs"] = 1234
        second["anim"][0]["transactionTimeNs"] = 1235
        second["anim"][0]["samples"] = [{"timeNs": 1234, "value": 0}, {"timeNs": 1244, "value": 1}]
        second["anim"][0]["presentedFrames"] = [
            {"timeNs": 1234, "imageHash": "sha256:" + "7" * 64},
            {"timeNs": 1244, "imageHash": "sha256:" + "8" * 64},
        ]
        captures.append(second)
        verdict = compare_case(case, captures, config)
        self.assertTrue(verdict["repeatability"]["mac"]["semanticAgreement"])


if __name__ == "__main__":
    unittest.main()
