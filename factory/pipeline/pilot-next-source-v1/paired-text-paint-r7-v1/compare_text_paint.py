#!/usr/bin/env python3
"""Bounded, raw-only adapter for Text paint paired observations.

This module deliberately refuses to infer missing Windows20 receipts.  It is
also used by controls, so controls exercise production validation rather than
an independent mirror predicate.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any, Iterable

MAX_JSON = 4 * 1024 * 1024
MAX_FILE = 16 * 1024 * 1024
MAX_TOTAL = 128 * 1024 * 1024
SHA = "sha256:"
CASE_ID = "swiftui.text.layout.baseline.recipe.pilot-next.text-baseline-light.54310440be2e6418"
CASE_HASH = SHA + "29807aa918aa7c2c1c4a4705eb324b0020f29060be7359d4923694aeb5d437ad"
TUPLE_ID = "sr1-text-paint-v2-r11-paired20-20261012"
WIN_HOST_HASH = SHA + "33248eaa0369e8d4b5e7dea9e1df7d6d86110ee3f31c8fdc9db61a500d057fe7"
MAC_HOST_HASH = SHA + "fb2757beded3e6d1d4d650b508ed28f2080f0168d56948f7a1dac2bc897db84c"
RENDERER_HASH = SHA + "e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
SOURCE_HASH = SHA + "4770ac41a8826891d972725f4af8e56f92c5b66ead5777eee677692cec71701e"


class Hold(Exception):
    pass


class Bounded:
    def __init__(self) -> None:
        self.total = 0

    def path(self, root: Path, relative: str) -> Path:
        p = Path(relative)
        if p.is_absolute() or ".." in p.parts:
            raise Hold(f"unsafe relative path: {relative}")
        cur = root
        for part in p.parts:
            cur = cur / part
            if cur.is_symlink():
                raise Hold(f"symlink path component: {relative}")
        return cur

    def bytes(self, path: Path, limit: int = MAX_FILE) -> bytes:
        try:
            st = path.stat()
        except OSError as e:
            raise Hold(f"unreadable input {path}: {e}") from e
        if not path.is_file() or path.is_symlink():
            raise Hold(f"input is not regular: {path}")
        if st.st_size > limit:
            raise Hold(f"input exceeds {limit} bytes: {path}")
        self.total += st.st_size
        if self.total > MAX_TOTAL:
            raise Hold("aggregate input exceeds 128MiB")
        out = bytearray()
        with path.open("rb") as f:
            while True:
                chunk = f.read(1024 * 1024)
                if not chunk:
                    return bytes(out)
                out.extend(chunk)

    def json(self, path: Path) -> Any:
        try:
            return json.loads(self.bytes(path, MAX_JSON).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError) as e:
            raise Hold(f"invalid JSON: {path}: {e}") from e

    def file_ref(self, root: Path, relative: str, limit: int = MAX_FILE) -> dict[str, Any]:
        path = self.path(root, relative)
        try:
            st = path.stat()
        except OSError as e:
            raise Hold(f"missing raw file {relative}: {e}") from e
        if not path.is_file() or path.is_symlink():
            raise Hold(f"raw file is not regular: {relative}")
        if st.st_size > limit:
            raise Hold(f"raw file exceeds {limit} bytes: {relative}")
        self.total += st.st_size
        if self.total > MAX_TOTAL:
            raise Hold("aggregate raw bytes exceeds 128MiB")
        digest = hashlib.sha256()
        with path.open("rb") as f:
            while chunk := f.read(1024 * 1024):
                digest.update(chunk)
        return {"path": relative, "bytes": st.st_size, "sha256": SHA + digest.hexdigest()}


def need(obj: dict[str, Any], key: str, where: str) -> Any:
    if key not in obj:
        raise Hold(f"{where} missing {key}")
    return obj[key]


def same_identity(left: dict[str, Any], right: dict[str, Any], label: str) -> None:
    for key in ("id", "hash"):
        if left.get(key) != right.get(key):
            raise Hold(f"{label}.{key} mismatch")


def mac_adapter(root: Path, b: Bounded) -> dict[str, Any]:
    index = b.json(b.path(root, "capture-index.json"))
    results = need(index, "results", "Mac capture-index")
    if not isinstance(results, list) or len(results) != 1:
        raise Hold("Mac capture-index must contain exactly one result")
    case = need(results[0], "case", "Mac capture-index result")
    same_identity(case, {"id": CASE_ID, "hash": CASE_HASH}, "Mac case")
    case_dir = b.path(root, CASE_ID)
    summary = b.json(case_dir / "summary.json")
    same_identity(need(summary, "case", "Mac summary"), case, "Mac summary case")
    runs = need(summary, "runs", "Mac summary")
    if not isinstance(runs, list) or len(runs) != 20:
        raise Hold("Mac summary must contain 20 runs")
    first_capture: dict[str, Any] | None = None
    rows: list[dict[str, Any]] = []
    for ordinal in range(1, 21):
        entry = runs[ordinal - 1]
        if not isinstance(entry, dict) or entry.get("run") != ordinal:
            raise Hold(f"Mac run ordinal mismatch at {ordinal}")
        rel = f"{CASE_ID}/run-{ordinal:03d}"
        capture = b.json(b.path(root, f"{rel}/capture.json"))
        same_identity(need(capture, "case", f"Mac run {ordinal}"), case, f"Mac run {ordinal} case")
        if capture.get("run") not in (None, ordinal) and capture.get("meta", {}).get("run") != ordinal:
            raise Hold(f"Mac run {ordinal} capture ordinal mismatch")
        tuple_doc = need(capture, "tuple", f"Mac run {ordinal}")
        if first_capture is None:
            first_capture = tuple_doc
        elif tuple_doc != first_capture:
            raise Hold(f"Mac run {ordinal} tuple drift")
        refs = [
            f"{rel}/capture.json", f"{rel}/plain.raw.json", f"{rel}/instrumented.raw.json",
            f"{rel}/compositor.raw.json", f"{rel}/external-ax.raw.json", f"{rel}/clock.json",
            f"{rel}/owned-window-process.json",
        ]
        raw = [b.file_ref(root, p, MAX_JSON) for p in refs]
        # Image hashes are semantic references in capture.json.  Hash image bytes
        # only when present; absence stays an explicit hold rather than a fake ref.
        for name in ("plain.png", "instrumented.png", "compositor.png"):
            raw.append(b.file_ref(root, f"{rel}/{name}", MAX_FILE))
        owned = b.json(b.path(root, f"{rel}/owned-window-process.json"))
        rows.append({
            "ordinal": ordinal,
            "sourceRun": f"run-{ordinal:03d}",
            "captureSemanticHash": entry.get("captureHash"),
            "capture": capture,
            "raw": raw,
            "terminal": {
                "retainedProcessHandle": owned.get("retainedProcessHandle"),
                "processGroupOwned": owned.get("processGroupOwned"),
                "pid": owned.get("pid"),
                "executable": owned.get("executable"),
                "terminalCertificate": False,
                "jobActiveCount": None,
            },
        })
    assert first_capture is not None
    provenance = need(first_capture, "provenance", "Mac capture")
    if provenance.get("sourceHash") != SOURCE_HASH or summary.get("sourceHash") != SOURCE_HASH:
        raise Hold("Mac source hash does not match admitted Text witness")
    if first_capture["tuple"].get("id") != TUPLE_ID:
        raise Hold("Mac tuple id mismatch")
    if first_capture["tuple"].get("rendererHash") != RENDERER_HASH:
        raise Hold("Mac renderer hash mismatch")
    compiler_receipt = summary.get("compilerReceipt", {}).get("compiler", {})
    if compiler_receipt.get("outputBinary", {}).get("sha256") != summary.get("binaryHash"):
        raise Hold("Mac compiler output hash is not joined to summary binary")
    return {
        "platform": "macos", "case": case, "tuple": first_capture["tuple"],
        "sourceHash": provenance.get("sourceHash"),
        "hostHash": first_capture.get("meta", {}).get("host", {}).get("hash"),
        "rendererHash": first_capture["tuple"].get("rendererHash"),
        "recipe": summary.get("probeManifest", {}).get("recipe"),
        "compiler": {"binaryHash": summary.get("binaryHash"), "adapterSourceHash": summary.get("adapterSourceHash")},
        "rows": rows,
        "holds": ["Mac rows expose retained process handles but no terminal certificate/job active proof"],
    }


def validate_windows_control(coordinator: dict[str, Any], task: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    """Validate actual control/coordinator schema; returns proofs unchanged."""
    if coordinator.get("count") != 20 or task.get("count") != 20:
        raise Hold("Windows coordinator/task-result do not both report count 20")
    if coordinator.get("status") != "completed-source-bound-observation" or task.get("status") != "completed-source-bound-observation":
        raise Hold("Windows coordinator/task-result status is not completed source-bound observation")
    if coordinator.get("wholeBatchExitConfirmed") is not True or coordinator.get("lockReleased") is not True:
        raise Hold("Windows coordinator missing whole-batch exit or lock-release proof")
    if coordinator.get("cleanupErrors") not in ([], None):
        raise Hold("Windows coordinator reports cleanup errors")
    parent = coordinator.get("taskParentProof")
    if not isinstance(parent, dict):
        raise Hold("Windows coordinator missing taskParentProof")
    for key, expected in (("kernelWait", 0), ("kernelExitCode", 0), ("kernelExitCodeSigned", 0), ("dotNetExitCode", 0)):
        if parent.get(key) != expected:
            raise Hold(f"Windows taskParentProof {key} is not zero")
    if parent.get("dotNetExited") is not True or not isinstance(parent.get("retainedHandle"), int):
        raise Hold("Windows taskParentProof lacks retained handle or .NET exit proof")
    memory = task.get("memoryReceipt")
    if not isinstance(memory, dict) or memory.get("status") != "passed":
        raise Hold("Windows task-result missing passed memoryReceipt")
    if memory.get("activeProcessCount") != 1 or memory.get("jobMemoryLimitBytes") != 1073741824 or memory.get("limitFlags") != 512:
        raise Hold("Windows memoryReceipt lacks required 1GiB self-job admission")
    if memory.get("killOnJobClose") is not False:
        raise Hold("Windows memoryReceipt killOnJobClose must be false")
    return parent, memory


def windows_adapter(root: Path, b: Bounded) -> dict[str, Any]:
    # Actual producer schema uses control/coordinator.json + task-result.json.
    # export-manifest.count is file count, so it must never become run count.
    coordinator = b.json(b.path(root, "control/coordinator.json"))
    task = b.json(b.path(root, "control/task-result.json"))
    parent, memory = validate_windows_control(coordinator, task)
    binding = b.json(b.path(root, "admission/candidate-binding.json"))
    candidate = b.json(b.path(root, "admission/candidate-tuple.json"))
    inputs = b.json(b.path(root, "admission/source-inputs.json"))
    plan = b.json(b.path(root, "native/plan.json"))
    obs = b.json(b.path(root, "native/observation.json"))
    same_identity(need(binding, "case", "Windows binding"), {"id": CASE_ID, "hash": CASE_HASH}, "Windows case")
    tuple_doc = need(candidate, "tuple", "Windows candidate tuple")
    if tuple_doc.get("id") != TUPLE_ID:
        raise Hold("Windows tuple id mismatch")
    if tuple_doc.get("hostHashes", {}).get("windows") != WIN_HOST_HASH:
        raise Hold("Windows host hash mismatch")
    if tuple_doc.get("hostHashes", {}).get("macos") != MAC_HOST_HASH:
        raise Hold("Windows tuple Mac host hash mismatch")
    if tuple_doc.get("rendererHash") != RENDERER_HASH:
        raise Hold("Windows tuple renderer hash mismatch")
    if candidate.get("case") != binding.get("case"):
        raise Hold("Windows candidate/binding case drift")
    for key, expected in (("caseID", CASE_ID), ("caseHash", CASE_HASH), ("tupleID", TUPLE_ID)):
        if key in inputs and inputs[key] != expected:
            raise Hold(f"Windows source-input {key} mismatch")
    if plan.get("case") != candidate.get("case") or obs.get("case") != candidate.get("case"):
        raise Hold("Windows plan/observation case drift")
    if obs.get("sourceHash") != binding.get("sourceHash"):
        raise Hold("Windows source hash drift")
    if binding.get("sourceHash") != SOURCE_HASH:
        raise Hold("Windows source hash does not match admitted Text witness")
    if obs.get("compilerHash") != plan.get("compilerHash"):
        raise Hold("Windows compiler hash drift")
    if plan.get("recipe") != candidate.get("recipe", plan.get("recipe")):
        # Candidate tuple roots from r11 do not carry recipe, so this branch
        # only rejects a producer that supplies a contradictory one.
        raise Hold("Windows plan/candidate recipe drift")
    rows: list[dict[str, Any]] = []
    for ordinal in range(1, 21):
        rel = f"native/native-{ordinal:02d}"
        outcome = b.json(b.path(root, f"{rel}/capture-outcome.json"))
        cert = b.json(b.path(root, f"{rel}/final-exit-certificate.json"))
        terminal_worker = b.json(b.path(root, f"{rel}/terminal-worker.json"))
        owned = b.json(b.path(root, f"{rel}/owned-process.json"))
        if outcome.get("case") not in (None, candidate.get("case")):
            raise Hold(f"Windows row {ordinal} case drift")
        if terminal_worker.get("terminalResultConfirmed") is not True:
            raise Hold(f"Windows row {ordinal} terminal worker not confirmed")
        sample = cert.get("sample")
        streams = cert.get("rawStreams")
        if not isinstance(sample, dict) or not isinstance(streams, list) or len(streams) != 2:
            raise Hold(f"Windows row {ordinal} missing terminal certificate streams")
        if sample.get("kernelAfter") != 0 or sample.get("exitCode") != 0 or sample.get("getExitCodeSucceeded") is not True:
            raise Hold(f"Windows row {ordinal} exit certificate is not zero/verified")
        if cert.get("start", {}).get("retainedHandle") is None or owned.get("pid") is None:
            raise Hold(f"Windows row {ordinal} missing original process identity")
        if any(s.get("sealed") is not True or s.get("copyCompleted") is not True or s.get("destinationClosed") is not True for s in streams):
            raise Hold(f"Windows row {ordinal} streams are not sealed")
        raw = []
        for filename in ("capture-outcome.json", "final-exit-certificate.json", "terminal-worker.json", "owned-process.json", "host.stdout.txt", "host.stderr.txt", "native.pixels.json", "native.uia.json", "native.printwindow.png", "native.screen.png"):
            raw.append(b.file_ref(root, f"{rel}/{filename}", MAX_FILE))
        rows.append({"ordinal": ordinal, "sourceRun": f"native-{ordinal:02d}", "raw": raw,
                     "terminal": {"kernelWait": sample.get("kernelAfter"), "exitCode": sample.get("exitCode"),
                                   "originalHandleRetained": True, "streamDrainComplete": all(s.get("copyCompleted") is True for s in streams),
                                   "streamsSealed": all(s.get("sealed") is True for s in streams)},
                     "observation": outcome})
    return {
        "platform": "windows", "case": candidate["case"], "tuple": tuple_doc,
        "sourceHash": binding.get("sourceHash"), "hostHash": tuple_doc.get("hostHashes", {}).get("windows"),
        "rendererHash": binding.get("renderer", {}).get("sha256"),
        "recipe": plan.get("recipe"),
        "compiler": {"compilerHash": plan.get("compilerHash"), "exeHash": obs.get("exeSha256")},
        "rows": rows, "successfulCount": 20, "successfulCountRef": "control/coordinator.json", "memoryReceipt": memory, "parentProof": parent, "holds": [],
    }


def validate_pair(mac: dict[str, Any], win: dict[str, Any]) -> list[str]:
    holds = list(mac.get("holds", []))
    same_identity(mac["case"], win["case"], "paired case")
    if mac.get("tuple", {}).get("id") != win.get("tuple", {}).get("id"):
        raise Hold("paired tuple id mismatch")
    if mac.get("sourceHash") != win.get("sourceHash"):
        raise Hold("paired source hash mismatch")
    if mac.get("tuple") != win.get("tuple"):
        raise Hold("paired tuple contents mismatch")
    if mac.get("recipe") != win.get("recipe"):
        raise Hold("paired recipe identity mismatch")
    if mac.get("rendererHash") != win.get("rendererHash"):
        raise Hold("paired renderer hash mismatch")
    if mac.get("hostHash") != mac.get("tuple", {}).get("hostHashes", {}).get("macos"):
        holds.append("Mac host hash is absent or not joined to tuple")
    for row in mac["rows"]:
        t = row["terminal"]
        if not t.get("retainedProcessHandle"):
            holds.append(f"Mac {row['sourceRun']} missing retained process handle")
        holds.append(f"Mac {row['sourceRun']} missing terminal certificate/job active proof")
    return holds


def compare(mac_root: Path, win_root: Path) -> dict[str, Any]:
    b = Bounded()
    result: dict[str, Any] = {
        "kind": "factory-text-paint-paired20-observed-v1", "status": "blocked",
        "parity": "held", "semantic": "held", "timing": "raw-only",
        "inputs": {"macRoot": str(mac_root), "windowsRoot": str(win_root)}, "holds": [],
    }
    try:
        mac = mac_adapter(mac_root, b)
        win = windows_adapter(win_root, b)
        result["mac"] = mac; result["windows"] = win
        result["holds"] = validate_pair(mac, win)
        result["status"] = "observed-diagnostic"
        result["observed"] = {"macCount": len(mac["rows"]), "windowsCount": len(win["rows"]), "rawBytesRead": b.total}
    except Hold as e:
        result["holds"].append(str(e)); result["status"] = "blocked"
        result["observed"] = {"rawBytesRead": b.total}
    return result


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--mac-root", type=Path, required=True)
    p.add_argument("--windows-root", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    args = p.parse_args()
    report = compare(args.mac_root, args.windows_root)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    tmp = args.output.with_suffix(args.output.suffix + ".tmp")
    tmp.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(tmp, args.output)
    return 0 if report["status"] != "blocked" else 2


if __name__ == "__main__":
    raise SystemExit(main())
