#!/usr/bin/env python3
"""Unit tests for pair.py's F-path gate (sr1-decisions 20 Oct: measured tolerances, dash geometry) on synthetic images:
python3 factory/tools/test_pair_edge_stats.py
Each test is a defect the gate must catch or a thing it must let through. Without the new pair.json fields the gate is the old one (default block)."""
import json, math, sys, tempfile, unittest
from pathlib import Path
from PIL import Image
sys.path.insert(0, str(Path(__file__).resolve().parent))
import pair


def base_image():
    """White 100x100 with a black 60x60 square: its edges give a band of several hundred pixels."""
    im = Image.new("RGB", (100, 100), (255, 255, 255))
    for y in range(20, 80):
        for x in range(20, 80):
            im.putpixel((x, y), (0, 0, 0))
    return im


def band_pixels(mac):
    band = pair.edge_band(mac)
    return [(x, y) for y in range(mac.size[1]) for x in range(mac.size[0]) if band.getpixel((x, y))]


def with_band_diffs(mac, plan, pixels=None):
    """Copy of mac where the first band pixels (row-major) differ by the given levels: plan = [(count, level), ...] in order."""
    win = mac.copy()
    pts = band_pixels(mac) if pixels is None else pixels
    i = 0
    for count, d in plan:
        for _ in range(count):
            x, y = pts[i]; i += 1
            m = mac.getpixel((x, y))[0]
            v = m - d if m >= d else m + d
            win.putpixel((x, y), (v, v, v))
    return win


def set_state(edge_aa=32, stats=None, haze=0, dash=None, expect_fail=False):
    pair.EDGE_AA, pair.EDGE_STATS, pair.HAZE = edge_aa, stats, haze
    pair.DASH_GEOM, pair.EXPECT_FAIL = dash, expect_fail


class DefaultBehaviour(unittest.TestCase):
    def setUp(self):
        set_state()
        self.mac = base_image()

    def test_identical_is_exact(self):
        self.assertEqual(pair.edge_gate(self.mac, self.mac)["verdict"], "exact")

    def test_band_within_levels_passes_as_before(self):
        g = pair.edge_gate(self.mac, with_band_diffs(self.mac, [(3, 20)]))
        self.assertEqual(g["verdict"], "edge-aa<=32")
        self.assertEqual(set(g), {"verdict", "totalDiff", "inBandDiff", "outOfBandDiff", "maxInBand", "maxOutOfBand", "bandPixels"})

    def test_band_over_levels_fails_as_before(self):
        self.assertEqual(pair.edge_gate(self.mac, with_band_diffs(self.mac, [(1, 40)]))["verdict"], "fail")

    def test_out_of_band_difference_fails_as_before(self):
        win = self.mac.copy(); win.putpixel((5, 5), (254, 254, 254))   # far from every edge
        self.assertEqual(pair.edge_gate(self.mac, win)["verdict"], "fail")

    def test_no_pair_json_gives_defaults(self):
        with tempfile.TemporaryDirectory() as d:
            pair.apply_gate_config(Path(d))
        self.assertEqual((pair.EDGE_AA, pair.EDGE_STATS, pair.DASH_GEOM, pair.EXPECT_FAIL, pair.HAZE), (32, None, None, False, 0))

    def test_levels_only_pill_config_is_unchanged(self):
        with tempfile.TemporaryDirectory() as d:
            Path(d, "pair.json").write_text(json.dumps({"edgeAATolerance": {"levels": 210, "reason": "measured"}}))
            pair.apply_gate_config(Path(d))
        self.assertEqual((pair.EDGE_AA, pair.EDGE_STATS), (210, None))
        self.assertEqual(pair.edge_gate(self.mac, with_band_diffs(self.mac, [(1, 200)]))["verdict"], "edge-aa<=32")


