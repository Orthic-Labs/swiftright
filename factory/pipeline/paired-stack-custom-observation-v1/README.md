# F9 paired stack & custom observation v1

`build_report.py` reconstructs report only from frozen Windows attempt bytes & exact 20-run Mac summaries. It verifies case hash, source hash, plan/runtime joins, raw file hashes, native capture fields & archive summary joins before writing `report.json` & `raw-pins.json`.

Windows stack failed before capture with raw `FACTORY_RENDER_ERROR ... Overlay`; UIA, PrintWindow, screen, shape & layout remain unavailable. Windows custom has one PrintWindow capture plus byte-stable repeat, one screen capture plus repeat, & root-only UIA with zero children; shape/layout/role/label/enabled semantics remain unavailable. Mac stack & custom archives each join exact case/source hashes & contain 20 runs; both are candidate-only & not promoted.

No native diff, parity, qualification, or golden is claimed. Run `PYTHONDONTWRITEBYTECODE=1 python3 build_report.py --fault-controls` for baseline acceptance plus source/case/raw/status mutation rejection.
