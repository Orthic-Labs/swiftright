"""Deferred direct-SSH dispatcher for three Windows TaskID variants.

`preflight` is local-only. `upload` only installs fresh inputs. `run` requires
compilerbridge_review's explicit token and executes each focused test once.
"""
from __future__ import annotations
import argparse, base64, datetime as dt, hashlib, json, os, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
PLAN = HERE / "source-plan.json"
RUNNER = HERE / "run-three-variants.ps1"
REMOTE_INPUT = r"D:\Claude\factory-swiftright-taskid-three-input-20261011"
REMOTE_RUN = r"D:\Claude\factory-swiftright-taskid-three-run-20261011"
TOKEN = "RUN-NOW-PERFORMANCE-PAIR-COMPLETE"
VARIANTS = ("original", "retained", "terminal")


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def source_file(root: Path, rel: str) -> Path:
    p = (root / rel).resolve()
    if root.resolve() not in p.parents:
        raise ValueError(f"source path escapes root: {rel}")
    return p


def plan_data() -> dict:
    return json.loads(PLAN.read_text())


def validate_local() -> dict:
    plan = plan_data()
    if plan.get("schema") != "taskid-windows-three-variants-source-plan-v1":
        raise ValueError("source-plan schema mismatch")
    if tuple(v["name"] for v in plan["variants"]) != VARIANTS:
        raise ValueError("variant order mismatch")
    manifest_path = REPO / plan["sourceManifest"]["path"]
    if sha(manifest_path.read_bytes()) != plan["sourceManifest"]["sha256"]:
        raise ValueError("frozen source manifest drift")
    for v in plan["variants"]:
        root = REPO / v["localRoot"]
        expected = {b["path"]: b for b in v["bindings"]}
        actual = {}
        for p in root.rglob("*"):
            if not p.is_file():
                continue
            rel = p.relative_to(root).as_posix()
            if rel not in expected:
                continue
            data = p.read_bytes()
            actual[rel] = {"path": rel, "bytes": len(data), "sha256": sha(data)}
        if set(actual) != set(expected):
            raise ValueError(f"{v['name']}: package source coverage differs")
        for rel, b in expected.items():
            if actual[rel] != b:
                raise ValueError(f"{v['name']}: source drift at {rel}")
        if len(actual) != int(v["packageFileCount"]):
            raise ValueError(f"{v['name']}: package count differs")
        task_text = (root / "Tests/SwiftRightRuntimeTests/TaskIDTests.swift").read_text()
        for marker in ("Task.sleep(for: .milliseconds(40))", "XCTAssertEqual(log.results, [\"a\"])", "XCTAssertEqual(log.events.filter { $0 == \"start a\" }.count, 1"):
            if marker not in task_text:
                raise ValueError(f"{v['name']}: original TaskID assertion/body drift")
        if v["name"] == "original" and any(marker in task_text for marker in ("retainedGraph", "waitForTerminalCommit", "DIAG variant=")):
            raise ValueError("original variant contains diagnostic marker")
        if v["name"] == "retained" and ("let retainedGraph = graph" not in task_text or "waitForTerminalCommit" in task_text):
            raise ValueError("retained variant marker mismatch")
        if v["name"] == "terminal" and any(marker not in task_text for marker in ("let retainedGraph = graph", "waitForTerminalCommit", "DIAG variant=terminal")):
            raise ValueError("terminal variant marker mismatch")
    return plan


def encoded_command(script: str) -> list[str]:
    payload = base64.b64encode(script.encode("utf-16le")).decode("ascii")
    return ["ssh", "-o", "BatchMode=yes", "win", "powershell", "-NoProfile", "-EncodedCommand", payload]