class MaxOverPixels(unittest.TestCase):
    def setUp(self):
        set_state(edge_aa=160, stats={"maxOverPixels": 4})
        self.mac = base_image()

    def test_up_to_four_over_pixels_pass(self):
        g = pair.edge_gate(self.mac, with_band_diffs(self.mac, [(4, 40)]))
        self.assertEqual(g["verdict"], "edge-aa-stats")
        self.assertEqual(g["overPixels"], 4)

    def test_five_over_pixels_fail(self):
        self.assertEqual(pair.edge_gate(self.mac, with_band_diffs(self.mac, [(5, 40)]))["verdict"], "fail")

    def test_levels_stays_a_per_pixel_ceiling(self):
        # one pixel at 170 > levels 160 fails even though only one pixel is over 32
        self.assertEqual(pair.edge_gate(self.mac, with_band_diffs(self.mac, [(1, 170)]))["verdict"], "fail")

    def test_fill_config_levels_32_is_a_ceiling_too(self):
        # With levels 32 the over-32 count is always zero: a fill case cannot use maxOverPixels above 32 (see report).
        set_state(edge_aa=32, stats={"maxOverPixels": 4})
        self.assertEqual(pair.edge_gate(self.mac, with_band_diffs(self.mac, [(2, 40)]))["verdict"], "fail")


class MaxOverFraction(unittest.TestCase):
    def setUp(self):
        set_state(edge_aa=160, stats={"maxOverFraction": 0.01})
        self.mac = base_image()
        self.nb = pair.edge_gate(self.mac, self.mac)["bandPixels"]

    def test_fraction_under_limit_passes(self):
        k = max(1, int(0.005 * self.nb))
        self.assertLessEqual(k / self.nb, 0.01)
        self.assertEqual(pair.edge_gate(self.mac, with_band_diffs(self.mac, [(k, 40)]))["verdict"], "edge-aa-stats")

    def test_fraction_over_limit_fails(self):
        k = math.ceil(0.02 * self.nb)
        self.assertGreater(k / self.nb, 0.01)
        self.assertEqual(pair.edge_gate(self.mac, with_band_diffs(self.mac, [(k, 40)]))["verdict"], "fail")

    def test_levels_within_32_do_not_count_as_over(self):
        self.assertEqual(pair.edge_gate(self.mac, with_band_diffs(self.mac, [(self.nb, 30)]))["verdict"], "edge-aa-stats")


class MaxMeanAbs(unittest.TestCase):
    def setUp(self):
        self.mac = base_image()

    def test_mean_above_limit_fails(self):
        set_state(edge_aa=160, stats={"maxMeanAbs": 6})
        nb = pair.edge_gate(self.mac, self.mac)["bandPixels"]
        g = pair.edge_gate(self.mac, with_band_diffs(self.mac, [(nb, 10)]))
        self.assertEqual(g["meanAbs"], 10)
        self.assertEqual(g["verdict"], "fail")

    def test_mean_within_limit_passes(self):
        set_state(edge_aa=160, stats={"maxMeanAbs": 12})
        nb = pair.edge_gate(self.mac, self.mac)["bandPixels"]
        self.assertEqual(pair.edge_gate(self.mac, with_band_diffs(self.mac, [(nb, 10)]))["verdict"], "edge-aa-stats")

    def test_mean_counts_zero_difference_band_pixels(self):
        set_state(edge_aa=160, stats={"maxMeanAbs": 6})
        nb = pair.edge_gate(self.mac, self.mac)["bandPixels"]
        half = nb // 2
        g = pair.edge_gate(self.mac, with_band_diffs(self.mac, [(half, 10)]))
        self.assertAlmostEqual(g["meanAbs"], 10 * half / nb, places=3)
        self.assertEqual(g["verdict"], "edge-aa-stats")


