# Tuple 13 Windows cross recordings x20 and Mac cross-compare (19 Oct 2026)

Windows Sandbox on the Dell (`ctl/cross.wsb`, vGPU off, networking off). FreshOnBridge `87b8cb27…`, renderer `1aa8ad22…` (tuple 13: stage a9556b77f + TextCache byte budget, #34), UIARecorder `41c94100…` (foreground check + focus settle). All 320 runs rc=0 and record those three hashes (`out/run-*.log`).

Compare against the host-Mac x20 references (`../tuple12-mac20-host-r1/`, Mac side unchanged by the renderer): **320/320 pairs pass** with each config's `adapt-v0.json` (`xcmp13.log`, reports in `xcmp13.tar.gz`). run.py compare stage on run 1 of each config: 16/16 with all negative controls rejected.
