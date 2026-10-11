from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
spec = importlib.util.spec_from_file_location("paired_next_v1", HERE / "adapter.py")
adapter = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(adapter)


def read_json(path: str):
    return json.loads((ROOT / path).read_text(encoding="utf-8-sig"))


def raw(path: str) -> bytes:
    return (ROOT / path).read_bytes()


def mac_paths(block: str):
    case = {
        "swiftui.padding-frame": "8805e6d0729b052d",
        "swiftui.preference-key": "66b6b44aaff817d6",
        "swiftui.scroll-view": "6716afb4fb55269b",
    }[block]
    base = f"factory/native/macos/evidence/20261010-primary-next-five/swiftui.{block.removeprefix('swiftui.')}.recipe_case_{case}"
    if block == "swiftui.preference-key":
        base = f"factory/native/macos/evidence/20261010-corrected-primary/swiftui.preference-key.recipe_case_{case}"
    return base


def win_paths(block: str):
    if block == "swiftui.scroll-view":
        root = "factory/native/windows/round1-native-v4/single-scroll-r1"
    else:
        root = f"factory/native/windows/round1-native-v3/single-{block.removeprefix('swiftui.')}-r1"
    return root + "/replays/run-001"


def one_mac_run(block: str):
    base = mac_paths(block)
    summary = read_json(base + "/summary.json")
    run_summary = next(x for x in summary["runs"] if x["run"] == 1)
    ax_path = base + "/run-001/external-ax.raw.json"
    cap_path = base + "/run-001/capture.json"
    return adapter.mac_run_observation(
        block=block, summary=summary, run_summary=run_summary,
        raw_ax=read_json(ax_path), raw_ax_bytes=raw(ax_path),
        capture=read_json(cap_path), capture_bytes=raw(cap_path),
        clock=read_json(base + "/run-001/clock.json"))


def one_windows_observation(block: str):
    base = win_paths(block)
    return adapter.windows_paint_observation(
        block=block,
        plan=read_json(base + "/plan.json"),
        native=read_json(base + "/native-observation.json"),
        observation=read_json(base + "/observation.json"),
        uia=read_json(base + "/native-01/native.uia.json"),
        pixels=read_json(base + "/native-01/native.pixels.json"),
        printwindow=raw(base + "/native-01/native.printwindow.png"),
        printwindow_repeat=raw(base + "/native-01/native.printwindow.repeat.png"),
        screen=raw(base + "/native-01/native.screen.png"),
        screen_repeat=raw(base + "/native-01/native.screen.repeat.png"))


