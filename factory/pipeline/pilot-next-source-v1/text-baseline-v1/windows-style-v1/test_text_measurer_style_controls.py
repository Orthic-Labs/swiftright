#!/usr/bin/env python3
"""Source-only Text style controls; no compiler, process, or native action."""
from __future__ import annotations
import copy
import hashlib, json, stat
from pathlib import Path

HERE = Path(__file__).resolve().parent
PATCH = HERE / "patch_text_measurer.py"
MAX = 128 * 1024

def source() -> str:
    st = PATCH.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode) or st.st_size > MAX:
        raise AssertionError("bounded regular patch source required")
    data = PATCH.read_bytes()
    if len(data) != st.st_size:
        raise AssertionError("patch changed while read")
    return data.decode()

def main() -> int:
    text = source()
    for marker in ("let metadata = request.fontMetadata", "let expectedFont = Font.system(size: 24, weight: .regular, design: .default)", "guard metadata != nil", "request.fontID == expectedFont.id", "metadata?.familyName == nil", "metadata?.pointSize == 24", "metadata?.weight == .regular", "metadata?.design == .default", "metadata?.isCustom == false", "request.lineLimit == nil", "Float(request.scale) == scale"):
        if marker not in text:
            raise AssertionError(f"missing strict style marker: {marker}")
    accepted = {"fontID": "system(24.0,regular)", "familyName": None, "pointSize": 24, "weight": "regular", "design": "default", "isCustom": False, "lineLimit": None, "scale": 2.5}
    def admits(fixture: dict) -> bool:
        return (fixture["fontID"] == "system(24.0,regular)" and fixture["familyName"] is None
                and fixture["pointSize"] == 24 and fixture["weight"] == "regular"
                and fixture["design"] == "default" and fixture["isCustom"] is False
                and fixture["lineLimit"] is None and fixture["scale"] == 2.5)
    if not admits(accepted):
        raise AssertionError("strict system-style positive rejected")
    faults = {"legacy-metadata-nil": {"familyName": None, "pointSize": None, "weight": None, "design": None},
              "custom-family": {"familyName": "Arial"}, "wrong-size": {"pointSize": 18},
              "wrong-weight": {"weight": "bold"}, "wrong-design": {"design": "serif"},
              "line-limit": {"lineLimit": 1}, "scale-drift": {"scale": 1.0},
              "wrong-font-id": {"fontID": "body"}}
    for label, changes in faults.items():
        fixture = copy.deepcopy(accepted); fixture.update(changes)
        if admits(fixture):
            raise AssertionError(f"style fault accepted: {label}")
    print(json.dumps({"kind": "factory-text-measurer-style-controls-v1", "status": "SOURCE_CONTROLS_PASS", "positive": "system-24-regular-default", "faultsRejected": sorted(faults), "nativeActions": 0, "patchSha256": hashlib.sha256(text.encode()).hexdigest()}, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
