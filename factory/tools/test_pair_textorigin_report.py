#!/usr/bin/env python3
"""Unit tests for pair_textorigin_report on synthetic fields: python3 factory/tools/test_pair_textorigin_report.py
Each test is a defect the gate must catch (text 5 px left, wrong selection colour, selection start moved, selection on one side only) or a thing it must let through."""
import sys, unittest
from pathlib import Path
from PIL import Image, ImageDraw
sys.path.insert(0, str(Path(__file__).resolve().parent))
import pair_textorigin_report as r

FRAME = [25, 25, 325, 85]
SEL = (179, 215, 255)


def field(ink_x=43, sel=None, caret_x=None):
    im = Image.new("RGB", (400, 120), (255, 255, 255)); d = ImageDraw.Draw(im)
    d.rectangle([25, 25, 324, 84], fill=(254, 254, 251))
    if sel: d.rectangle([sel[1], 40, sel[2], 70], fill=sel[0])
    d.rectangle([ink_x, 45, ink_x + 3, 68], fill=(33, 33, 33))          # a glyph stem
    d.rectangle([ink_x + 20, 45, ink_x + 40, 68], fill=(33, 33, 33))
    if caret_x: d.rectangle([caret_x, 40, caret_x + 1, 70], fill=(17, 17, 17))
    return im


class TextOrigin(unittest.TestCase):
    def verdict(self, mac, win, **cfg):
        return r.gate(r.analyse(mac, FRAME), r.analyse(win, FRAME), cfg)

    def test_identical_passes(self):
        self.assertEqual(self.verdict(field(43), field(43)), [])

    def test_text_five_px_left_fails(self):             # the bezelTextInset = 4 defect: Windows ink 5-7 px left of the Mac
        self.assertTrue(self.verdict(field(43), field(38)))

    def test_named_tolerance_allows_only_that_much(self):
        self.assertEqual(self.verdict(field(43), field(42), firstInkTolerancePx=1), [])
        self.assertTrue(self.verdict(field(43), field(41), firstInkTolerancePx=1))

    def test_selection_start_must_be_equal(self):
        self.assertEqual(self.verdict(field(43, (SEL, 40, 100)), field(43, (SEL, 40, 90))), [])   # the end follows the glyph advances: not gated
        self.assertTrue(self.verdict(field(43, (SEL, 40, 100)), field(43, (SEL, 35, 100))))

    def test_selection_colour_must_be_equal(self):
        self.assertTrue(self.verdict(field(43, (SEL, 40, 100)), field(43, ((153, 201, 239), 40, 100))))

    def test_selection_on_one_side_fails(self):
        self.assertTrue(self.verdict(field(43, (SEL, 40, 100)), field(43)))
        self.assertTrue(self.verdict(field(43), field(43, (SEL, 40, 100))))

    def test_selection_edge_is_not_ink(self):            # the highlight is far lighter than glyph ink: it must not become the first ink
        a = r.analyse(field(60, (SEL, 40, 100)), FRAME)
        self.assertEqual(a["firstInkX"], 60)
        self.assertEqual(a["selection"]["startX"], 40)

    def test_plain_scan_reaches_frame_edge(self):      # scanInteriorPx 0 (plain field): ink at the frame's first column is seen; the bezeled margin 2 skips it
        self.assertEqual(r.analyse(field(25), FRAME, 0)["firstInkX"], 25)
        self.assertEqual(r.analyse(field(25), FRAME)["firstInkX"], 27)

    def test_caret_is_reported_not_ink(self):
        a = r.analyse(field(60, None, 41), FRAME)
        self.assertEqual(a["firstInkX"], 60)
        self.assertEqual(a["caretX"], [41, 42])


if __name__ == "__main__":
    unittest.main()
