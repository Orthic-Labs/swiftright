#!/usr/bin/env python3
"""Unit test for the scroll gate (pair_scroll_report.py, issue #31) on synthetic MAC_SCROLL / WIN_SCROLL logs.

  python3 -I factory/tools/test_pair_scroll_report.py
"""
import json, subprocess, sys, tempfile, unittest
from pathlib import Path

TOOLS = Path(__file__).resolve().parent
sys.path.insert(0, str(TOOLS))
import pair_scroll_report as psr  # noqa: E402

REST = 0.2  # the Mac List rest offset at the first label
MAC_CLIP = 89.6  # the Mac viewport: 0.4 pt shorter than the 90 pt Windows viewport


def mac_line(label, offset, status="OK", content=92.0, view=MAC_CLIP, scroller=0.0):
    return (f"MAC_SCROLL label={label} how=wheel status={status} moved=true before=0.000 offset={offset:.3f} pageAmount=0.000 "
            f"verticalPageScroll=0.000 verticalLineScroll=0.000 top=0.000 contentHeight={content:.3f} viewportHeight={view:.3f} "
            f"scrollerValue={scroller:.3f} axValue=-1.000 knobProportion=0.500 hasScroller=true flipped=true insets=10.0,10.0 selected=-1")


def win_line(label, offset, content=92.0, view=90.0, value=0.0):
    return f"WIN_SCROLL label={label} offset={offset:.3f} contentHeight={content:.3f} viewportHeight={view:.3f} value={value:.3f}"


# a wheel case with a 212 pt document: the Mac first label at the rest offset, then 3 lines (72 pt) and 10 lines (clamped at 122.2 pt)
def wheel_mac(w3=72.0 + REST, w10=122.2, status="OK", content=212.0, view=MAC_CLIP):
    return [mac_line("w0-to", REST, content=content, view=view), mac_line("w1-wheel", REST + 24.0, content=content, view=view),
            mac_line("w3-reset", REST, content=content, view=view), mac_line("w3-wheel", w3, status=status, content=content, view=view),
            mac_line("w10-reset", REST, content=content, view=view), mac_line("w10-wheel", w10, content=content, view=view)]


def wheel_win(in1=72.0, in10=122.0, content=212.0, view=90.0):
    return [win_line("in0", 0.0, content=content, view=view), win_line("in1", in1, content=content, view=view),
            win_line("in10", in10, content=content, view=view)]


WHEEL_PAIRS = [{"mac": "w3", "win": "in1", "perLine": True, "macLines": 3, "winLines": 3}, {"mac": "w10", "win": "in10", "clamp": True}]
TOL = 1.0


def judge(pair, mac_lines, win_lines, first="w0"):
    m = psr.mac_reading(mac_lines, pair["mac"])
    w = psr.win_reading(win_lines, pair["win"])
    f = psr.mac_reading(mac_lines, first)
    return psr.judge(pair, m, w, f["offset"] if f else None, TOL)


class PerLinePair(unittest.TestCase):
    def test_three_lines_agree(self):
        ok, probs = judge(WHEEL_PAIRS[0], wheel_mac(), wheel_win(in1=72.0))
        self.assertTrue(ok, probs)

    def test_within_tolerance_passes(self):
        ok, _ = judge(WHEEL_PAIRS[0], wheel_mac(), wheel_win(in1=72.6))   # 0.6 pt over 3 lines
        self.assertTrue(ok)

    def test_per_line_difference_fails(self):
        ok, probs = judge(WHEEL_PAIRS[0], wheel_mac(), wheel_win(in1=60.0))   # 12 pt short: 4 pt per line against 24
        self.assertFalse(ok)
        self.assertTrue(any("per-line" in p for p in probs), probs)

    def test_clamped_reading_is_not_a_per_line_amount(self):
        lines = wheel_mac(w3=122.2)   # the Mac's 3-line wheel reached the range end: no per-line amount
        ok, probs = judge(WHEEL_PAIRS[0], lines, wheel_win(in1=72.0))
        self.assertFalse(ok)
        self.assertTrue(any("range end" in p for p in probs), probs)


