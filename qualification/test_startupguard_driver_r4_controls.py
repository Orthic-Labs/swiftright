#!/usr/bin/env python3
"""Pure source controls for tuple12 driver r4 foreground observation baseline."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
R3 = ROOT / "probes/sr0-s/fresh-on-bridge/scripts/tuple12-startupguard-smoke-v1/drive-fixture-noactivate-focus-r3.ps1"
R4 = ROOT / "probes/sr0-s/fresh-on-bridge/scripts/tuple12-startupguard-smoke-v1/drive-fixture-noactivate-focus-r4.ps1"

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def fail(name):
    raise SystemExit(f"R4_CONTROLS_FAIL {name}")

def main():
    r3, r4 = R3.read_text(encoding="utf-8"), R4.read_text(encoding="utf-8")
    if r3 == r4:
        fail("overlay-missing")
    expected = [
        "# Establish observation baseline before first targeted sample; later transitions remain fail-visible.",
        'if ($rendererReadyValid -and $hwnd -ne [IntPtr]::Zero)',
        '$script:lastFg = [SW.N]::GetForegroundWindow()',
        'Log \"fg_baseline hwnd=$($script:lastFg.ToInt64()) target=$($hwnd.ToInt64())\"',
        '$script:fgChanges++',
        'Sample-Fg \"key-$vk\"',
        'fg_before=$($fgBefore.ToInt64())',
        'fg_after=$(([SW.N]::GetForegroundWindow()).ToInt64())',
    ]
    for needle in expected:
        if needle not in r4:
            fail(f"missing:{needle}")
    marker = r4.index("# Establish observation baseline")
    target = r4.index("$script:targetInvalid")
    sample = r4.index("function Sample-Fg")
    if not marker < target < sample:
        fail("baseline-order")
    # Targeted path must retain observation only; foreground acquisition remains global-only.
    targeted = r4[r4.index("function Type-Key("):r4.index("# Global path")]
    if "Ensure-Foreground" in targeted or "SetForegroundWindow" in targeted:
        fail("targeted-foreground-acquire")
    if "Sample-Fg" not in targeted or "fg_before=" not in targeted or "fg_after=" not in targeted:
        fail("targeted-observation")
    if "$script:lastFg = [IntPtr]::Zero" not in r4:
        fail("zero-initial-state-missing")
    # Fault controls model regressions: baseline erased, transition counter erased, targeted trace erased.
    faults = {
        "baseline-erased": r4.replace('$script:lastFg = [SW.N]::GetForegroundWindow()', '$script:lastFg = [IntPtr]::Zero', 1),
        "transition-counter-erased": r4.replace('$script:fgChanges++', '$script:fgChanges = 0', 1),
        "targeted-before-erased": targeted.replace('fg_before=$($fgBefore.ToInt64())', 'fg_before=removed', 1),
    }
    checks = {
        "baseline-erased": ('$script:lastFg = [SW.N]::GetForegroundWindow()' in faults["baseline-erased"]),
        "transition-counter-erased": ('$script:fgChanges++' in faults["transition-counter-erased"]),
        "targeted-before-erased": ('fg_before=$($fgBefore.ToInt64())' in faults["targeted-before-erased"]),
    }
    if any(checks.values()):
        fail("fault-controls:" + ",".join(k for k,v in checks.items() if v))
    print({
        "kind": "sr0-startupguard-driver-r4-controls-v1",
        "status": "passed",
        "baseR3": sha(R3),
        "overlayR4": sha(R4),
        "positive": len(expected) + 4,
        "faults": list(faults),
    })

if __name__ == "__main__":
    main()
