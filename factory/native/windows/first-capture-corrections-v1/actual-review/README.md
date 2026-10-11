# Corrected Windows first-capture independent review

`report.json` records offline verification of `actual-corrected-r1` plus original `actual-first-r1` and matched Mac summary-20 lineage. `review.py` replays hash, source, executable, process, HWND, viewport, UIA, text-log and PNG joins without rerunning compiler, GUI, SSH or Pulse. Seven raw-input mutations changed source, viewport, PID, visual hash, UIA text or logs and were rejected.

Verdict: `VERIFIED-CORRECTED-SOURCE-BOUND-OBSERVATION-PARITY-HELD`. Corrected run has 26 files / 230373 bytes; compile exit is 0, native capture exit is 0, client readback is 800x600 at dpi 240 / scale 2.5, UIA Continue is 160x60, and retained text logs contain 606 measured/committed runs. Foreground changes 395622 to 0, print/screen repeats are stable but differ, natural occlusion is uncontrolled, provider readback is absent, and parity remains held.

`root-stage-manifest.json` remains complete for its 80 listed files/dependencies. Corrected actual-run/build trees are supplemental and are independently pinned in `report.json`; original evidence remains immutable.
