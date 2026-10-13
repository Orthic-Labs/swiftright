#!/usr/bin/env python3
"""Pure source controls for tuple12 Workload lifecycle controls v3."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
V3 = ROOT / "qualification/tuple12-takeover/workload-controls-v3"
RUN = V3 / "run-workload.ps1"
TASK = V3 / "task-workload.ps1"
VERIFY = V3 / "verify-artifacts.ps1"
SAMPLER = V3 / "sample-resources.ps1"
PINS = V3 / "source-pins.json"


def fail(label, reason):
    raise AssertionError(f"{label}: {reason}")


def positive(run, task, verify, sampler):
    run_needles = (
        "[string]$ControlRoot = ''",
        "[string]$AnalysisRoot = ''",
        "$controlRoot = if ($ControlRoot)",
        "$analysis = if ($AnalysisRoot)",
        "$scripts  = $controlRoot",
        "-ControlRoot `\"$controlRoot`\"",
        '"$analysis\\analyze_workload.py"',
        "[switch]$LifecycleProof",
        "[switch]$NoActivate",
        "$pmSession = \"SR0BWL-$Tag\"",
        "New-Object System.Diagnostics.ProcessStartInfo",
        "$pmProc = [System.Diagnostics.Process]::Start($pmPsi)",
        "$pmHandle = $pmProc.Handle",
        "$pmStdout = $pmProc.StandardOutput.ReadToEndAsync()",
        "$pmStderr = $pmProc.StandardError.ReadToEndAsync()",
        "$pmProc.WaitForExit(60000)",
        "$pmProc.Kill()",
        "$pmProc.WaitForExit(15000)",
        "$pmStdout.Wait(15000)",
        "$pmStderr.Wait(15000)",
        "--session_name",
        "--terminate_after_timed",
        "fresh run root",
        "$analysisRc = $LASTEXITCODE",
        "if ($LifecycleProof) { exit $analysisRc }",
    )
    for needle in run_needles:
        if needle not in run:
            fail("run-positive", needle)
    forbidden_run = (
        "Start-Process -FilePath $pmExe",
        "--terminate_existing_session",
        "Get-Process -Name 'PresentMon-2.6.0-x64'",
    )
    for needle in forbidden_run:
        if needle in run:
            fail("run-forbidden", needle)
    if "`$analysisRc" in run or "`$LifecycleProof" in run:
        fail("run-positive", "literal backtick before PowerShell variable")
    if "else { \"$Base\\probes\\sr0-b\\workload\\scripts\" }" not in run:
        fail("run-default", "default control root path changed")
    if "else { \"$Base\\probes\\sr0-b\\workload\\analysis\" }" not in run:
        fail("run-default", "default analysis root path changed")
    if "Register-ScheduledTask -TaskName $taskName -Action $act -Principal $pri -Settings $set -Force" not in run:
        fail("run-default", "legacy -Force branch disappeared")

    task_needles = (
        "[string]$ControlRoot = ''",
        "$controlRoot = if ($ControlRoot)",
        '`"$controlRoot\\sample-resources.ps1`"',
        "[switch]$LifecycleProof",
        "BottomNoActivate",
        "WindowPid(hwnd) != pid",
        "static extern bool GetExitCodeProcess",
        "GetExitCodeProcess(h, out code)",
        "return code != 259",
        "($kernelCode -eq $dotnetExit)",
        "($samplerKernelCode -eq $samplerDotnetExit)",
        "$proc.WaitForExit(15000)",
        "$sampler.WaitForExit(15000)",
        "$so.Wait(15000)",
        "$se.Wait(15000)",
        "$samplerErr.Wait(15000)",
        "worker_terminal=$([int]$workerTerminalAll)",
        "sampler_terminal=$([int]$samplerTerminalAll)",
        "task_quiescent=$([int]($workerTerminalAll -and $samplerTerminalAll))",
        "window-owner-mismatch",
        "startup_activation=guarded",
        "$samplerTerminalAll = [bool]$NoResources",
        "catch { $samplerTerminalAll = $false;",
    )
    for needle in task_needles:
        if needle not in task:
            fail("task-positive", needle)
    if task.count("static extern uint GetWindowThreadProcessId") != 1:
        fail("task-positive", "GetWindowThreadProcessId declaration count is not one")
    if ".Result" not in task:
        fail("task-positive", "completed async results absent")

    if "param(" not in verify or "Get-FileHash -Algorithm SHA256" not in verify:
        fail("verify-positive", "artifact hash gate absent")
    if "param(" not in sampler or "resources.csv" not in sampler:
        fail("sampler-positive", "sampler source absent")


def main():
    run = RUN.read_text(encoding="utf-8")
    task = TASK.read_text(encoding="utf-8")
    verify = VERIFY.read_text(encoding="utf-8")
    sampler = SAMPLER.read_text(encoding="utf-8")
    pins = json.loads(PINS.read_text(encoding="utf-8"))
    expected = pins["overlay_source"]
    for key, path in (("run_workload_sha256", RUN), ("task_workload_sha256", TASK),
                      ("verify_artifacts_sha256", VERIFY), ("sample_resources_sha256", SAMPLER)):
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected[key]:
            fail("pin", f"{key}: {actual} != {expected[key]}")
    positive(run, task, verify, sampler)
    mutations = (
        ("duplicate-pinvoke", lambda r, t: (r, t.replace("    public static int WindowPid", "    [DllImport(\"user32.dll\")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);\n    public static int WindowPid", 1))),
        ("remove-actual-window-helper", lambda r, t: (r, t.replace("WindowPid(hwnd) != pid", "true", 1))),
        ("remove-native-terminal", lambda r, t: (r, t.replace("static extern bool GetExitCodeProcess", "static extern bool NO_NATIVE_TERMINAL", 1).replace("GetExitCodeProcess(h, out code)", "NO_NATIVE_TERMINAL(h, out code)", 1))),
        ("remove-still-active-check", lambda r, t: (r, t.replace("return code != 259", "return true", 1))),
        ("remove-sampler-start-failure", lambda r, t: (r, t.replace("catch { $samplerTerminalAll = $false;", "catch { $samplerTerminalAll = $true;", 1))),
        ("remove-unique-session", lambda r, t: (r.replace("$pmSession = \"SR0BWL-$Tag\"", "$pmSession = \"PresentMon\"", 1), t)),
        ("remove-owned-pm-handle", lambda r, t: (r.replace("$pmHandle = $pmProc.Handle", "$pmHandle = [IntPtr]::Zero", 1), t)),
        ("remove-control-root", lambda r, t: (r.replace("$scripts  = $controlRoot", "$scripts  = $Base", 1), t)),
        ("remove-analysis-root", lambda r, t: (r.replace("$analysis = if ($AnalysisRoot)", "$analysis = $Base #", 1), t)),
    )
    caught = []
    for label, mutate in mutations:
        mr, mt = mutate(run, task)
        try:
            positive(mr, mt, verify, sampler)
        except AssertionError:
            caught.append(label)
    if len(caught) != len(mutations):
        fail("fault-controls", f"caught {caught}")
    print("tuple12 workload lifecycle v3 controls: PASS positive + 9 mutation faults")
    print("run_sha256=" + hashlib.sha256(RUN.read_bytes()).hexdigest())
    print("task_sha256=" + hashlib.sha256(TASK.read_bytes()).hexdigest())
    print("verify_sha256=" + hashlib.sha256(VERIFY.read_bytes()).hexdigest())
    print("sampler_sha256=" + hashlib.sha256(SAMPLER.read_bytes()).hexdigest())


if __name__ == "__main__":
    raise SystemExit(main())
