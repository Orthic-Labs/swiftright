#!/usr/bin/env python3
"""Unit tests for the first-line-band placement of pair_textcolour_report.position() (issue #7, G76).

  python3 -m unittest discover -s factory/tools -p 'test_pair_textcolour_report.py'

A single-line region keeps the one-line values exactly (no bandBottoms key). A multi-line region takes baseline and first ink from its first band only, so a
descender on a later line, or a later line whose glyph runs line up with the first, cannot move the placement; every band's bottom is gated within the row's baseline tolerance.
"""
import sys
import unittest
from collections import Counter
from pathlib import Path

from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pair_textcolour_report as TC  # noqa: E402

W, H = 200, 120
RECT = (0, 0, W, H)


def canvas(*boxes):
    """white canvas with black ink boxes (x0, y0, x1, y1) inclusive"""
    im = Image.new("RGB", (W, H), (255, 255, 255))
    d = ImageDraw.Draw(im)
    for b in boxes:
        d.rectangle(b, fill=(0, 0, 0))
    return im


def old_position(img, rect, background=None, coverage=0.15):
    """the position() of the committed report before issue #7 (one whole-block first column run), kept here as the reference for the one-line identity"""
    x0, y0, x1, y1 = rect
    px = img.load()
    pts = [(x, y, px[x, y]) for y in range(y0, y1) for x in range(x0, x1)]
    bg = tuple(background) if background else Counter(p for _, _, p in pts).most_common(1)[0][0]
    top = max(abs(TC.lum(p) - TC.lum(bg)) for _, _, p in pts)
    if top < 8:
        return None
    ink = [(x, y) for x, y, p in pts if abs(TC.lum(p) - TC.lum(bg)) >= coverage * top]
    cols = sorted({x for x, _ in ink})
    run = {cols[0]}
    for c in cols[1:]:
        if c != max(run) + 1:
            break
        run.add(c)
    xs = [x for x, _ in ink]
    rows = sorted({y for _, y in ink})
    bands = 1 + sum(1 for a, b in zip(rows, rows[1:]) if b != a + 1)
    return dict(firstInkX=cols[0], firstInkY=min(y for x, y in ink if x in run), baselineY=max(y for x, y in ink if x in run), inkCentreX=(min(xs) + max(xs) + 1) / 2,
                inkRightX=max(xs) + 1, inkHeight=max(rows) - min(rows) + 1, lineBands=bands)


class SingleLine(unittest.TestCase):
    def test_single_line_values_identical_to_one_line_reference(self):
        # one line: an H-like glyph pair, a glyph with a descender (y-like), and a space-separated word
        im = canvas((10, 20, 14, 30), (20, 20, 24, 30), (10, 26, 24, 27), (30, 20, 34, 36), (40, 20, 44, 30), (50, 20, 56, 26))
        self.assertEqual(TC.position(im, RECT), old_position(im, RECT))
        self.assertNotIn("bandBottoms", TC.position(im, RECT))
        self.assertEqual(TC.position(im, RECT)["lineBands"], 1)

    def test_single_line_with_background_values_identical(self):
        im = Image.new("RGB", (W, H), (30, 30, 30))
        ImageDraw.Draw(im).rectangle((10, 20, 60, 33), fill=(230, 230, 230))
        self.assertEqual(TC.position(im, RECT, (30, 30, 30)), old_position(im, RECT, (30, 30, 30)))

    def test_empty_region_is_none(self):
        self.assertIsNone(TC.position(Image.new("RGB", (W, H), (255, 255, 255)), RECT))