def invoke(script: str, stdin: str | None = None, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    # Remote PowerShell consumes one JSON line via ReadLine; never ReadToEnd.
    return subprocess.run(encoded_command(script), input=None if stdin is None else stdin + "\n", text=True, capture_output=True, timeout=timeout, check=False)


def upload(plan: dict) -> None:
    if os.environ.get("TASKID_ALLOW_UPLOAD") != "1":
        raise SystemExit("upload held: set TASKID_ALLOW_UPLOAD=1 only after direct coordination")
    files: dict[str, dict[str, str]] = {
        "source-plan.json": {"data": base64.b64encode(PLAN.read_bytes()).decode("ascii"), "sha256": sha(PLAN.read_bytes())},
        "run-three-variants.ps1": {"data": base64.b64encode(RUNNER.read_bytes()).decode("ascii"), "sha256": sha(RUNNER.read_bytes())},
    }
    for v in plan["variants"]:
        root = REPO / v["localRoot"]
        for b in v["bindings"]:
            p = source_file(root, b["path"])
            files[f"variants/{v['name']}/{b['path']}"] = {"data": base64.b64encode(p.read_bytes()).decode("ascii"), "sha256": sha(p.read_bytes())}
    init_script = r'''$ErrorActionPreference="Stop";$ProgressPreference="SilentlyContinue";$d=[Console]::In.ReadLine()|ConvertFrom-Json;if(Test-Path -Path $d.root){[ordered]@{root=$d.root;status="existing"}|ConvertTo-Json;return};New-Item -ItemType Directory -Path $d.root|Out-Null;[ordered]@{root=$d.root;status="initialized";initializedAt=[DateTime]::UtcNow.ToString("o")}|ConvertTo-Json'''
    write_script = r'''$ErrorActionPreference="Stop";$ProgressPreference="SilentlyContinue";$d=[Console]::In.ReadLine()|ConvertFrom-Json;if(-not(Test-Path -Path $d.root)){throw "Input root missing"};$written=0;$existing=0;foreach($item in @($d.files)){[string]$rel=$item.path;if($rel -match '(^|[\\/])\.\.([\\/]|$)' -or $rel -match '^[\\/]' -or $rel -match ':'){throw "Unsafe relative path"};$dest=Join-Path $d.root ($rel -replace '/','\\');if(Test-Path -Path $dest){$existing++;continue};$parent=Split-Path -Parent $dest;if(-not(Test-Path -Path $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};[IO.File]::WriteAllBytes($dest,[Convert]::FromBase64String([string]$item.data));$written++};[ordered]@{root=$d.root;written=$written;existing=$existing;finishedAt=[DateTime]::UtcNow.ToString("o")}|ConvertTo-Json'''
    parser_script = r'''$ErrorActionPreference="Stop";$ProgressPreference="SilentlyContinue";$d=[Console]::In.ReadLine()|ConvertFrom-Json;$tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile((Join-Path $d.root "run-three-variants.ps1"),[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){$errors|ConvertTo-Json;throw "PowerShell parser rejection"};[ordered]@{root=$d.root;fileCount=@(Get-ChildItem -Path $d.root -Recurse -File).Count;finishedAt=[DateTime]::UtcNow.ToString("o")}|ConvertTo-Json'''
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    init_result = invoke(init_script, json.dumps({"root": REMOTE_INPUT}, separators=(",", ":")), 60)
    batches: list[dict] = []
    if init_result.returncode:
        receipt = {"schema": "taskid-windows-three-variants-upload-receipt-v3", "status": "init-failed", "startedAt": started, "endedAt": dt.datetime.now(dt.timezone.utc).isoformat(), "returncode": init_result.returncode, "stdout": init_result.stdout, "stderr": init_result.stderr, "remoteInputRoot": REMOTE_INPUT, "sourcePlanSha256": sha(PLAN.read_bytes()), "fileCount": len(files), "batches": batches}
        (HERE / "upload-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        raise SystemExit(init_result.returncode)
    names = list(files)
    for i in range(0, len(names), 8):
        selected = names[i:i+8]
        payload = json.dumps({"root": REMOTE_INPUT, "files": [{"path": name, **files[name]} for name in selected]}, separators=(",", ":"))
        result = invoke(write_script, payload, 180)
        row = {"index": i // 8, "paths": selected, "payloadBytes": len(payload), "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr}
        batches.append(row)
        if result.returncode:
            receipt = {"schema": "taskid-windows-three-variants-upload-receipt-v3", "status": "batch-failed", "startedAt": started, "endedAt": dt.datetime.now(dt.timezone.utc).isoformat(), "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr, "remoteInputRoot": REMOTE_INPUT, "sourcePlanSha256": sha(PLAN.read_bytes()), "fileCount": len(files), "batches": batches}
            (HERE / "upload-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
            raise SystemExit(result.returncode)
    parser_result = invoke(parser_script, json.dumps({"root": REMOTE_INPUT}, separators=(",", ":")), 60)
    batches.append({"parserCheck": True, "returncode": parser_result.returncode, "stdout": parser_result.stdout, "stderr": parser_result.stderr})
    receipt = {"schema": "taskid-windows-three-variants-upload-receipt-v3", "status": "uploaded", "startedAt": started, "endedAt": dt.datetime.now(dt.timezone.utc).isoformat(), "returncode": parser_result.returncode, "stdout": parser_result.stdout, "stderr": parser_result.stderr, "remoteInputRoot": REMOTE_INPUT, "sourcePlanSha256": sha(PLAN.read_bytes()), "fileCount": len(files), "batches": batches}
    (HERE / "upload-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if parser_result.returncode:
        raise SystemExit(parser_result.returncode)

def run_remote() -> None:
    token = os.environ.get("TASKID_RUN_TOKEN")
    if token != TOKEN:
        raise SystemExit("run held: TASKID_RUN_TOKEN must be compilerbridge_review confirmation token")
    script = f'& "{REMOTE_INPUT}\\run-three-variants.ps1" -InputRoot "{REMOTE_INPUT}" -RunRoot "{REMOTE_RUN}" -ExecutionToken "{TOKEN}"'
    started = dt.datetime.now(dt.timezone.utc).isoformat()
    result = invoke(script, timeout=1800)
    receipt = {"schema": "taskid-windows-three-variants-dispatch-receipt-v1", "argv": encoded_command(script), "startedAt": started, "endedAt": dt.datetime.now(dt.timezone.utc).isoformat(), "returncode": result.returncode, "stdout": result.stdout, "stderr": result.stderr, "remoteInputRoot": REMOTE_INPUT, "remoteRunRoot": REMOTE_RUN, "sourcePlanSha256": sha(PLAN.read_bytes()), "executionTokenAccepted": result.returncode == 0}
    (HERE / "run-dispatch-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if result.returncode:
        raise SystemExit(result.returncode)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("preflight", "upload", "run"))
    args = parser.parse_args()
    plan = validate_local()
    if args.action == "preflight":
        out = {"schema": "taskid-windows-three-variants-preflight-v1", "status": "verified-deferred", "sourcePlanSha256": sha(PLAN.read_bytes()), "variantNames": [v["name"] for v in plan["variants"]], "windowsExecution": False, "compilerInvocations": 0, "sshInvocations": 0}
        (HERE / "preflight-receipt.json").write_text(json.dumps(out, indent=2) + "\n")
        print(json.dumps(out, indent=2))
    elif args.action == "upload":
        upload(plan)
    else:
        run_remote()

if __name__ == "__main__":
    main()
