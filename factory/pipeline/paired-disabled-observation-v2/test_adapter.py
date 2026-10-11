from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import unittest
from pathlib import Path
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("paired_disabled_v2", HERE / "adapter.py")
adapter = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(adapter)


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def fixture():
    manifest_bytes, payloads = adapter.load_pinned_inputs()
    return json.loads(manifest_bytes), payloads


def replace_json(payloads, path, edit):
    data = json.loads(payloads[path].decode("utf-8-sig"))
    edit(data)
    payloads[path] = json.dumps(data, sort_keys=True, separators=(",", ":")).encode()


def rebuild_manifest(manifest, payloads):
    for row in manifest["inputs"]:
        raw = payloads[row["path"]]
        row["bytes"] = len(raw)
        row["sha256"] = sha(raw)
    raw = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    return raw


class PairedDisabledObservationV2Tests(unittest.TestCase):
    def test_report_keeps_three_batch_channels_separate(self):
        manifest_bytes, payloads = adapter.load_pinned_inputs()
        report = adapter.build_report(manifest_bytes, payloads)
        self.assertEqual(report["batches"]["macOSAXEnabled"]["runs"], 20)
        self.assertEqual(report["batches"]["macOSPaint"]["runs"], 20)
        self.assertEqual(report["batches"]["windowsUIA"]["runs"], 20)
        self.assertEqual(report["semanticComparison"]["macOSValueCounts"], {"true": 20, "false": 0})
        self.assertEqual(report["semanticComparison"]["windowsValueCounts"], {"true": 20, "false": 0})
        self.assertEqual(report["qualification"]["acceptedGoldenCount"], 0)
        self.assertEqual(report["qualification"]["nativeParity"], "held")
        self.assertEqual(len(report["rawInputManifest"]["inputs"]), 1131)

    def test_rejects_truncated_manifest(self):
        manifest_bytes, payloads = adapter.load_pinned_inputs()
        with self.assertRaises(adapter.ObservationError):
            adapter.build_report(manifest_bytes[:-1], payloads)

    def test_rejects_mac_boolean_mutation_even_with_rehashed_source_manifest(self):
        manifest, payloads = fixture()
        path = f"{adapter.MAC_AX_ROOT}/run-001/external-ax.raw.json"
        def edit(raw):
            button = adapter._unique_continue(raw, "role", "label")
            button["enabledAttribute"]["value"] = "true"
        replace_json(payloads, path, edit)
        mb = rebuild_manifest(manifest, payloads)
        with patch.object(adapter, "MANIFEST_SHA256", sha(mb)):
            with self.assertRaises(adapter.ObservationError):
                adapter.build_report(mb, payloads)

    def test_rejects_windows_non_boolean_enabled_mutation(self):
        manifest, payloads = fixture()
        path = f"{adapter.WIN_ROOT}/disabled-repeatability-r1-01/native-01/native.uia.json"
        def edit(uia):
            button = [n for n in adapter._walk(uia) if n.get("controlType") == "ControlType.Button" and n.get("name") == "Continue"][0]
            button["enabled"] = 1
        replace_json(payloads, path, edit)
        mb = rebuild_manifest(manifest, payloads)
        with patch.object(adapter, "MANIFEST_SHA256", sha(mb)):
            with self.assertRaises(adapter.ObservationError):
                adapter.build_report(mb, payloads)

    def test_rejects_wrong_accessibility_role_without_alias_guessing(self):
        manifest, payloads = fixture()
        path = f"{adapter.MAC_AX_ROOT}/run-001/external-ax.raw.json"
        def edit(raw):
            adapter._unique_continue(raw, "role", "label")["role"] = "AXControl"
        replace_json(payloads, path, edit)
        mb = rebuild_manifest(manifest, payloads)
        with patch.object(adapter, "MANIFEST_SHA256", sha(mb)):
            with self.assertRaises(adapter.ObservationError):
                adapter.build_report(mb, payloads)

    def test_rejects_windows_button_missing_or_duplicate(self):
        manifest, payloads = fixture()
        path = f"{adapter.WIN_ROOT}/disabled-repeatability-r1-01/native-01/native.uia.json"
        def edit(uia):
            uia["children"].append(copy.deepcopy(uia["children"][0]))
        replace_json(payloads, path, edit)
        mb = rebuild_manifest(manifest, payloads)
        with patch.object(adapter, "MANIFEST_SHA256", sha(mb)):
            with self.assertRaises(adapter.ObservationError):
                adapter.build_report(mb, payloads)


    def test_rejects_printwindow_repeat_mismatch(self):
        manifest, payloads = fixture()
        path = f"{adapter.WIN_ROOT}/disabled-repeatability-r1-01/native-01/native.printwindow.repeat.png"
        payloads[path] = payloads[path] + b"fault"
        mb = rebuild_manifest(manifest, payloads)
        with patch.object(adapter, "MANIFEST_SHA256", sha(mb)):
            with self.assertRaises(adapter.ObservationError):
                adapter.build_report(mb, payloads)

    def test_rejects_windows_analysis_row_misbound_to_raw_native_receipt(self):
        manifest, payloads = fixture()
        path = "factory/native/windows/disabled-repeatability-batch-v1/analysis.json"
        def edit(analysis):
            analysis["rows"][0]["nativeObservationSha256"] = "0" * 64
        replace_json(payloads, path, edit)
        mb = rebuild_manifest(manifest, payloads)
        with patch.object(adapter, "MANIFEST_SHA256", sha(mb)):
            with self.assertRaises(adapter.ObservationError):
                adapter.build_report(mb, payloads)


if __name__ == "__main__":
    unittest.main()
