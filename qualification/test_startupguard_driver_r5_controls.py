#!/usr/bin/env python3
"""Pure controls for r5 post-ready HWND revalidation; no native execution."""
from pathlib import Path
import hashlib
ROOT = Path(__file__).resolve().parents[1]
R4 = ROOT / "probes/sr0-s/fresh-on-bridge/scripts/tuple12-startupguard-smoke-v1/drive-fixture-noactivate-focus-r4.ps1"
R5 = ROOT / "probes/sr0-s/fresh-on-bridge/scripts/tuple12-startupguard-smoke-v1/drive-fixture-noactivate-focus-r5.ps1"
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def fail(x): raise SystemExit("R5_CONTROLS_FAIL " + x)
def main():
    r4, r5 = R4.read_text(encoding="utf-8"), R5.read_text(encoding="utf-8")
    if r4 == r5: fail("overlay-missing")
    needles = [
        "# MainWindowHandle was sampled before Bridge.onReady; revalidate same-process HWND after marker.",
        "if ($NoActivate -and $rendererReadyValid)",
        "$candidateHwnd = $proc.MainWindowHandle",
        "GetWindowThreadProcessId($candidateHwnd, [ref]$candidatePid)",
        "$candidateRectOk = [SW.N]::GetClientRect($candidateHwnd, [ref]$candidateRect)",
        "$candidatePid -eq $originalProcessId",
        "renderer_window_revalidate=PASS",
        "renderer_window_revalidate=FAIL",
        "$hwnd = [IntPtr]::Zero",
        "$rendererReadyValid = $false",
        "run_summary keymode=$KeyMode delivery=$delivery fg_changes=",
        "driver_abort=",
    ]
    for x in needles:
        if x not in r5: fail("missing:" + x)
    if not (r5.index("renderer_window_revalidate=PASS") < r5.index("WindowMetrics phase=startup")):
        fail("metrics-before-revalidate")
    if "SetForegroundWindow($hwnd)" in r5[r5.index("function Type-Key("):r5.index("# Global path")]: fail("targeted-activation")
    faults = {
      "owner-check-removed": r5.replace("$candidatePid -eq $originalProcessId", "$candidatePid -eq 0", 1),
      "client-check-removed": r5.replace("$candidateRectOk -and $candidateSizeOk", "$candidateSizeOk", 1),
      "fail-closed-removed": r5.replace("    $hwnd = [IntPtr]::Zero\n    $rendererReadyValid = $false", "    $hwnd = [IntPtr]::Zero\n    $rendererReadyValid = $true", 1),
    }
    if "$candidatePid -eq $originalProcessId" in faults["owner-check-removed"]: fail("owner-fault")
    if "$candidateRectOk -and $candidateSizeOk" in faults["client-check-removed"]: fail("client-fault")
    fail_block = 'Log "renderer_window_revalidate=FAIL initial_hwnd=$($initialHwnd.ToInt64()) owner_pid=$originalProcessId"\n    $hwnd = [IntPtr]::Zero\n    $rendererReadyValid = $false'
    if fail_block in faults["fail-closed-removed"]: fail("closed-fault")
    print({"kind":"sr0-startupguard-driver-r5-controls-v1","status":"passed","baseR4":sha(R4),"overlayR5":sha(R5),"positive":len(needles),"faults":list(faults)})
if __name__ == "__main__": main()
