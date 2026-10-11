from __future__ import annotations

import copy
import json
from pathlib import Path
import unittest

from capture import CaptureValidationError, EVIDENCE, validate_raw_observation


class DisabledEnabledAXObservationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.report = json.loads((EVIDENCE / "report.json").read_text())
        cls.raw_rows = []
        for index in range(1, 21):
            run_root = EVIDENCE / f"run-{index:03d}"
            cls.raw_rows.append((
                json.loads((run_root / "external-ax.raw.json").read_text()),
                json.loads((run_root / "owner-process.json").read_text()),
            ))

    def test_no_prompt_preflight_and_exact_case_provenance(self):
        self.assertTrue(self.report["preflight"]["axTrusted"])
        self.assertIs(self.report["preflight"]["permissionRequests"], False)
        self.assertEqual(self.report["caseId"], "swiftui.disabled.recipe/case/f113195a59446fc4")
        self.assertEqual(self.report["sourceSha256"], "68eed62f6ef06ecec579a0e36cdc44a612a559a8329fe6dbd91a700c5d90c005")
        self.assertEqual(self.report["existingCaptureHostSha256"], "d555759e14425b5c38751935ed54bc18836bbbd8703362f85e33661e99d0c7d6")
        client_source = Path(__file__).with_name("AXEnabledClient.swift").read_text()
        self.assertIn("AXIsProcessTrusted()", client_source)
        self.assertNotIn("AXIsProcessTrustedWithOptions", client_source)
        self.assertNotIn("kAXTrustedCheckOptionPrompt", client_source)
        self.assertEqual(len(self.report["priorRunOwnerReceipts"]), 20)

    def test_twenty_distinct_process_observations_return_axenabled_true(self):
        self.assertEqual(self.report["newObservationCount"], 20)
        self.assertEqual(self.report["observedEnabledTrueCount"], 20)
        self.assertEqual(len({row[1]["pid"] for row in self.raw_rows}), 20)
        for raw, owner in self.raw_rows:
            selected = validate_raw_observation(raw, owner)
            self.assertEqual(selected["enabledAttribute"], {
                "attribute": "AXEnabled", "axError": 0, "status": "observed-bool", "value": True,
            })

    def test_controls_reject_owner_case_source_and_permission_mutations(self):
        raw, owner = self.raw_rows[0]
        mutations = [
            ("ownerPID", 1),
            ("ownerPath", "/tmp/other"),
            ("ownerBinarySha256", "sha256:" + "0" * 64),
            ("ownerStartedAt", "different-start"),
            ("caseSha256", "sha256:" + "0" * 64),
            ("sourceSha256", "sha256:" + "0" * 64),
            ("permissionRequests", True),
        ]
        for key, value in mutations:
            changed = copy.deepcopy(raw)
            changed[key] = value
            with self.subTest(key=key), self.assertRaises(CaptureValidationError):
                validate_raw_observation(changed, owner)

    def test_controls_reject_absent_false_string_and_duplicate_axenabled(self):
        raw, owner = self.raw_rows[0]
        for field_value in (None, {"attribute": "AXEnabled", "axError": 0, "status": "observed-bool", "value": False},
                            {"attribute": "AXEnabled", "axError": 0, "status": "observed-bool", "value": "true"}):
            changed = copy.deepcopy(raw)
            button = next(node for node in _walk(changed) if node.get("role") == "AXButton" and node.get("label") == "Continue")
            if field_value is None:
                del button["enabledAttribute"]
            else:
                button["enabledAttribute"] = field_value
            with self.subTest(field_value=field_value), self.assertRaises(CaptureValidationError):
                validate_raw_observation(changed, owner)
        duplicated = copy.deepcopy(raw)
        original_button = next(node for node in _walk(duplicated) if node.get("role") == "AXButton" and node.get("label") == "Continue")
        duplicated["steps"][0]["tree"]["children"].append(copy.deepcopy(original_button))
        with self.assertRaises(CaptureValidationError):
            validate_raw_observation(duplicated, owner)

    def test_capture_is_ax_only_and_does_not_claim_hit_testing(self):
        self.assertIs(self.report["noInputInvoked"], True)
        self.assertIs(self.report["permissionRequests"], False)
        for raw, _ in self.raw_rows:
            self.assertNotIn("inputEvents", raw)
            self.assertNotIn("callbackReceipt", raw)


def _walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from _walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from _walk(value)


if __name__ == "__main__":
    unittest.main(verbosity=2)
