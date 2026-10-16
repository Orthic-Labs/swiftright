#!/usr/bin/env python3
"""Unit test for the render-scale silent-skip guard in pass_render_scale.py.

  python3 -m unittest factory/tools/test_pass_render_scale.py
"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pass_render_scale as prs  # noqa: E402


class RunCallGuard(unittest.TestCase):
    def test_flags_run_without_render_scale_and_accepts_with(self):
        src = (
            'try bridge.run(title: "a", width: 320, height: 240, renderScale: factoryRenderScale)\n'
            'try bridge.run(title: "b", width: 320, height: 240)\n'
            'try Bridge.run(title: "c",\n'
            '    width: 320, height: 240,\n'
            '    pointerMoves: true)\n'
            'try bridge.run(title: "d", width: 320, height: 240, pointerMoves: true, renderScale: factoryRenderScale)\n'
        )
        calls = list(prs.run_call_args(src))
        self.assertEqual([line for line, _ in calls], [1, 2, 3, 6])
        self.assertEqual(["renderScale" in args for _, args in calls], [True, False, False, True])

    def test_ignores_other_receivers(self):
        src = "let x = mybridge.run(title: \"z\")\nsomething.run(width: 1)\n"
        self.assertEqual(list(prs.run_call_args(src)), [])

    def test_scan_reports_offender_under_blocks_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            good = root / "factory/pipeline/blocks-x/host/CaptureHost.template.swift"
            bad = root / "factory/pipeline/blocks-x/host/package/Sources/FactoryProbe/main.swift"
            archived = root / "factory/pipeline/pilot-delivery-five-v1/main.swift"
            for p in (good, bad, archived):
                p.parent.mkdir(parents=True, exist_ok=True)
            good.write_text('try bridge.run(title: "t", width: 320, height: 240, renderScale: factoryRenderScale)\n')
            bad.write_text('let ok = 1\ntry bridge.run(title: "t", width: 320, height: 240)\n')
            archived.write_text('try bridge.run(title: "t", width: 320, height: 240)\n')
            self.assertEqual(prs.scan_offenders(root),
                             [("factory/pipeline/blocks-x/host/package/Sources/FactoryProbe/main.swift", 2)])


if __name__ == "__main__":
    unittest.main()
