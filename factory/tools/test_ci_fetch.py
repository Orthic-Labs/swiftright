#!/usr/bin/env python3
"""Unit test for ci_fetch.py: canonical build.json choice, pipeline-relative case keys, local out paths.

  python3 -m unittest factory/tools/test_ci_fetch.py
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ci_fetch as cf  # noqa: E402

MAC = {"mac": {"scaleGuard": {"status": "pass"}}}
MERGED = dict(MAC, stage={"name": "645396d04-5dfe7cc2"}, renderer={"label": "renderer-0.10-a15ebc5d"}, windows={"capture": {"ok": True}})


def write(path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(obj if isinstance(obj, str) else json.dumps(obj, indent=1))
    return path


class Canonical(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="ci-fetch-test-"))
        self.rel = "factory/pipeline/blocks-6-10/swiftui.x/case-v1/runs/20261016-031740/build.json"

    def copies(self, mac_obj, cmp_obj):
        m = write(self.tmp / "mac-1" / self.rel, mac_obj)
        c = write(self.tmp / "compare-results" / self.rel, cmp_obj)
        return [("mac-1", m), ("compare-results", c)]

    def test_identical_copies_are_one_file(self):
        src, how = cf.choose_copy(self.rel, self.copies(MAC, MAC))
        self.assertEqual(how, "identical")

    def test_mac_copy_that_is_subset_of_merged_copy_yields_to_compare_results(self):
        src, how = cf.choose_copy(self.rel, self.copies(MAC, MERGED))
        self.assertEqual(how, "canonical-compare-results")
        self.assertEqual(src, self.tmp / "compare-results" / self.rel)
        self.assertIn("windows", json.loads(src.read_text()))

    def test_conflicting_value_is_refused(self):
        bad = dict(MERGED, mac={"scaleGuard": {"status": "FAIL"}})
        with self.assertRaises(SystemExit):
            cf.choose_copy(self.rel, self.copies(MAC, bad))

    def test_non_json_difference_is_refused(self):
        a = write(self.tmp / "mac-1" / "factory/pipeline/x/y.txt", "a")
        b = write(self.tmp / "compare-results" / "factory/pipeline/x/y.txt", "b")
        with self.assertRaises(SystemExit):
            cf.choose_copy("factory/pipeline/x/y.txt", [("mac-1", a), ("compare-results", b)])

    def test_plan_uses_each_path_once(self):
        cps = self.copies(MAC, MERGED)
        entries = [(art, Path(src).relative_to(self.tmp / art), src) for art, src in cps]
        results, chosen = cf.plan(entries)
        self.assertEqual(results, [])
        self.assertEqual(list(chosen), [self.rel])


class Keys(unittest.TestCase):
    def test_pipeline_relative_case(self):
        self.assertEqual(cf.pipeline_case("factory/pipeline/blocks-6-10/swiftui.animation/completion-v1"),
                         "blocks-6-10/swiftui.animation/completion-v1")
        self.assertEqual(cf.pipeline_case("factory/pipeline/blocks-6-10/a/b/"), "blocks-6-10/a/b")

    def test_repo_relative_only(self):
        with self.assertRaises(ValueError):
            cf.pipeline_case("blocks-6-10/swiftui.animation/completion-v1")
        with self.assertRaises(ValueError):
            cf.pipeline_case("factory/other/x")

    def test_record_rewritten_to_local_shape(self):
        rec = {"stage": "645396d04-5dfe7cc2", "case": "factory/pipeline/blocks-6-10/swiftui.animation/completion-v1",
               "n": 3, "ts": "20261016-031740", "exit": 1, "out": "D:\\a\\_temp\\pairs\\x"}
        local = cf.record_for_local(rec)
        self.assertEqual(local["case"], "blocks-6-10/swiftui.animation/completion-v1")
        self.assertEqual(local["out"], str((cf.PIPELINE / "blocks-6-10/swiftui.animation/completion-v1/runs/20261016-031740").resolve()))
        self.assertEqual(local["exit"], 1)
        self.assertEqual(rec["case"], "factory/pipeline/blocks-6-10/swiftui.animation/completion-v1")  # input untouched


if __name__ == "__main__":
    unittest.main()
