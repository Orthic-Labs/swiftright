#!/usr/bin/env python3
"""Pure source controls for tuple12 StartupGuard; no Swift, PowerShell, GUI, or native execution."""
from pathlib import Path
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "probes/sr0-s/fresh-on-bridge"
SWIFT = SRC / "Sources/FreshOnBridge"
FILES = {
    "guard": SWIFT / "StartupGuard.swift",
    "main": SWIFT / "main.swift",
    "fixture": SWIFT / "Fixture.swift",
    "driver": SRC / "scripts/drive-fixture.ps1",
}

def read(name):
    return FILES[name].read_text(encoding="utf-8")

def requirements(files):
    guard, main, fixture, driver = (files[k] for k in ("guard", "main", "fixture", "driver"))
    checks = {
        "guard-hooks-activate": "HCBT_ACTIVATE" in guard,
        "guard-hooks-focus": "HCBT_SETFOCUS" in guard,
        "guard-installs-thread-cbt": "SetWindowsHookExW" in guard and "GetCurrentThreadId" in guard,
        "guard-vetoes": "return 1" in guard and "CallNextHookEx" in guard,
        "guard-stops": "UnhookWindowsHookEx" in guard,
        "guard-lifetime-covers-run": "defer { startupGuard.stop() }" in main and main.index("defer { startupGuard.stop() }") < main.index("try bridge.run"),
        "guard-opt-in": "--sr0-noactivate" in fixture and "SR0ActivationGuard(enabled: options.noActivate)" in main,
        "ready-source": '"source": "Bridge.onReady"' in guard and '"phase": "first-ready"' in guard,
        "ready-exclusive-create": ".withoutOverwriting" in guard,
        "driver-marker-gate": "renderer_ready_event" in driver and "rendererReadyValid" in driver,
        "driver-identity-gate": "Assert-Target" in driver and "originalProcessHandle" in driver,
        "driver-noactivate-args": "--sr0-noactivate" in driver and "--renderer-ready-file" in driver,
    }
    return checks

def main():
    baseline = requirements({k: read(k) for k in FILES})
    if not all(baseline.values()):
        bad = [k for k, ok in baseline.items() if not ok]
        raise SystemExit("baseline failed: " + ",".join(bad))
    faults = []
    with tempfile.TemporaryDirectory(prefix="sr0-startupguard-controls-") as td:
        td = Path(td)
        for name, needle, replacement, expected in [
            ("focus-veto-removed", " || code == Int32(HCBT_SETFOCUS)", "", "guard-hooks-focus"),
            ("exclusive-create-removed", ".withoutOverwriting", "", "ready-exclusive-create"),
            ("lifetime-stop-early", "defer { startupGuard.stop() }", "startupGuard.stop()", "guard-lifetime-covers-run"),
        ]:
            copies = {k: read(k) for k in FILES}
            copies["guard"] = copies["guard"].replace(needle, replacement, 1) if name != "lifetime-stop-early" else copies["guard"]
            copies["main"] = copies["main"].replace(needle, replacement, 1) if name == "lifetime-stop-early" else copies["main"]
            checks = requirements(copies)
            faults.append({"name": name, "rejected": not checks[expected]})
    if not all(x["rejected"] for x in faults):
        raise SystemExit("fault control failed: " + repr(faults))
    print({"kind": "sr0-startupguard-source-controls-v1", "status": "passed", "positive": len(baseline), "faults": faults})

if __name__ == "__main__":
    main()
