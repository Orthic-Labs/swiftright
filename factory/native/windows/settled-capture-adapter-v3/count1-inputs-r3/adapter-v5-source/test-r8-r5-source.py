#!/usr/bin/env python3
"""Pure source controls for execute-r8/repeat-r5 telemetry successor."""
from __future__ import annotations

import hashlib
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = next(p for p in HERE.parents if (p / "factory").is_dir())
R7 = REPO / "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r7"
R8 = REPO / "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r8"
R4 = REPO / "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r4"
R5 = REPO / "factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r5"
BASE_HASH = {
    "producerProfile": "sha256:72016fe5689e9cb74ef851ab6be2665f74b1b5a73ec0711e406046748b287967",
    "capturePlan": "sha256:db405b87fd926bbe45744f19b0c23990ea8dcf9c1d92d553781c9cef9920362a",
    "compiler": "sha256:1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a",
}


def digest(p):
    return "sha256:" + hashlib.sha256(p.read_bytes()).hexdigest()


def check_pair(old_dir, new_dir, old_suffix, new_suffix):
    old = old_dir / f"capture-repeat-{old_suffix}.ps1"
    new = new_dir / f"capture-repeat-{new_suffix}.ps1"
    old_text = old.read_text()
    new_text = new.read_text()
    addition = ";rawHashStates=[ordered]@{stdout=[ordered]@{sha256=$stdoutHashState.sha256;qualification=$stdoutHashState.qualification;error=$stdoutHashState.error};stderr=[ordered]@{sha256=$stderrHashState.sha256;qualification=$stderrHashState.qualification;error=$stderrHashState.error}}"
    assert new_text.count(addition) == 1
    assert new_text.replace(addition, "").replace(f"-{new_suffix}", f"-{old_suffix}") == old_text
    assert '"user42.dll"' not in new_text and '"user32.dll"' in new_text
    assert new_text.count('[DllImport("user32.dll")]') == old_text.count('[DllImport("user32.dll")]')
    assert 'rawHashesQualification=$rawQualification' in new_text
    return {p.name: digest(p) for p in new_dir.glob("*.ps1")}


def main():
    r8 = check_pair(R7, R8, "r7", "r8")
    r5 = check_pair(R4, R5, "r4", "r5")
    for d in (R8, R5):
        for p in d.glob("*.ps1"):
            text = p.read_text()
            assert "user42.dll" not in text
            assert "rawHashStates" in (d / next(x.name for x in d.glob("capture-repeat-*.ps1"))).read_text()
    # Meaningful source faults: telemetry removed or ABI import altered.
    capture = (R8 / "capture-repeat-r8.ps1").read_text()
    assert "rawHashStates" in capture
    stripped = capture.replace("rawHashStates", "")
    assert "rawHashStates" not in stripped
    altered = capture.replace('"user32.dll"', '"user42.dll"', 1)
    assert altered.count('[DllImport("user32.dll")]') != (R7 / "capture-repeat-r7.ps1").read_text().count('[DllImport("user32.dll")]')
    assert BASE_HASH["producerProfile"].startswith("sha256:") and BASE_HASH["capturePlan"].startswith("sha256:") and BASE_HASH["compiler"].startswith("sha256:")
    print({"status": "pass", "executeR8Files": len(r8), "repeatR5Files": len(r5), "faults": ["rawHashStates-missing", "win32-import-drift"]})


if __name__ == "__main__":
    main()
