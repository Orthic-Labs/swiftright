import copy
import json
import tempfile
import unittest
from pathlib import Path

from factory.core.artifacts import canonical_hash
from factory.reports import build_report
from factory.reports.report import _case_status


ROOT = Path(__file__).resolve().parents[2]
EXAMPLE = ROOT / "factory/spec/examples/rectangle-v0.1"


def read(name):
    return json.loads((EXAMPLE / name).read_text(encoding="utf-8"))


class ReportTests(unittest.TestCase):
    def test_manifest_case_without_observation_stays_in_denominator(self):
        registry = read("example-block-registry.json")
        case = read("example-case.json")
        with tempfile.TemporaryDirectory() as tmp:
            paths = build_report(registry, [case], [], [], tmp)
            report = Path(paths["blocks"][0]["markdown"]).read_text(encoding="utf-8")
            dashboard = Path(paths["markdown"]).read_text(encoding="utf-8")
        self.assertIn("0 pass / 0 fail / 1 blocked / 0 invalidated / 1 total", report)
        self.assertIn("0 / 0 / 1 / 1", dashboard)
        self.assertIn("No verdict for manifest case", report)

    def test_escaping_and_path_sanitizing(self):
        registry = {"blocks": [{"id": "x/../../<script>", "symbols": [], "inventoryStatus": "inventory", "progress": "recipe", "semanticDependencies": []}]}
        with tempfile.TemporaryDirectory() as tmp:
            paths = build_report(registry, [], [], [], tmp)
            html_doc = Path(paths["blocks"][0]["html"]).read_text(encoding="utf-8")
            self.assertNotIn("<script>", html_doc)
            self.assertIn("&lt;script&gt;", html_doc)
            self.assertTrue(Path(paths["blocks"][0]["markdown"]).resolve().is_relative_to(Path(tmp).resolve()))

    def test_fail_and_blocked_remain_distinct(self):
        registry = read("example-block-registry.json")
        case = read("example-case.json")
        base = read("example-verdict.json")
        blocked = dict(base, status="blocked")
        second_case = dict(case, id="spec-example.rectangle.case-fail")
        failed = dict(base, id="spec-example.rectangle.verdict-fail", case={"id": second_case["id"], "hash": base["case"]["hash"]}, status="fail")
        with tempfile.TemporaryDirectory() as tmp:
            paths = build_report(registry, [case, second_case], [], [blocked, failed], tmp)
            report = Path(paths["blocks"][0]["markdown"]).read_text(encoding="utf-8")
        self.assertIn("1 fail / 1 blocked / 0 invalidated / 2 total", report)
        self.assertIn("| spec-example.rectangle.case | blocked", report)
        self.assertIn("| spec-example.rectangle.case-fail | fail", report)

    def test_pass_verdict_with_synthetic_evidence_is_held(self):
        registry = read("example-block-registry.json")
        case = read("example-case.json")
        mac = read("capture-macos-candidate.json")
        win = read("capture-windows-candidate.json")
        verdict = read("example-verdict.json")
        verdict.update(status="pass", macCaptures=[{"id": mac["id"], "hash": "sha256:" + "a" * 64}], windowsCaptures=[{"id": win["id"], "hash": "sha256:" + "b" * 64}])
        with tempfile.TemporaryDirectory() as tmp:
            paths = build_report(registry, [case], [mac, win], [verdict], tmp)
            report = Path(paths["blocks"][0]["markdown"]).read_text(encoding="utf-8")
        self.assertIn("Synthetic/spec-example evidence cannot establish parity", report)
        self.assertIn("0 pass / 0 fail / 1 blocked", report)

    def test_empty_passing_channel_is_held(self):
        digest = "sha256:" + "a" * 64
        tuple_value = {"id": "pilot.tuple", "sdk": "Swift", "macosBuild": "27.0", "toolchains": {"swift": "6"},
                       "runtimeCommit": "abcdef0", "rendererHash": digest,
                       "hostHashes": {"macos": "sha256:" + "b" * 64, "windows": "sha256:" + "c" * 64},
                       "factoryVersion": "0.1", "acceptanceConfigHash": digest}
        case = {"id": "pilot.case", "block": "pilot.block", "tuple": tuple_value, "provenance": {"producer": "pilot"}}
        registry = {"blocks": [{"id": "pilot.block", "symbols": [], "inventoryStatus": "inventory", "progress": "implementing", "semanticDependencies": []}]}
        case_ref = {"id": case["id"], "hash": canonical_hash(case)}
        def capture_rows(platform):
            host = tuple_value["hostHashes"][platform]
            capture_tuple = {key: value for key, value in tuple_value.items() if key != "hostHashes"}
            capture_tuple["hostHashes"] = {platform: host}
            return [{"id": f"pilot.{platform}.{index}", "platform": platform, "case": case_ref,
                     "tuple": capture_tuple, "meta": {"run": index},
                     "layout": [], "images": [], "ax": [], "events": [], "anim": [], "text": []}
                    for index in range(1, 21)]
        mac = capture_rows("macos")
        win = capture_rows("windows")
        refs = lambda rows: [{"id": row["id"], "hash": canonical_hash(row)} for row in rows]
        mac_repeat = {"runs": 20, "semanticAgreement": True, "evidence": refs(mac)}
        win_repeat = {"runs": 20, "semanticAgreement": True, "evidence": refs(win)}
        verdict = {"id": "pilot.verdict", "case": case_ref, "tuple": tuple_value,
                   "macCaptures": refs(mac), "windowsCaptures": refs(win),
                   "semantic": {"status": "pass", "results": [{"channel": "layout", "status": "pass"}]},
                   "timing": {"status": "pass"}, "repeatability": {"mac": mac_repeat, "windows": win_repeat}, "status": "pass"}
        with tempfile.TemporaryDirectory() as tmp:
            paths = build_report(registry, [case], mac + win, [verdict], tmp)
            report = Path(paths["blocks"][0]["markdown"]).read_text(encoding="utf-8")
        self.assertIn("Mac has no layout records for passing channel", report)
        self.assertIn("0 pass / 0 fail / 1 blocked", report)

        forged_hash = copy.deepcopy(verdict)
        forged_hash["macCaptures"][0]["hash"] = digest
        self.assertIn("hash does not match artifact", _case_status(case, forged_hash, mac + win)[1])

        duplicated_run = copy.deepcopy(mac)
        duplicated_run[0]["meta"]["run"] = 2
        duplicate_verdict = copy.deepcopy(verdict)
        duplicate_refs = refs(duplicated_run)
        duplicate_verdict["macCaptures"] = duplicate_refs
        duplicate_verdict["repeatability"]["mac"]["evidence"] = duplicate_refs
        self.assertIn("uniquely cover 1 through 20", _case_status(case, duplicate_verdict, duplicated_run + win)[1])

        for capture in mac + win:
            capture["layout"] = [{"probeTag": "probe", "viewIdentity": capture["id"], "frame": {}}]
        mac_refs, win_refs = refs(mac), refs(win)
        qualified_verdict = copy.deepcopy(verdict)
        qualified_verdict["macCaptures"], qualified_verdict["windowsCaptures"] = mac_refs, win_refs
        qualified_verdict["repeatability"]["mac"]["evidence"] = mac_refs
        qualified_verdict["repeatability"]["windows"]["evidence"] = win_refs
        self.assertIn("Supplied passing F10 receipt", _case_status(case, qualified_verdict, mac + win)[1])
        gate_receipt = {"kind": "receipt", "operation": "gate", "status": "pass", "tuple": tuple_value,
                        "provenance": {"producer": "factory.gate/0.1"},
                        "inputs": [{"id": "case.input.0", "hash": case_ref["hash"]}, *mac_refs, *win_refs],
                        "outputs": [{"id": "gate.f10.seed", "hash": digest}]}
        self.assertEqual(("pass", ""), _case_status(case, qualified_verdict, mac + win, [gate_receipt]))


if __name__ == "__main__":
    unittest.main()
