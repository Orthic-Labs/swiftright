#!/usr/bin/env python3
"""Unit tests for pair_blocks_report: the gate writes block-gate.json into the run dir (python3 factory/tools/test_pair_blocks_report.py).
One synthetic run that passes (identical block rows) and one that fails (the Windows blue block moved 20 px right, far beyond the 1.5 px tolerance)."""
import json, subprocess, sys, tempfile, unittest
from pathlib import Path
from PIL import Image, ImageDraw

TOOL = Path(__file__).resolve().parent / "pair_blocks_report.py"
PAL = {"R": (255, 59, 48), "B": (0, 122, 255)}


def frame(shift_b=0):
    im = Image.new("RGB", (400, 100), (255, 255, 255)); d = ImageDraw.Draw(im)
    d.rectangle([20, 20, 120, 50], fill=PAL["R"])                       # 100 px red block
    d.rectangle([140 + shift_b, 20, 240 + shift_b, 50], fill=PAL["B"])  # 100 px blue block
    return im


def make_case(root, blocks):
    case = root / "case"; case.mkdir()
    (case / "pair.json").write_text(json.dumps({"blockGate": {"tolerancePx": 1.5, "cutTolerancePt": 9, "naturals": blocks}}))
    out = root / "run"; (out / "mac").mkdir(parents=True); (out / "windows").mkdir()
    frame().save(out / "mac" / "run-01.png")
    return case, out


class BlockGateVerdictFile(unittest.TestCase):
    def run_tool(self, case, out):
        return subprocess.run([sys.executable, str(TOOL), str(case), str(out)], capture_output=True, text=True)

    def test_passing_run_writes_pass_verdict(self):
        with tempfile.TemporaryDirectory() as tmp:
            case, out = make_case(Path(tmp), [])
            frame().save(out / "windows" / "native-01.png")
            r = self.run_tool(case, out)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
            doc = json.loads((out / "block-gate.json").read_text())
            self.assertTrue(doc["pass"]); self.assertEqual(doc["runs"], 1); self.assertTrue(doc["verdicts"][0]["ok"])

    def test_failing_run_writes_fail_verdict(self):
        with tempfile.TemporaryDirectory() as tmp:
            case, out = make_case(Path(tmp), [])
            frame(shift_b=20).save(out / "windows" / "native-01.png")
            r = self.run_tool(case, out)
            self.assertEqual(r.returncode, 1, r.stdout + r.stderr)
            doc = json.loads((out / "block-gate.json").read_text())
            self.assertFalse(doc["pass"]); self.assertFalse(doc["verdicts"][0]["ok"])
            self.assertTrue(any("block B" in p for p in doc["verdicts"][0]["problems"]))


if __name__ == "__main__":
    unittest.main()