class ClampPair(unittest.TestCase):
    def test_both_at_their_end_passes(self):
        ok, probs = judge(WHEEL_PAIRS[1], wheel_mac(), wheel_win(in10=122.0))   # mac 122.2 - 0.2 = 122.0 ends at 212 - 89.6 = 122.4; windows ends at 122
        self.assertTrue(ok, probs)

    def test_windows_short_of_its_end_fails(self):
        ok, probs = judge(WHEEL_PAIRS[1], wheel_mac(), wheel_win(in10=100.0))
        self.assertFalse(ok)
        self.assertTrue(any("windows not at its range end" in p for p in probs), probs)

    def test_mac_short_of_its_end_fails(self):
        ok, probs = judge(WHEEL_PAIRS[1], wheel_mac(w10=60.0), wheel_win(in10=122.0))
        self.assertFalse(ok)
        self.assertTrue(any("mac not at its range end" in p for p in probs), probs)

    def test_range_ends_must_agree(self):
        mac = wheel_mac(content=212.0, view=MAC_CLIP)
        win = [win_line("in10", 62.0, content=212.0, view=150.0)]   # windows sits at its end 62; the Mac's end is 122.4
        ok, probs = judge(WHEEL_PAIRS[1], mac, win)
        self.assertFalse(ok)
        self.assertTrue(any("range ends differ" in p for p in probs), probs)


class DragPair(unittest.TestCase):
    def mac(self, label, offset, value, status="OK"):
        return [mac_line("o0-to", REST, scroller=0.0), mac_line(f"{label}-to", offset, status=status, scroller=value)]

    def test_offset_and_value_agree(self):
        ok, probs = judge({"mac": "omid", "win": "in1"}, self.mac("omid", 40.2, 0.5), [win_line("in1", 40.0, value=0.5)], first="o0")
        self.assertTrue(ok, probs)

    def test_offset_disagreement_fails(self):
        ok, probs = judge({"mac": "omid", "win": "in1"}, self.mac("omid", 40.2, 0.5), [win_line("in1", 30.0, value=0.5)], first="o0")
        self.assertFalse(ok)
        self.assertTrue(any("offset mac" in p for p in probs), probs)

    def test_value_disagreement_fails(self):
        ok, probs = judge({"mac": "omid", "win": "in1"}, self.mac("omid", 40.2, 0.5), [win_line("in1", 40.0, value=0.6)], first="o0")
        self.assertFalse(ok)
        self.assertTrue(any("value" in p for p in probs), probs)

    def test_no_mac_scroller_fails(self):
        ok, probs = judge({"mac": "omid", "win": "in1"}, self.mac("omid", 40.2, -1.0), [win_line("in1", 40.0, value=0.5)], first="o0")
        self.assertFalse(ok)
        self.assertTrue(any("no scroller value" in p for p in probs), probs)


class FailClosed(unittest.TestCase):
    def test_mac_status_fail_fails_the_pair(self):
        ok, probs = judge(WHEEL_PAIRS[0], wheel_mac(status="FAIL"), wheel_win(in1=72.0))
        self.assertFalse(ok)
        self.assertTrue(any("FAIL" in p for p in probs), probs)

    def test_missing_windows_line_fails(self):
        ok, probs = judge(WHEEL_PAIRS[0], wheel_mac(), wheel_win(in1=72.0)[:1])   # no in1
        self.assertFalse(ok)
        self.assertTrue(any("no WIN_SCROLL" in p for p in probs), probs)

    def test_missing_mac_line_fails(self):
        ok, probs = judge({"mac": "w7", "win": "in1", "perLine": True, "macLines": 3, "winLines": 3}, wheel_mac(), wheel_win(in1=72.0))
        self.assertFalse(ok)
        self.assertTrue(any("no MAC_SCROLL" in p for p in probs), probs)

    def test_incomplete_windows_reading_fails(self):
        bad = [l.replace("contentHeight=212.000 ", "") for l in wheel_win(in1=72.0)]
        ok, probs = judge(WHEEL_PAIRS[0], wheel_mac(), bad)
        self.assertFalse(ok)
        self.assertTrue(any("incomplete" in p for p in probs), probs)

    def test_unparsable_number_fails(self):
        bad = [l.replace("offset=72.000", "offset=abc") for l in wheel_win(in1=72.0)]
        ok, probs = judge(WHEEL_PAIRS[0], wheel_mac(), bad)
        self.assertFalse(ok)

    def test_no_first_label_fails(self):
        m = wheel_mac()
        w = wheel_win(in1=72.0)
        ok, probs = psr.judge(WHEEL_PAIRS[0], psr.mac_reading(m, "w3"), psr.win_reading(w, "in1"), None, TOL)
        self.assertFalse(ok)
        self.assertTrue(any("rest offset unknown" in p for p in probs), probs)


