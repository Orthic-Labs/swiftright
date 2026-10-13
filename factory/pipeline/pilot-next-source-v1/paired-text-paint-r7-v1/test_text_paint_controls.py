#!/usr/bin/env python3
"""Source controls for production identity/count/terminal gates.

Controls intentionally call production `compare`, not a duplicate predicate.
They create only small temporary JSON fixtures when root executes this file.
"""
from __future__ import annotations

import json
import tempfile
from pathlib import Path
import importlib.util

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("text_paint_production", HERE / "compare_text_paint.py")
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def write(root: Path, rel: str, value: object) -> None:
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(value), encoding="utf-8")


def windows_shape(count: object = 20, *, case: dict | None = None, terminal: dict | None = None) -> dict:
    c = case or {"id": mod.CASE_ID, "hash": mod.CASE_HASH}
    t = terminal or {"kernelWait": 0, "exitCode": 0, "originalHandleRetained": True,
                     "streamDrainComplete": True, "streamsSealed": True, "jobActiveCount": 0}
    row = {"case": c, "raw": [{"path": "raw.json", "sha256": "sha256:" + "0" * 64}], "terminal": t}
    return {"successfulCount": count, "rows": [row for _ in range(20)]}


def check() -> None:
    base_coordinator = {
        "count": 20, "status": "completed-source-bound-observation", "wholeBatchExitConfirmed": True,
        "lockReleased": True, "cleanupErrors": [],
        "taskParentProof": {"kernelWait": 0, "retainedHandle": 1920, "kernelExitCode": 0,
                             "kernelExitCodeSigned": 0, "dotNetExited": True, "dotNetExitCode": 0},
    }
    base_task = {
        "count": 20, "status": "completed-source-bound-observation",
        "memoryReceipt": {"status": "passed", "activeProcessCount": 1,
                           "jobMemoryLimitBytes": 1073741824, "limitFlags": 512, "killOnJobClose": False},
    }
    # These mutations execute same production control predicate used by
    # windows_adapter; none can be accepted by changing a merely descriptive
    # report field.
    for name, mutate in (
        ("count19", lambda c, t: c.update(count=19)),
        ("lock-held", lambda c, t: c.update(lockReleased=False)),
        ("parent-kernel", lambda c, t: c["taskParentProof"].update(kernelWait=1)),
        ("parent-dotnet", lambda c, t: c["taskParentProof"].update(dotNetExitCode=17)),
        ("memory-active", lambda c, t: t["memoryReceipt"].update(activeProcessCount=0)),
        ("memory-budget", lambda c, t: t["memoryReceipt"].update(jobMemoryLimitBytes=536870912)),
        ("memory-kill", lambda c, t: t["memoryReceipt"].update(killOnJobClose=True)),
    ):
        c = json.loads(json.dumps(base_coordinator)); t = json.loads(json.dumps(base_task)); mutate(c, t)
        try:
            mod.validate_windows_control(c, t)
        except mod.Hold:
            pass
        else:
            raise AssertionError(name)
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        write(root, "admission/candidate-binding.json", {"case": {"id": mod.CASE_ID, "hash": mod.CASE_HASH}, "sourceHash": "sha256:" + "1" * 64})
        write(root, "admission/candidate-tuple.json", {"case": {"id": mod.CASE_ID, "hash": mod.CASE_HASH}, "tuple": {"id": mod.TUPLE_ID}, "sourceInputs": {}})
        write(root, "admission/source-inputs.json", {"caseID": mod.CASE_ID, "caseHash": mod.CASE_HASH, "tupleID": mod.TUPLE_ID})
        write(root, "native/plan.json", {"case": {"id": mod.CASE_ID, "hash": mod.CASE_HASH}})
        write(root, "native/observation.json", {"case": {"id": mod.CASE_ID, "hash": mod.CASE_HASH}, "sourceHash": "sha256:" + "1" * 64})
        (root / "raw.json").write_bytes(b"{}")
        # Production compare must hold missing successfulCount, count 19, wrong
        # case, missing terminal, & terminal mutation; no fixture is accepted.
        for name, doc in (("missing-count", {"rows": []}), ("count-19", windows_shape(19)),
                          ("wrong-case", windows_shape(case={"id": "wrong", "hash": mod.CASE_HASH})),
                          ("missing-terminal", {"successfulCount": 20, "rows": [{"case": {"id": mod.CASE_ID, "hash": mod.CASE_HASH}, "raw": []}] * 20}),
                          ("bad-active", windows_shape(terminal={"kernelWait": 0, "exitCode": 0, "originalHandleRetained": True, "streamDrainComplete": True, "streamsSealed": True, "jobActiveCount": 1}))):
            write(root, "export-manifest.json", doc)
            out = mod.compare(Path(td), root)
            assert out["status"] == "blocked", name


if __name__ == "__main__":
    check()
    print("text-paint production controls: PASS")
