#!/usr/bin/env python3
"""Pure positive/fault controls for strict F1 pair assembler."""
from copy import deepcopy
from pathlib import Path
import importlib.util
import json
import tempfile

SPEC = importlib.util.spec_from_file_location("pair", Path(__file__).with_name("assemble-tuple12-f1-paired.py"))
PAIR = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(PAIR)

def mac_report():
    rows = [{"case": f"n{i}", "rawSha256": "a"*64, "traceSha256": "b"*64} for i in range(1,21)]
    return {"status":"qualified","fixture":"F1","requiredRuns":20,"observedRuns":20,"passedRuns":20,"failures":[],"runs":rows,"candidate":{"sourceCommit":PAIR.PRODUCT},"joins":{"capture":{"sourceCommit":PAIR.SOURCE,"inputs":{"F1MacRecord":[PAIR.RECORDER,146992],"F1Assemble":[PAIR.ASSEMBLER,350632]}},"fixture":{"sha256":PAIR.FIXTURE}},"macPlans":{"stepsSha256":PAIR.STEPS,"stimulusSha256":PAIR.STIMULUS}}

def win_report():
    rows = [{"run": i, "receiptSha256":"a"*64, "traceSha256":"b"*64} for i in range(1,21)]
    return {"status":"qualified","fixture":"F1","requiredRuns":20,"observedRuns":20,"passedRuns":20,"failures":[],"runs":rows,"source":{"commit":PAIR.SOURCE,"manifestSha256":"f45b9e0dab99428194946341b0170f0e3beed874f9f552d01fd9046f3200b7ca","paths":{"driver":{"path":"D:\\stage\\drive-fixture-noactivate-focus-r4.ps1"},"worker":{"path":"D:\\stage\\worker-v3.ps1"},"coordinator":{"path":"D:\\stage\\coordinator-v3.ps1"}}},"artifacts":{"driver":PAIR.DRIVER,"exe":PAIR.EXE,"renderer":PAIR.RENDERER}}

def mac_trace():
    model = {"row/F0000001-0000-4000-8000-000000000005":"Row 5abcd","row/F0000001-0000-4000-8000-000000000099":"Engine 0"}
    obs = [{"stepId":x,"focusedNodeId":"row/F0000001-0000-4000-8000-000000000005/field","model":model} for x in PAIR.STEP_IDS]
    return {"fixtureId":"F1","sourceHash":"sha256:"+PAIR.STIMULUS,"steps":[{"id":x} for x in PAIR.STEP_IDS],"observations":obs}

def win_trace():
    return "\n".join(["SELFTEST F1: PASS (17/17", "ASSERT F1 focus-stays-row5: PASS", "ASSERT F1 row5-text: PASS", "ASSERT F1 ax-focus-delivered: PASS", "driver_abort=none", "run_summary keymode=char delivery=targeted fg_changes=0"])

def main():
    with tempfile.TemporaryDirectory(prefix="sr0-f1-pair-controls-") as td:
        root = Path(td); mac = root/"mac"; win = root/"win"; mac.mkdir(); win.mkdir()
        for i in range(1,21):
            (mac/f"mac-trace-n{i}.json").write_text(json.dumps(mac_trace()), encoding="utf-8")
            case = win/f"F1-r{i}-{'a'*32}"; (case/"nested").mkdir(parents=True)
            (case/"nested"/"driver-trace.txt").write_text(win_trace(), encoding="utf-8")
        PAIR.check_mac(mac_report()); PAIR.check_windows(win_report()); PAIR.check_mac_root(mac); PAIR.check_windows_root(win)
        faults = []
        mutated = mac_report(); mutated["macPlans"]["stimulusSha256"] = "c"*64
        try: PAIR.check_mac(mutated)
        except ValueError: faults.append("mac-stimulus")
        mutated = win_report(); mutated["artifacts"]["driver"] = "d"*64
        try: PAIR.check_windows(mutated)
        except ValueError: faults.append("windows-driver")
        (mac/"mac-trace-n20.json").write_text(json.dumps({"fixtureId":"F1"}), encoding="utf-8")
        try: PAIR.check_mac_root(mac)
        except ValueError: faults.append("mac-trace")
        (case/"nested"/"driver-trace.txt").write_text(win_trace().replace("fg_changes=0","fg_changes=1"), encoding="utf-8")
        try: PAIR.check_windows_root(win)
        except ValueError: faults.append("windows-foreground")
        if faults != ["mac-stimulus","windows-driver","mac-trace","windows-foreground"]:
            raise SystemExit(f"PAIR_CONTROLS_FAIL {faults}")
        print({"kind":"sr0-tuple12-f1-paired-controls-v1","status":"passed","positive":4,"faults":faults})

if __name__ == "__main__": raise SystemExit(main())
