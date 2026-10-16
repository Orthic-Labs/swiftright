#!/usr/bin/env python3
"""Unit test for the runner's guest scripts: every script a case type uses resolves in the checkout, and the job names the repo capture.

  python3 -m unittest factory/tools/test_ci_pair_guest.py
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ci_pair as cp  # noqa: E402


class GuestScripts(unittest.TestCase):
    def test_every_kind_resolves(self):
        for kind in ("capture", "clock", "interact"):
            for f in cp.guest_scripts(kind):
                self.assertTrue(f.is_file(), f"{kind}: missing {f}")

    def test_clock_and_capture_use_repo_capture_script(self):
        self.assertEqual(cp.CAPTURE_SCRIPT, Path(cp.HERE, "pair", "capture.ps1"))
        for kind in ("clock", "capture"):
            args = cp.job_args(kind, Path("x.exe"), 3, Path("r.dll"), clock=[0.0, 0.1] if kind == "clock" else None)
            self.assertEqual(args["captureScript"], str(cp.CAPTURE_SCRIPT))
            self.assertNotIn("C:\\sbq", args["captureScript"])
        self.assertNotIn("captureScript", cp.job_args("interact", Path("x.exe"), 3, Path("r.dll"), steps=[{"op": "wait", "ms": 1}]))

    def test_kind_from_case_files(self):
        self.assertEqual(cp.job_kind([0.0], None), "clock")
        self.assertEqual(cp.job_kind(None, [{"op": "wait"}]), "interact")
        self.assertEqual(cp.job_kind(None, None), "capture")

    def test_guest_default_is_sandbox_path_only_without_argument(self):
        for name in ("job-clock.ps1", "job-capture.ps1"):
            text = (cp.GUEST / name).read_text(encoding="utf-8")
            self.assertIn("if ($job.args.captureScript)", text, name)
            self.assertIn("-File $capture ", text, name)
            self.assertEqual(text.count("C:\\sbq\\guest\\capture.ps1"), 1, name)


if __name__ == "__main__":
    unittest.main()