class TwoLines(unittest.TestCase):
    def setUp(self):
        # line 1: rows 10..20, letters at x 10..19 and 21..29 (a gap at x 20). line 2: rows 30..40 at the same letters, and a descender at x 10..19 rows 41..44.
        # the column 20 has ink only on line 2, so the old whole-block run reached x 10..29 and took the descender as the baseline.
        self.im = canvas((10, 10, 19, 20), (21, 10, 29, 20), (10, 30, 19, 40), (21, 30, 29, 40), (10, 41, 19, 44))

    def test_first_band_sets_first_ink_and_baseline(self):
        p = TC.position(self.im, RECT)
        self.assertEqual(p["lineBands"], 2)
        self.assertEqual(p["firstInkY"], 10)
        self.assertEqual(p["baselineY"], 20)     # line 1's bottom, not the line 2 descender (44)
        self.assertEqual(p["bandBottoms"], [20, 44])

    def test_old_whole_block_run_would_have_taken_the_descender(self):
        self.assertEqual(old_position(self.im, RECT)["baselineY"], 44)

    def test_line_extent_fields_unchanged(self):
        p, q = TC.position(self.im, RECT), old_position(self.im, RECT)
        for k in ("firstInkX", "inkCentreX", "inkRightX", "inkHeight", "lineBands"):
            self.assertEqual(p[k], q[k], k)

    def test_later_line_descender_does_not_move_placement(self):
        # the same first line with and without a descender on line 2: first-band placement is equal, the bottoms of line 2 differ
        plain = canvas((10, 10, 19, 20), (21, 10, 29, 20), (10, 30, 19, 40), (21, 30, 29, 40))
        a, b = TC.position(plain, RECT), TC.position(self.im, RECT)
        self.assertEqual((a["firstInkY"], a["baselineY"]), (b["firstInkY"], b["baselineY"]))
        self.assertEqual(a["bandBottoms"], [20, 40])
        self.assertEqual(b["bandBottoms"], [20, 44])

    def test_first_line_shift_is_seen(self):
        moved = canvas((10, 13, 19, 23), (21, 13, 29, 23), (10, 30, 19, 40), (21, 30, 29, 40), (10, 41, 19, 44))
        p, q = TC.position(moved, RECT), TC.position(self.im, RECT)
        self.assertEqual(p["firstInkY"] - q["firstInkY"], 3)
        self.assertEqual(p["baselineY"] - q["baselineY"], 3)

    def test_line2_shift_leaves_first_band_placement_and_is_caught_by_band_bottoms(self):
        # a band-2 shift of 3 px: first-band placement unchanged, band 2's bottom moves 3 px, the row's baseline tolerance (1 px) catches it
        moved = canvas((10, 10, 19, 20), (21, 10, 29, 20), (10, 33, 19, 43), (21, 33, 29, 43), (10, 44, 19, 47))
        p, q = TC.position(moved, RECT), TC.position(self.im, RECT)
        self.assertEqual((p["firstInkY"], p["baselineY"]), (q["firstInkY"], q["baselineY"]))
        self.assertEqual(p["bandBottoms"][1] - q["bandBottoms"][1], 3)
        self.assertEqual(p["inkHeight"] - q["inkHeight"], 3)
        why = TC.position_why(q, p, {"lineBands": 0, "baselineTolerancePx": 1}, "leading")
        self.assertEqual(len(why), 1)
        self.assertIn("[0, 3]", why[0])

    def test_band2_shift_of_one_pixel_passes(self):
        for dy in (-1, 1):
            moved = canvas((10, 10, 19, 20), (21, 10, 29, 20), (10, 30 + dy, 19, 40 + dy), (21, 30 + dy, 29, 40 + dy), (10, 41 + dy, 19, 44 + dy))
            p, q = TC.position(moved, RECT), TC.position(self.im, RECT)
            self.assertEqual(TC.position_why(q, p, {"lineBands": 0, "baselineTolerancePx": 1}, "leading"), [], dy)
            self.assertEqual(TC.band_deltas(q, p), [0, dy], dy)

    def test_band2_shift_of_three_pixels_fails_with_tolerance_one(self):
        moved = canvas((10, 10, 19, 20), (21, 10, 29, 20), (10, 33, 19, 43), (21, 33, 29, 43), (10, 44, 19, 47))
        p, q = TC.position(moved, RECT), TC.position(self.im, RECT)
        self.assertTrue(TC.position_why(q, p, {"baselineTolerancePx": 1}, "leading"))


class ThreeLines(unittest.TestCase):
    def setUp(self):
        # three bands at rows 10..20, 30..40, 50..60; band 2 has a descender at x 10..19 rows 41..44; band 3 a descender at x 21..29 rows 61..63
        self.im = canvas((10, 10, 19, 20), (21, 10, 29, 20), (10, 30, 19, 40), (21, 30, 29, 40), (10, 41, 19, 44), (10, 50, 19, 60), (21, 50, 29, 60), (21, 61, 29, 63))

    def test_three_bands(self):
        p = TC.position(self.im, RECT)
        self.assertEqual(p["lineBands"], 3)
        self.assertEqual(p["firstInkY"], 10)
        self.assertEqual(p["baselineY"], 20)
        self.assertEqual(p["bandBottoms"], [20, 44, 63])
        self.assertEqual(p["inkHeight"], 63 - 10 + 1)

    def test_middle_band_does_not_set_placement(self):
        moved = canvas((10, 10, 19, 20), (21, 10, 29, 20), (10, 33, 19, 43), (21, 33, 29, 43), (10, 50, 19, 60), (21, 50, 29, 60), (21, 61, 29, 63))
        p, q = TC.position(moved, RECT), TC.position(self.im, RECT)
        self.assertEqual((p["firstInkY"], p["baselineY"]), (q["firstInkY"], q["baselineY"]))
        self.assertEqual(p["lineBands"], q["lineBands"])


if __name__ == "__main__":
    unittest.main()