class LastLineWins(unittest.TestCase):
    def test_mac_group_takes_the_last_line_of_the_label(self):
        lines = [mac_line("w3-reset", 0.2), mac_line("w3-wheel", 72.2), mac_line("w3-to", 10.0)]   # the group's settled reading is the last one
        self.assertEqual(psr.mac_reading(lines, "w3")["offset"], 10.0)

    def test_mac_label_prefix_does_not_match_a_longer_label(self):
        lines = [mac_line("w10-wheel", 240.0), mac_line("w1-wheel", 24.0)]
        self.assertEqual(psr.mac_reading(lines, "w1")["offset"], 24.0)
        self.assertIsNone(psr.mac_reading([mac_line("w10-wheel", 240.0)], "w1"))

    def test_windows_takes_the_last_line_of_the_input(self):
        lines = [win_line("in1", 60.0), win_line("in1", 72.0)]
        self.assertEqual(psr.win_reading(lines, "in1")["offset"], 72.0)

    def test_fields_first_occurrence_wins(self):
        d = psr.fields("label=w1-wheel status=OK offset=24.000 note=offset=99")
        self.assertEqual(d["offset"], "24.000")


class WholeRun(unittest.TestCase):
    """main() on a synthetic case and run directory: the report file and the exit code."""

    def run_gate(self, mac_text, win_text, pairs):
        with tempfile.TemporaryDirectory() as d:
            case, out = Path(d, "case"), Path(d, "run")
            case.mkdir(); (out / "windows").mkdir(parents=True)
            (case / "pair.json").write_text(json.dumps({"phaseShots": ["w0", "w1", "w3", "w10"], "scrollGate": {"pairs": pairs, "tolerancePt": TOL}}))
            (out / "mac-run-01.log").write_text(mac_text)
            (out / "windows" / "host-01.stdout.txt").write_text(win_text)
            r = subprocess.run([sys.executable, "-I", str(TOOLS / "pair_scroll_report.py"), str(case), str(out)], capture_output=True, text=True)
            rep = json.loads((out / "scroll-report.json").read_text())
            return r.returncode, rep, r.stdout

    def test_passing_run_exits_zero(self):
        code, rep, _ = self.run_gate("\n".join(wheel_mac()) + "\n", "\n".join(wheel_win(in1=72.0)) + "\n", WHEEL_PAIRS)
        self.assertEqual(code, 0)
        self.assertEqual((rep["runs"], rep["gatePassed"]), (1, 1))
        self.assertEqual([p["kind"] for p in rep["rows"][0]["pairs"]], ["perLine", "clamp"])

    def test_failing_pair_exits_nonzero(self):
        code, rep, out = self.run_gate("\n".join(wheel_mac()) + "\n", "\n".join(wheel_win(in1=60.0)) + "\n", WHEEL_PAIRS)
        self.assertEqual(code, 1)
        self.assertEqual(rep["gatePassed"], 0)
        self.assertIn("scroll-gate=0/1", out)

    def test_no_runs_exits_nonzero(self):
        with tempfile.TemporaryDirectory() as d:
            case, out = Path(d, "case"), Path(d, "run")
            case.mkdir(); out.mkdir()
            (case / "pair.json").write_text(json.dumps({"phaseShots": ["w0"], "scrollGate": {"pairs": WHEEL_PAIRS}}))
            r = subprocess.run([sys.executable, "-I", str(TOOLS / "pair_scroll_report.py"), str(case), str(out)], capture_output=True, text=True)
            self.assertEqual(r.returncode, 1)

    def test_missing_windows_host_file_fails_the_run(self):
        with tempfile.TemporaryDirectory() as d:
            case, out = Path(d, "case"), Path(d, "run")
            case.mkdir(); out.mkdir()
            (case / "pair.json").write_text(json.dumps({"phaseShots": ["w0"], "scrollGate": {"pairs": WHEEL_PAIRS}}))
            (out / "mac-run-01.log").write_text("\n".join(wheel_mac()) + "\n")
            r = subprocess.run([sys.executable, "-I", str(TOOLS / "pair_scroll_report.py"), str(case), str(out)], capture_output=True, text=True)
            self.assertEqual(r.returncode, 1)
            rep = json.loads((out / "scroll-report.json").read_text())
            self.assertIn("missing windows/host-NN.stdout.txt", rep["rows"][0]["problems"])

    def test_empty_pairs_fails_closed(self):
        code, rep, _ = self.run_gate("\n".join(wheel_mac()) + "\n", "\n".join(wheel_win(in1=72.0)) + "\n", [])
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
