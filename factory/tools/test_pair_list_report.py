#!/usr/bin/env python3
"""Unit test for the list gate's background sample in pair_list_report.py (the sample must lie inside the row, not in the list gutter).

  python3 -m unittest discover -s factory/tools -p 'test_pair_list_report.py'
"""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pair_list_report as plr  # noqa: E402

# controls-b at scale 2.5: list rect (100, 270) .. (550, 495); the rows are x 100 .. 508 (163.2 pt), the label starts at listRect.x0 + 40 = 140
LIST_X0, LIST_X1 = 100, 550
ROW_X, ROW_W = 100, 408
LABEL_X0 = LIST_X0 + 40


class BackgroundSample(unittest.TestCase):
    def test_sample_is_inside_the_row_and_right_of_the_label(self):
        x = plr.background_x(ROW_X, ROW_W, LABEL_X0)
        self.assertEqual(x, 300)
        self.assertTrue(ROW_X < x < ROW_X + ROW_W)
        self.assertFalse(LABEL_X0 <= x < LABEL_X0 + plr.LABEL_W)

    def test_old_sample_fell_in_the_gutter(self):
        old = LIST_X1 - 30   # 520: past the row's right edge at 508, inside the 42 px gutter
        self.assertFalse(ROW_X <= old < ROW_X + ROW_W)

    def test_no_sample_when_the_row_is_too_narrow(self):
        self.assertIsNone(plr.background_x(ROW_X, 100, LABEL_X0))   # the row ends before the label does
        self.assertIsNone(plr.background_x(ROW_X, 0, LABEL_X0))


if __name__ == "__main__":
    unittest.main()
