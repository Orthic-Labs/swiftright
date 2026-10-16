#!/usr/bin/env python3
"""Unit test for the fixed-lease guard in pass_capture_lease.py.

  python3 -m unittest factory/tools/test_pass_capture_lease.py
"""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pass_capture_lease as pcl  # noqa: E402

FIXED_HOST = (
    "final class Host {\n"
    "    var windowClosed = false\n"
    "    init(_ bridge: Bridge) { self.bridge = bridge }\n"
    "    func tick(time: UInt64) {\n"
    "        if time - (started ?? time) > 10_000_000_000 { bridge.requestQuit() }\n"
    "    }\n"
    "}\n"
)
PARSED_HOST = FIXED_HOST.replace(pcl.ANCHOR, pcl.ANCHOR + pcl.PARSE_BLOCK).replace(pcl.FIXED_OLD, pcl.FIXED_NEW)


class FixedLeaseGuard(unittest.TestCase):
    def test_flags_fixed_compare_and_accepts_parsed(self):
        self.assertTrue(pcl.is_fixed_compare("if time - (started ?? time) > 10_000_000_000 { bridge.requestQuit() }"))
        self.assertTrue(pcl.is_fixed_compare("if time - started > 5_000_000_000 { x() }"))
        self.assertFalse(pcl.is_fixed_compare("if time - (started ?? time) > Self.leaseNS { bridge.requestQuit() }"))
        self.assertFalse(pcl.is_fixed_compare("        return 10_000_000_000"))
        self.assertFalse(pcl.is_fixed_compare("guard time - started >= 300_000_000, time - lastScriptTick >= 150_000_000 else { return }"))
        self.assertTrue(pcl.is_fixed_compare("if (time - (started ?? time)) > 10_000_000_000 { bridge.requestQuit() }"))
        self.assertTrue(pcl.is_fixed_compare("if time-(started??time)>10_000_000_000{ x() }"))
        self.assertTrue(pcl.is_fixed_compare("if time - startedAt > 5_000_000_000 { x() }"))
        self.assertFalse(pcl.is_fixed_compare("if (time - (started ?? time)) > Self.leaseNS) { x() }"))

    def test_apply_text_is_the_parsed_snippet(self):
        self.assertEqual(FIXED_HOST.count(pcl.FIXED_OLD), 1)
        self.assertEqual(FIXED_HOST.count(pcl.ANCHOR), 1)
        self.assertEqual(PARSED_HOST.count("static let leaseNS"), 1)
        self.assertIn("return 10_000_000_000\n    }()\n    init(_ bridge", PARSED_HOST)
        self.assertNotIn(pcl.FIXED_OLD, PARSED_HOST)

    def test_offender_scan_reports_only_fixed_blocks_hosts(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            fixed = root / "factory/pipeline/blocks-9-9/swiftui.x/case-v1/package/Sources/FactoryProbe"
            fixed.mkdir(parents=True)
            (fixed / "main.swift").write_text(FIXED_HOST)
            parsed = root / "factory/pipeline/blocks-9-9/swiftui.x/case-v2/package/Sources/FactoryProbe"
            parsed.mkdir(parents=True)
            (parsed / "main.swift").write_text(PARSED_HOST)
            archived = root / "factory/pipeline/pilot-delivery-five-v1/x/package/Sources/FactoryProbe"
            archived.mkdir(parents=True)
            (archived / "main.swift").write_text(FIXED_HOST)
            found = pcl.fixed_offenders(root)
            self.assertEqual(found, [("factory/pipeline/blocks-9-9/swiftui.x/case-v1/package/Sources/FactoryProbe/main.swift", 5)])


if __name__ == "__main__":
    unittest.main()
