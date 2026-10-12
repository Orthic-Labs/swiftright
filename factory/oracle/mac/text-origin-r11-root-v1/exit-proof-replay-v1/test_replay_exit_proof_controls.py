#!/usr/bin/env python3
"""Source controls for exit-proof replay; no child launch."""
from __future__ import annotations

import importlib.util
import copy
import hashlib
import os
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("exit_proof_replay", HERE / "replay_exit_proof.py")
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def check() -> None:
    assert module.HOST_SHA == "sha256:fb2757beded3e6d1d4d650b508ed28f2080f0168d56948f7a1dac2bc897db84c"
    assert module.AX_SHA == "sha256:7f1013de103feefabf35a525bfedd28a2abbe60763761c8e0372530f8a051581"
    assert module.CASE_ID.endswith("54310440be2e6418")
    assert module.TUPLE_ID == "sr1-text-paint-v2-r11-paired20-20261012"
    assert module.normalize_hash(module.HOST_SHA.removeprefix("sha256:")) == module.HOST_SHA
    assert module.normalize_hash(module.AX_SHA) == module.AX_SHA
    try:
        module.normalize_hash("0" * 63 + "g")
    except module.Hold:
        pass
    else:
        raise AssertionError("malformed producer hash was admitted")
    source = (HERE / "replay_exit_proof.py").read_text(encoding="utf-8")
    for marker in ("waitPidObserved", "streamsSealed", "rssLimitExceeded", "outputLimitExceeded", "axTrusted", "start_new_session=False", "producer-bytes-v1", "copy_measured", "stage_execution", "validate_execution_record", "executionPath", "archivedPath", "os.chmod(destination, 0o700)", "symlink component rejected"):
        assert marker in source, marker
    assert "os.killpg" not in source
    assert "--preflight" in source
    assert '"qualified": False' in source
    assert "execution bin must be fresh" in source
    assert "execution copy collision" in source

    # Pure record faults: no child launch, archived refs cannot become argv.
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        (root / "bin").mkdir()
        rows = {}
        for role, name in (("host", "capture-host"), ("ax", "ax-f5-ax-client")):
            staged = root / "bin" / name
            staged.write_bytes(b"measured-" + role.encode())
            os.chmod(staged, 0o700)
            rows[role] = {"archivedPath": f"/archive/{name}", "executionPath": str(staged), "bytes": staged.stat().st_size, "sha256": "sha256:" + hashlib.sha256(staged.read_bytes()).hexdigest()}
        record = {"root": str(root / "bin"), **rows}
        module.validate_execution_record(record, root)
        drift = copy.deepcopy(record)
        drift["host"]["executionPath"] = drift["host"]["archivedPath"]
        try:
            module.validate_execution_record(drift, root)
        except module.Hold:
            pass
        else:
            raise AssertionError("archived execution path fault was admitted")


if __name__ == "__main__":
    check()
    print("Text Mac exit-proof source controls: PASS")
