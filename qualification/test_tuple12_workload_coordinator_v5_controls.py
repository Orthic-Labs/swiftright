#!/usr/bin/env python3
"""Pure source + proof-helper controls for tuple12 coordinator v5."""
from pathlib import Path
import hashlib
import re

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "qualification/tuple12-takeover/workload-coordinator-v5/workload-coordinator.ps1"


def fail(label, reason):
    raise AssertionError(f"{label}: {reason}")


def signed(raw):
    return raw - 2**32 if raw > 2**31 - 1 else raw


def presentmon_proof(line):
    required = ("terminal=True", "kernel_terminal=True", "stop=forced-owned", "stdout_drained=True stderr_drained=True", "session_absent=True")
    if any(x not in line for x in required):
        return False
    m = re.search(r"kernel_exit_raw=(\d+) kernel_exit=(-?\d+) dotnet_exit=(-?\d+) exit=(-?\d+)", line)
    if not m:
        return False
    raw, kernel, dotnet, exit_code = map(int, m.groups())
    session_exit = re.search(r"session_stop_exit=(-?\d+)", line)
    return raw != 259 and kernel == signed(raw) == dotnet == exit_code and session_exit is not None


def semantic_proof(text, stdout):
    ids = re.findall(r"^=== RUN ([\w.-]+) start=", text, re.M)
    return len(ids) == 3 and all(
        re.search(rf"^run_state id={re.escape(i)} valid=1 reason=ok$", text, re.M)
        and re.search(rf"^background_noactivate run={re.escape(i)} result=PASS startup_activation=guarded", text, re.M)
        and re.search(rf"^host_startup_guard run={re.escape(i)} result=PASS arg=--sr0-noactivate$", text, re.M)
        for i in ids
    ) and all("WORKLOAD-WIN-DONE" in stdout[i] and "aborted=true" not in stdout[i] for i in ids)


def positive(s):
    required = (
        "function Signed-Dword([uint64]$raw)",
        "function Terminal-LineProof",
        "function Semantic-RunProof([string]$text,[string]$root)",
        "function Strict-RunProof([string]$text)",
        "function PresentMon-Proof([string]$text)",
        "session_stop_exit=-?[0-9]+ session_absent=True",
        "kernel_exit_raw=[0-9]+ kernel_exit=-?[0-9]+ dotnet_exit=-?[0-9]+",
        "sampler_kernel_exit_raw=[0-9]+ sampler_kernel_exit=-?[0-9]+ sampler_dotnet_exit=-?[0-9]+",
        "semanticRunProof=Semantic-RunProof $resultText $runRoot",
        "semanticRunProof=$semanticRunProof",
        "kind='sr0-tuple12-workload-coordinator-v5'",
        "[IO.FileMode]::CreateNew",
        "$releaseAllowed=($orchestratorTerminal -and $streamsDrained -and $taskQuiescent -and $cleanupProof -and $presentMonRelease)",
    )
    for n in required:
        if n not in s:
            fail("positive", n)
    for forbidden in ("Remove-Item", "Unregister-ScheduledTask", "Get-Process -Name"):
        if forbidden in s:
            fail("forbidden", forbidden)


def helper_controls():
    good = ("presentmon terminal=True kernel_terminal=True kernel_exit_raw=4294967295 kernel_exit=-1 "
            "dotnet_exit=-1 exit=-1 stop=forced-owned session=SR0BWL-r handle=7 "
            "stdout_drained=True stderr_drained=True session_stop_exit=0 session_absent=True")
    if not presentmon_proof(good):
        fail("helper-positive", "forced PM session proof")
    for label, bad in (
        ("session-still-present", good.replace("session_absent=True", "session_absent=False")),
        ("unsigned-kernel", good.replace("kernel_exit=-1", "kernel_exit=4294967295")),
        ("raw-sentinel", good.replace("kernel_exit_raw=4294967295 kernel_exit=-1", "kernel_exit_raw=259 kernel_exit=259")),
        ("missing-stop-exit", good.replace("session_stop_exit=0 ", "")),
    ):
        if presentmon_proof(bad):
            fail("helper-fault", label)
    text = "\n".join(f"=== RUN {i} start=x\nrun_state id={i} valid=1 reason=ok\nbackground_noactivate run={i} result=PASS startup_activation=guarded\nhost_startup_guard run={i} result=PASS arg=--sr0-noactivate" for i in ("r1", "r2", "r3"))
    stdout = {i: "WORKLOAD-WIN-DONE aborted=false" for i in ("r1", "r2", "r3")}
    if not semantic_proof(text, stdout):
        fail("semantic-positive", "three guarded runs")
    if semantic_proof(text.replace("result=PASS", "result=not-requested", 1), stdout):
        fail("semantic-fault", "missing noactivate guard")
    if semantic_proof(text, {**stdout, "r2": "WORKLOAD-WIN-DONE aborted=true"}):
        fail("semantic-fault", "aborted run")
    if semantic_proof(text.replace("valid=1", "valid=0", 1), stdout):
        fail("semantic-fault", "invalid run")


def main():
    s = SRC.read_text()
    positive(s)
    helper_controls()
    print("tuple12 workload coordinator v5 controls: PASS source + PM/session/semantic helper controls")
    print("source_sha256=" + hashlib.sha256(SRC.read_bytes()).hexdigest())
    print("controls_sha256=" + hashlib.sha256(Path(__file__).read_bytes()).hexdigest())


if __name__ == "__main__":
    raise SystemExit(main())
