#!/usr/bin/env python3
"""Unit test for the hand-entry checks of generate.py: python3 factory/tools/proven-controls/test_hand_entries.py
One good entry (the real I2 hand entry, valid against docs/sr1-status.md and the factory tree) passes; one bad entry (a status
outside the allowed set, a missing case, a missing evidence path, a block id the generator already emits) yields each violation."""
import copy, json, sys, unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import generate as g

GOOD = json.loads((HERE / "hand-entries.json").read_text())[0]


class HandEntryChecks(unittest.TestCase):
    def setUp(self):
        self.status = g.STATUS.read_text()
        self.generated = {"swiftui.image"}

    def test_good_entry_passes(self):
        self.assertEqual(g.validate_hand_entries([copy.deepcopy(GOOD)], self.generated, self.status), [])

    def test_bad_entry_is_rejected_with_each_violation(self):
        bad = copy.deepcopy(GOOD)
        bad["block"] = "swiftui.image"                       # duplicates a generated block id
        bad["status"] = "delivered-ish"                      # outside the allowed set
        bad["cases"] = ["blocks-w1-i2/swiftui.image-layout/no-such-case-v1"]
        bad["verdict"]["source"] = "docs/sr1-status.md I2 row + factory/pipeline/blocks-w1-i2/no-such-evidence"
        errors = g.validate_hand_entries([bad], self.generated, self.status)
        text = "\n".join(errors)
        self.assertIn("duplicates a generated block id", text)
        self.assertIn("status 'delivered-ish'", text)
        self.assertIn("case path does not exist", text)
        self.assertIn("evidence path does not exist", text)

    def test_missing_status_row_and_duplicate_entry_are_rejected(self):
        orphan = copy.deepcopy(GOOD); orphan["block"] = "foundations.orphan"; orphan["statusDocBlock"] = "ZZ"
        errors = g.validate_hand_entries([orphan, copy.deepcopy(GOOD), copy.deepcopy(GOOD)], self.generated, self.status)
        text = "\n".join(errors)
        self.assertIn("no row 'ZZ'", text)
        self.assertIn("duplicate hand entry", text)

    def test_structural_violations_are_rejected(self):
        drift = copy.deepcopy(GOOD); drift["status"] = "delivered"                # the I2 row says delivered-pending-review
        empty = copy.deepcopy(GOOD); empty["cases"] = []
        nopath = copy.deepcopy(GOOD); nopath["verdict"]["source"] = "the I2 row and its evidence"
        caveats = copy.deepcopy(GOOD); caveats["caveats"] = "one caveat as a string"
        errors = "\n".join(g.validate_hand_entries([drift, empty, nopath, caveats], self.generated, self.status))
        self.assertIn("differs from the bold status 'delivered-pending-review'", errors)
        self.assertIn("cases is empty", errors)
        self.assertIn("verdict.source names no path", errors)
        self.assertIn("caveats is not a list", errors)

    def test_good_entry_has_no_structural_errors(self):
        self.assertEqual(g.validate_hand_entries([copy.deepcopy(GOOD)], self.generated, self.status), [])


if __name__ == "__main__":
    unittest.main()
