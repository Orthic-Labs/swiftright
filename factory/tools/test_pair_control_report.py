#!/usr/bin/env python3
"""Unit tests for pair_control_report.label_box on synthetic images: python3 factory/tools/test_pair_control_report.py"""
import sys, unittest
from pathlib import Path
from PIL import Image, ImageDraw
sys.path.insert(0, str(Path(__file__).resolve().parent))
import pair_control_report as r


def canvas(box=None, label=None):
    im = Image.new("RGB", (200, 60), (255, 255, 255)); d = ImageDraw.Draw(im)
    if box: d.rectangle(box, fill=(0, 120, 249))
    if label: d.rectangle(label, fill=(0, 0, 0))
    return im


class LabelBox(unittest.TestCase):
    def test_label_right_of_control_at_x0(self):      # the checkbox case that used to report [0,11,1,33] (the box's own edge)
        self.assertEqual(r.label_box(canvas((0, 10, 39, 49), (54, 20, 120, 40)), (0, 40)), [54, 20, 121, 41])

    def test_label_left_of_control(self):             # a switch
        self.assertEqual(r.label_box(canvas((100, 10, 160, 49), (2, 22, 80, 38)), (100, 161)), [2, 22, 81, 39])

    def test_no_label_returns_none(self):
        self.assertIsNone(r.label_box(canvas((0, 10, 39, 49)), (0, 40)))
        self.assertIsNone(r.label_box(canvas((100, 10, 160, 49)), (100, 161)))

    def test_control_own_edge_is_not_a_label(self):
        self.assertIsNone(r.label_box(canvas((1, 10, 39, 49)), (1, 40)))


if __name__ == "__main__":
    unittest.main()
