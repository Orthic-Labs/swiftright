#!/usr/bin/env python3
"""Source controls for production identity/count/terminal gates.

Controls intentionally call production `compare`, not a duplicate predicate.
They create only small temporary JSON fixtures when root executes this file.
"""
from __future__ import annotations

import json
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("text_paint_production", HERE / "compare_text_paint.py")
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


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
    mod.validate_windows_control(base_coordinator, base_task)
    # Production Windows terminal predicate rejects each mutation; no mirror
    # validator or synthetic native evidence is used.
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


if __name__ == "__main__":
    check()
    print("text-paint production controls: PASS")