class PairedNextObservationTests(unittest.TestCase):
    def test_complete_pinned_report_is_one_windows_vs_twenty_mac_observations(self):
        manifest_bytes, payloads = adapter.load_pinned_inputs(ROOT)
        report = adapter.build_report(manifest_bytes, payloads)
        self.assertEqual(report["status"], "source-bound-observation-only")
        self.assertEqual(report["caseCount"], 3)
        self.assertEqual(report["denominators"], {"MacRunsPerCase": 20, "WindowsRunsPerCase": 1})
        self.assertEqual(report["qualification"]["acceptedGoldenCount"], 0)
        self.assertEqual(report["qualification"]["nativeParity"], "held")
        self.assertEqual(report["qualification"]["hitTesting"], "not-attempted")
        for case in report["cases"].values():
            self.assertEqual(case["macOS"]["runs"], 20)
            self.assertEqual(case["windows"]["runs"], 1)
            self.assertEqual(len(case["accessibilityComparisons"]), 20)
            self.assertTrue(all(c["exactSequenceMatch"] for c in case["accessibilityComparisons"]))
            self.assertEqual(case["windows"]["observation"]["qualification"]["nativeParity"], "held")

    def test_report_rejects_changed_raw_source_even_with_same_payload_set(self):
        manifest_bytes, payloads = adapter.load_pinned_inputs(ROOT)
        altered = dict(payloads)
        target = next(path for path in altered if path.endswith("/run-001/external-ax.raw.json"))
        altered[target] += b" "
        with self.assertRaises(adapter.ObservationError):
            adapter.build_report(manifest_bytes, altered)

    def test_report_rejects_changed_or_missing_manifest_identity(self):
        manifest_bytes, payloads = adapter.load_pinned_inputs(ROOT)
        with self.assertRaises(adapter.ObservationError):
            adapter.build_report(manifest_bytes + b" ", payloads)
        missing = dict(payloads)
        missing.pop(next(iter(missing)))
        with self.assertRaises(adapter.ObservationError):
            adapter.build_report(manifest_bytes, missing)

    def test_three_primary_cases_exactly_join_mac_and_windows_source_case(self):
        expected_labels = {
            "swiftui.padding-frame": ["Box"],
            "swiftui.preference-key": ["0", "1", "2"],
            "swiftui.scroll-view": ["Row 0", "Row 1", "Row 2", "Row 3"],
        }
        for block, labels in expected_labels.items():
            with self.subTest(block=block):
                mac = one_mac_run(block)
                win = one_windows_observation(block)
                win_labels = [row["value"] for row in win["uia"]]
                self.assertEqual([row["value"] for row in mac["labels"]], labels)
                self.assertEqual(win_labels, labels)
                compared = adapter.compare_accessibility(mac["labels"], win["uia"])
                self.assertTrue(compared["exactSequenceMatch"])
                self.assertEqual(compared["qualification"], "not-claimed")
                self.assertEqual(win["qualification"]["nativeParity"], "held")
                self.assertEqual(win["printWindow"]["sameProviderRepeatExact"], True)

    def test_padding_and_preference_are_not_joined_by_block_name_alone(self):
        for block, other in (("swiftui.padding-frame", "swiftui.preference-key"),
                             ("swiftui.preference-key", "swiftui.scroll-view")):
            expected = adapter.CASES[block]
            wrong = adapter.CASES[other]
            with self.assertRaises(adapter.ObservationError):
                adapter.validate_identity(block, case_id=wrong["caseId"],
                                          case_sha256=wrong["caseSha256"],
                                          source_sha256=wrong["sourceSha256"])

    def test_mac_raw_owner_window_and_source_are_required(self):
        block = "swiftui.padding-frame"
        base = mac_paths(block)
        summary = read_json(base + "/summary.json")
        run = next(x for x in summary["runs"] if x["run"] == 1)
        ax_path = base + "/run-001/external-ax.raw.json"
        cap_path = base + "/run-001/capture.json"
        ax = read_json(ax_path)
        ax["windowTitle"] = "Wrong case title"
        with self.assertRaises(adapter.ObservationError):
            adapter.mac_run_observation(block=block, summary=summary, run_summary=run,
                raw_ax=ax, raw_ax_bytes=raw(ax_path), capture=read_json(cap_path),
                capture_bytes=raw(cap_path), clock=read_json(base + "/run-001/clock.json"))

    def test_windows_uia_enabled_is_exact_boolean(self):
        block = "swiftui.padding-frame"
        base = win_paths(block)
        uia = read_json(base + "/native-01/native.uia.json")
        uia["enabled"] = 1
        with self.assertRaises(adapter.ObservationError):
            adapter.windows_paint_observation(block=block, plan=read_json(base + "/plan.json"),
                native=read_json(base + "/native-observation.json"),
                observation=read_json(base + "/observation.json"), uia=uia,
                pixels=read_json(base + "/native-01/native.pixels.json"),
                printwindow=raw(base + "/native-01/native.printwindow.png"),
                printwindow_repeat=raw(base + "/native-01/native.printwindow.repeat.png"),
                screen=raw(base + "/native-01/native.screen.png"),
                screen_repeat=raw(base + "/native-01/native.screen.repeat.png"))

    def test_windows_printwindow_bytes_must_match_raw_pixel_receipt(self):
        block = "swiftui.preference-key"
        base = win_paths(block)
        args = dict(block=block, plan=read_json(base + "/plan.json"),
                    native=read_json(base + "/native-observation.json"),
                    observation=read_json(base + "/observation.json"),
                    uia=read_json(base + "/native-01/native.uia.json"),
                    pixels=read_json(base + "/native-01/native.pixels.json"),
                    printwindow=raw(base + "/native-01/native.printwindow.png") + b"changed",
                    printwindow_repeat=raw(base + "/native-01/native.printwindow.repeat.png"),
                    screen=raw(base + "/native-01/native.screen.png"),
                    screen_repeat=raw(base + "/native-01/native.screen.repeat.png"))
        with self.assertRaises(adapter.ObservationError):
            adapter.windows_paint_observation(**args)

    def test_unmapped_role_fails_closed_and_label_difference_stays_observation(self):
        with self.assertRaises(adapter.ObservationError):
            adapter.compare_accessibility([{"role": "AXGroup", "value": "X"}],
                                          [{"role": "ControlType.Text", "value": "X"}])
        result = adapter.compare_accessibility([{"role": "AXStaticText", "value": "A"}],
                                               [{"role": "ControlType.Text", "value": "B"}])
        self.assertFalse(result["exactSequenceMatch"])
        self.assertEqual(result["interpretation"], "observed-difference")
        self.assertEqual(result["qualification"], "not-claimed")

    def test_timing_keeps_clock_domains_separate_and_rejects_boolean_ns(self):
        out = adapter.retain_raw_timing(
            mac_clock={"clockId": "macos.dispatch.uptime", "startNs": 1, "endNs": 9},
            windows_observation={"startedAt": "raw-start", "finishedAt": "raw-finish"})
        self.assertEqual(out["macElapsedNsWithinClock"], 8)
        self.assertEqual(out["crossPlatformTimingComparison"], "unavailable-different-clock-scopes")
        with self.assertRaises(adapter.ObservationError):
            adapter.retain_raw_timing(mac_clock={"clockId": "macos.dispatch.uptime", "startNs": True, "endNs": 9},
                                      windows_observation={})


if __name__ == "__main__":
    unittest.main()
