#!/usr/bin/env python3
"""Offline Count20 successor admission checks; never invokes PowerShell/native code."""
from __future__ import annotations
import hashlib, json
from pathlib import Path

HERE = Path(__file__).resolve().parent
PACKET = HERE.parent
CAPTURE = PACKET.parent
SCRIPTS = {
    "resume": HERE / "resume-issued-coordinator-repeat.ps1",
    "interactive": HERE / "interactive-task-repeat.ps1",
    "dispatch": HERE / "dispatch-repeat.ps1",
    "capture": HERE / "capture-repeat-repeat.ps1",
}

def text(name):
    return SCRIPTS[name].read_text(encoding="utf-8")

def main():
    plan = json.loads((CAPTURE / "capture-plan.json").read_text(encoding="utf-8"))
    repeat = plan["dispatch"]["repeat"]
    assert repeat["count"] == 20
    assert repeat["runRoot"].endswith("actual-repeat-r1")
    assert repeat["firstProofRequired"] is True
    assert plan["dispatch"]["retries"] is False

    all_text = "\n".join(text(k) for k in SCRIPTS)
    for bad in ("dispatch.batch", "actual-batch-r1", "coordinator-batch-r1", "capture-repeat-batch.ps1", "interactive-task-batch.ps1"):
        assert bad not in all_text, bad
    for name, body in ((k, text(k)) for k in SCRIPTS):
        assert "overlayRoot" in body, name
        assert "..\\.." in body, name
        assert "dispatch.repeat" in body or "actual-repeat-r1" in body, name
        assert "Count20" in body, name
        if name != "interactive":
            assert "ValidateSet(20)" in body, name
    assert "interactive-task-repeat.ps1" in text("resume")
    assert "dispatch-repeat.ps1" in text("interactive")
    assert "capture-repeat-repeat.ps1" in text("dispatch")
    for name in ("resume", "dispatch", "capture"):
        body = text(name)
        assert "Assert-PaddingFirstCaptureProof" in body
        proof = body.index("Assert-PaddingFirstCaptureProof")
        lock = min((i for i in (body.find("function Check-Lock"), body.find("$lock="), body.find("Get-Content -Raw 'D:\\Claude\\desktop.lock'")) if i >= 0), default=-1)
        assert lock == -1 or proof < lock, name
    packet_manifest = json.loads((HERE / "root-stage-manifest.json").read_text(encoding="utf-8"))
    for row in packet_manifest["files"]:
        raw = (HERE / row["path"]).read_bytes()
        assert len(raw) == row["bytes"]
        assert "sha256:" + hashlib.sha256(raw).hexdigest() == row["sha256"], row["path"]
    # Preserve accepted Count1 r3 source bytes exactly; this test only reads them.
    frozen = CAPTURE / "root-metadata-controls-v1" / "execute-r3"
    manifest = json.loads((frozen / "root-stage-manifest.json").read_text(encoding="utf-8"))
    for row in manifest["files"]:
        p = frozen / row["path"].split("/")[-1]
        assert p.is_file(), str(p)
        raw = p.read_bytes()
        assert len(raw) == row["bytes"]
        assert "sha256:" + hashlib.sha256(raw).hexdigest() == row["sha256"], str(p)
    # This admission test only reads source/JSON; it never launches PowerShell.
    print("PASS repeat-r1 source admission; native/lock/compiler/remote actions=0")

if __name__ == "__main__":
    main()