def ring(size=220, center=110, shift=0, skip=None):
    """Dashed ring: period 45 deg (8 dashes, 27 deg on) on radius 74..86, rotated by shift; `skip` drops one dash (0..7)."""
    im = Image.new("RGB", (size, size), (255, 255, 255))
    for y in range(size):
        for x in range(size):
            dx, dy = x - center, y - center
            r = math.hypot(dx, dy)
            if 74 <= r <= 86:
                th = math.degrees(math.atan2(dy, dx)) % 360
                if (th - shift) % 45 < 27 and (skip is None or int(th // 45) != skip):
                    im.putpixel((x, y), (51, 153, 255))
    return im


DASH = {"center": [110, 110], "radius": 80, "maxAngleDeg": 1.5}


class DashGeometry(unittest.TestCase):
    def setUp(self):
        set_state()
        self.mac = ring()

    def test_identical_dashes_pass(self):
        dg = pair.dash_check(self.mac, self.mac, DASH)
        self.assertTrue(dg["ok"])
        self.assertGreater(dg["macEdges"], 0)
        self.assertEqual(dg["macEdges"], dg["winEdges"])
        self.assertEqual(dg["worstAngleDeg"], 0)

    def test_shifted_dashes_fail_at_tight_limit_and_pass_at_loose(self):
        win = ring(shift=8)
        self.assertFalse(pair.dash_check(self.mac, win, DASH)["ok"])
        self.assertTrue(pair.dash_check(self.mac, win, dict(DASH, maxAngleDeg=10))["ok"])

    def test_missing_dash_fails_on_count(self):
        dg = pair.dash_check(self.mac, ring(skip=7), DASH)
        self.assertFalse(dg["ok"])
        self.assertEqual(dg["reason"], "dash edge count differs")

    def test_blank_capture_fails_no_dash(self):
        blank = Image.new("RGB", (220, 220), (255, 255, 255))
        dg = pair.dash_check(blank, blank, DASH)
        self.assertFalse(dg["ok"])
        self.assertEqual(dg["reason"], "no dash found")

    def test_circle_outside_capture_raises(self):
        small = Image.new("RGB", (50, 50), (255, 255, 255))
        with self.assertRaises(ValueError):
            pair.dash_edges(small, (25, 25), 40)



class ConfigAndExpectFail(unittest.TestCase):
    def test_stats_and_dash_read_from_pair_json(self):
        with tempfile.TemporaryDirectory() as d:
            Path(d, "pair.json").write_text(json.dumps({
                "edgeAATolerance": {"levels": 160, "maxOverFraction": 0.01, "maxMeanAbs": 6, "reason": "measured"},
                "dashGeometry": {"center": [1, 2], "radius": 3, "maxAngleDeg": 1.5}}))
            pair.apply_gate_config(Path(d))
        self.assertEqual(pair.EDGE_AA, 160)
        self.assertEqual(pair.EDGE_STATS, {"maxOverFraction": 0.01, "maxMeanAbs": 6})
        self.assertEqual(pair.DASH_GEOM["radius"], 3)
        set_state()

    def test_edge_tolerance_without_reason_is_refused(self):
        with tempfile.TemporaryDirectory() as d:
            Path(d, "pair.json").write_text(json.dumps({"edgeAATolerance": {"levels": 32, "maxOverPixels": 4}}))
            with self.assertRaises(AssertionError):
                pair.apply_gate_config(Path(d))
        set_state()

    def test_dash_geometry_needs_all_keys(self):
        with tempfile.TemporaryDirectory() as d:
            Path(d, "pair.json").write_text(json.dumps({"dashGeometry": {"center": [1, 2], "radius": 3}}))
            with self.assertRaises(AssertionError):
                pair.apply_gate_config(Path(d))
        set_state()

    def test_expect_fail_inverts_the_exit_code(self):
        set_state(expect_fail=True)
        with self.assertRaises(SystemExit) as gate_failed:
            pair._exit(1)
        self.assertEqual(gate_failed.exception.code, 0)
        with self.assertRaises(SystemExit) as gate_passed:
            pair._exit(0)
        self.assertEqual(gate_passed.exception.code, 1)
        set_state()

    def test_without_expect_fail_the_exit_code_is_unchanged(self):
        set_state()
        with self.assertRaises(SystemExit) as cm:
            pair._exit(1)
        self.assertEqual(cm.exception.code, 1)


if __name__ == "__main__":
    unittest.main()
