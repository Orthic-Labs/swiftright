#!/usr/bin/env python3
"""Pure source controls for F3 ready-file timing diagnosis; no native execution."""
from pathlib import Path
import hashlib
import difflib

ROOT = Path(__file__).resolve().parents[1]
R5 = ROOT / "probes/sr0-s/fresh-on-bridge/scripts/tuple12-startupguard-smoke-v1/drive-fixture-noactivate-focus-r5.ps1"
R6 = ROOT / "qualification/tuple12-takeover/f3-ready-diagnosis-v1/drive-fixture-noactivate-focus-r6-diagnostic.ps1"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(name: str) -> None:
    raise SystemExit("F3_READY_DIAG_CONTROLS_FAIL " + name)


def valid_source(source: str) -> bool:
    required = [
        '$rendererReadyWait.ElapsedMilliseconds -lt 45000',
        'if (-not (Test-Path -LiteralPath $rendererReadyFile)) { throw "renderer-ready file missing" }',
        '$readySeenMs = $rendererReadyWait.ElapsedMilliseconds',
        '$readyReadWatch = [Diagnostics.Stopwatch]::StartNew()',
        '$readyRaw = [IO.File]::ReadAllText($rendererReadyFile)',
        '$readyReadMs = $readyReadWatch.ElapsedMilliseconds',
        'renderer_ready_file_seen_ms=',
        'renderer_ready_event=',
        'renderer_window_revalidate=FAIL',
        '$hwnd = [IntPtr]::Zero',
        '$rendererReadyValid = $false',
        'if (-not $rendererReadyValid) { throw \'renderer-ready record identity/phase mismatch\' }',
    ]
    if any(item not in source for item in required):
        return False
    fail_closed = "    $hwnd = [IntPtr]::Zero\n    $rendererReadyValid = $false"
    if fail_closed not in source:
        return False
    order = [
        '$readySeenMs = $rendererReadyWait.ElapsedMilliseconds',
        '$readyReadWatch = [Diagnostics.Stopwatch]::StartNew()',
        '$readyRaw = [IO.File]::ReadAllText($rendererReadyFile)',
        '$readyReadMs = $readyReadWatch.ElapsedMilliseconds',
        'renderer_ready_file_seen_ms=',
        '$readyRecord = $readyRaw | ConvertFrom-Json',
        'renderer_ready_event=',
    ]
    positions = [source.index(item) for item in order]
    return positions == sorted(positions)


def main() -> None:
    if not R5.is_file() or not R6.is_file():
        fail("source-missing")
    r5, r6 = R5.read_text(encoding="utf-8"), R6.read_text(encoding="utf-8")
    if not valid_source(r6):
        fail("positive-source")
    if valid_source(r5):
        fail("base-unexpectedly-diagnostic")

    # Overlay must only add timing around existing synchronous read/parse. Any other
    # source drift invalidates this diagnostic pin and requires fresh review.
    diff = list(difflib.unified_diff(r5.splitlines(), r6.splitlines(), n=0))
    changed = [line for line in diff if line.startswith(("+", "-")) and not line.startswith(("+++", "---"))]
    expected_additions = {
        "+    $readySeenMs = $rendererReadyWait.ElapsedMilliseconds",
        "+    $readyReadWatch = [Diagnostics.Stopwatch]::StartNew()",
        "+    $readyReadMs = $readyReadWatch.ElapsedMilliseconds",
        '+    Log "renderer_ready_file_seen_ms=$readySeenMs read_ms=$readyReadMs bytes=$([Text.Encoding]::UTF8.GetByteCount($readyRaw))"',
    }
    if set(changed) != expected_additions:
        fail("overlay-drift:" + repr(changed))

    # Fault controls: timing evidence missing, or fail-closed revalidation weakened,
    # must both reject candidate source.
    faults = {
        "missing-read-timing": r6.replace("    $readyReadMs = $readyReadWatch.ElapsedMilliseconds\n", "", 1),
        "revalidation-open": r6.replace("    $hwnd = [IntPtr]::Zero\n    $rendererReadyValid = $false", "    $hwnd = [IntPtr]::Zero\n    $rendererReadyValid = $true", 1),
        "ready-identity-open": r6.replace("    if (-not $rendererReadyValid) { throw 'renderer-ready record identity/phase mismatch' }", "    # identity check removed", 1),
    }
    for name, source in faults.items():
        if valid_source(source):
            fail("fault-accepted:" + name)

    print({
        "kind": "sr0-f3-ready-diagnosis-controls-v1",
        "status": "passed",
        "baseR5": sha(R5),
        "overlayR6": sha(R6),
        "changedLines": len(changed),
        "faults": list(faults),
    })


if __name__ == "__main__":
    main()
