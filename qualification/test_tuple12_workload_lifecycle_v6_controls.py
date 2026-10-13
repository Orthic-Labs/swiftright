#!/usr/bin/env python3
"""Source + helper controls for tuple12 Workload lifecycle v6."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
RUN = ROOT / "qualification/tuple12-takeover/workload-controls-v6/run-workload.ps1"
TASK = ROOT / "qualification/tuple12-takeover/workload-controls-v6/task-workload.ps1"


def fail(label, reason):
    raise AssertionError(f"{label}: {reason}")


def signed_dword(raw: int) -> int:
    return raw - 2**32 if raw > 2**31 - 1 else raw


def terminal_line_proof(line: str, raw_field="kernel_exit_raw", signed_field="kernel_exit", dotnet_field="dotnet_exit") -> bool:
    m = re.search(rf"{raw_field}=(\d+) {signed_field}=(-?\d+) {dotnet_field}=(-?\d+)", line)
    if not m:
        return False
    raw, signed, dotnet = map(int, m.groups())
    return raw != 259 and signed == signed_dword(raw) and signed == dotnet


def semantic_model(text: str, root: Path) -> bool:
    ids = re.findall(r"^=== RUN ([\w.-]+) start=", text, re.M)
    if len(ids) != 3:
        return False
    for ident in ids:
        if not re.search(rf"^run_state id={re.escape(ident)} valid=1 reason=ok$", text, re.M):
            return False
        if not re.search(rf"^background_noactivate run={re.escape(ident)} result=PASS startup_activation=guarded", text, re.M):
            return False
        if not re.search(rf"^host_startup_guard run={re.escape(ident)} result=PASS arg=--sr0-noactivate$", text, re.M):
            return False
        out = root / ident / "stdout.txt"
        if not out.is_file():
            return False
        value = out.read_text()
        if "WORKLOAD-WIN-DONE" not in value or not re.search(r"aborted\s*=\s*false", value, re.I) or re.search(r"aborted\s*=\s*true", value, re.I):
            return False
    return True


def source_positive(run: str, task: str):
    for needle in (
        "function Invoke-Logman([string[]]$arguments)",
        "function Stop-UniquePresentMonSession",
        "logman.exe",
        "session_absent=$pmSessionAbsent",
        "$script:pmSessionAbsent=$true",
        "public static long SignedDword(uint code)",
        "$pmKernelExitRaw=[uint64]$pmKernelExit",
        "$pmKernelExitSigned=[Sr0Tuple12PresentMonKernel]::SignedDword($pmKernelExit)",
        "session_stop_exit=$pmSessionStopExit",
    ):
        if needle not in run:
            fail("run-positive", needle)
    for needle in (
        "[switch]$NoActivate",
        "--sr0-noactivate",
        "if ($NoActivate -and $psi.Arguments -notmatch",
        "pid run=$id pid=$($proc.Id) handle=$workerHandle",
        "kernel_exit_raw=$kernelCode kernel_exit=$kernelCodeSigned dotnet_exit=$dotnetExit",
        "sampler_kernel_exit_raw=$samplerKernelCode sampler_kernel_exit=$samplerKernelCodeSigned sampler_dotnet_exit=$samplerDotnetExit",
        "background_noactivate run=$id result=$backgroundNoActivate startup_activation=guarded",
        "if ($NoActivate) {",
        "[Inj]::Acquire($hwnd",
    ):
        if needle not in task:
            fail("task-positive", needle)
    # Acquire must remain exclusively inside non-NoActivate branch.
    start = task.index("if ($NoActivate) {\n      $backgroundNoActivate")
    branch = task[start:task.index("} else {", start)]
    if "[Inj]::Acquire($hwnd" in branch:
        fail("task-positive", "foreground API reachable from NoActivate branch")


def helper_controls():
    good = "pid_exit run=r1 handle=7 kernel_terminal=1 kernel_exit_raw=4294967295 kernel_exit=-1 dotnet_exit=-1"
    if not terminal_line_proof(good):
        fail("helper-positive", "signed DWORD terminal proof")
    cases = {
        "raw-259": good.replace("4294967295 kernel_exit=-1", "259 kernel_exit=259"),
        "signed-mismatch": good.replace("kernel_exit=-1", "kernel_exit=4294967295"),
        "missing-raw": good.replace("kernel_exit_raw=4294967295 ", ""),
    }
    for label, value in cases.items():
        if terminal_line_proof(value):
            fail("helper-fault", label)

    import tempfile
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        rows = []
        for ident in ("r1", "r2", "r3"):
            rows += [f"=== RUN {ident} start=now", f"run_state id={ident} valid=1 reason=ok", f"background_noactivate run={ident} result=PASS startup_activation=guarded", f"host_startup_guard run={ident} result=PASS arg=--sr0-noactivate"]
            run = root / ident
            run.mkdir()
            (run / "stdout.txt").write_text("WORKLOAD-WIN-DONE aborted=false\n")
        good = "\n".join(rows)
        if not semantic_model(good, root):
            fail("semantic-positive", "3-run guarded receipt")
        (root / "r1" / "stdout.txt").write_text("WORKLOAD-WIN-DONE aborted=true\n")
        if semantic_model(good, root):
            fail("semantic-fault", "aborted run accepted")
        (root / "r1" / "stdout.txt").write_text("WORKLOAD-WIN-DONE aborted=false\n")
        if semantic_model(good.replace("result=PASS", "result=not-requested", 1), root):
            fail("semantic-fault", "noactivate guard missing accepted")
        if semantic_model(good.replace("run_state id=r3 valid=1", "run_state id=r3 valid=0", 1), root):
            fail("semantic-fault", "invalid run accepted")


def main():
    run, task = RUN.read_text(), TASK.read_text()
    source_positive(run, task)
    helper_controls()
    print("tuple12 workload lifecycle v6 controls: PASS source + signed-exit/session/semantic helper controls")
    print("run_sha256=" + hashlib.sha256(RUN.read_bytes()).hexdigest())
    print("task_sha256=" + hashlib.sha256(TASK.read_bytes()).hexdigest())
    print("controls_sha256=" + hashlib.sha256(Path(__file__).read_bytes()).hexdigest())


if __name__ == "__main__":
    raise SystemExit(main())
