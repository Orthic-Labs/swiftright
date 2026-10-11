# Fresh F5 Mac origin producer controls

Source-only contract for `factory/native/macos/capture.py`, `normalize.py`, `check_evidence.py` & pure fixture controls. No native/compiler execution is represented here.

Producer writes `compiler-receipt.json` before returning from every fresh host build. Receipt binds resolver/compiler argv, cwd, PID/PGID, UTC start/end, exit, owned-group cleanup, stdout/stderr bytes, source-before/after, resolved tool-before/after, `/usr/bin/xcrun` hash & output binary. Any resolve/build/tool/source/output persistence failure aborts item; it cannot emit qualified `capture.json`.

Each normalized run writes `meta.conditions.macOrigin` with exact `captureId`, case, Witness source, generated CaptureHost source, binary & receipt refs. `origin-summary.json` is immutable summary snapshot used by descriptor; final mutable `summary.json` retains existing run/capture hashes. Existing F1 recorder, fresh AX preflight, internal cache confinement, candidate policy & no-TCC path remain unchanged.

`check_evidence.verify` requires descriptor refs, exact bytes/hashes, candidate summary joins, SUCCESS receipt/sourceDrift false, binary output join & auxiliary AX refs when fresh AX says AVAILABLE. Historical captures are not rewritten.
