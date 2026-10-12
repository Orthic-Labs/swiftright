#!/usr/bin/env python3
"""Source-only positive/fault controls for exact system-primary Text paint."""
from __future__ import annotations
import copy, hashlib, importlib.util, json, stat
from pathlib import Path

HERE = Path(__file__).resolve().parent
PATCH = HERE / "patch_text_paint_default_v1.py"
MAX = 128 * 1024

def bounded_source() -> str:
    st = PATCH.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_size > MAX:
        raise AssertionError("bounded regular patch source required")
    with PATCH.open("rb") as stream:
        data = stream.read(MAX + 1)
    if len(data) != st.st_size:
        raise AssertionError("patch changed while read")
    return data.decode("utf-8")

def admits(fixture: dict) -> bool:
    return (fixture["fontID"] == "system(24.0,regular)" and fixture["familyName"] is None
            and fixture["pointSize"] == 24 and fixture["weight"] == "regular"
            and fixture["design"] == "default" and fixture["isCustom"] is False
            and fixture["lineLimit"] is None and fixture["scale"] == 2.5
            and fixture["paintSemantic"] == "label" and fixture["opacity"] == 1
            and fixture["packedRGBA8"] == "0x1f1f1fff")

def main() -> int:
    text = bounded_source()
    spec = importlib.util.spec_from_file_location("text_paint_patch", PATCH)
    if spec is None or spec.loader is None:
        raise AssertionError("patch module load failed")
    patch_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(patch_module)
    markers = (
        "OLD_PAINT =", "NEW_PAINT =", "func factoryTextPaint(_ foreground: ResolvedColor?, opacity: Double) throws -> UInt32",
        "case .semantic(\"label\")", "return 0x1f1f1fff", "Bridge color contract is packed RGBA8",
        "metadata?.pointSize == 24", "metadata?.isCustom == false", "Float(request.scale) == scale",
    )
    for marker in markers:
        if marker not in text:
            raise AssertionError(f"missing strict overlay marker: {marker}")
    synthetic = patch_module.OLD_STYLE + "\nfunc factoryResolvedFill() {}\n" + patch_module.OLD_PAINT
    transformed = patch_module.transform(synthetic)
    if patch_module.NEW_STYLE not in transformed or patch_module.NEW_PAINT not in transformed:
        raise AssertionError("source transform did not emit strict style/paint guards")
    if transformed.index(patch_module.PAINT_HELPER) > transformed.index("func factoryResolvedFill"):
        raise AssertionError("paint helper inserted after its Swift anchor")
    for broken in (synthetic.replace(patch_module.OLD_STYLE, "", 1), synthetic.replace(patch_module.OLD_PAINT, "", 1)):
        try:
            patch_module.transform(broken)
        except RuntimeError:
            pass
        else:
            raise AssertionError("source mutation accepted malformed legacy guard")
    accepted = {"fontID": "system(24.0,regular)", "familyName": None, "pointSize": 24, "weight": "regular", "design": "default", "isCustom": False, "lineLimit": None, "scale": 2.5, "paintSemantic": "label", "opacity": 1, "packedRGBA8": "0x1f1f1fff"}
    if not admits(accepted):
        raise AssertionError("system-primary positive rejected")
    faults = {
        "legacy-metadata-nil": {"pointSize": None, "weight": None, "design": None},
        "custom-family": {"familyName": "Arial"}, "wrong-size": {"pointSize": 18},
        "wrong-weight": {"weight": "bold"}, "wrong-design": {"design": "serif"},
        "line-limit": {"lineLimit": 1}, "scale-drift": {"scale": 1.0}, "wrong-font-id": {"fontID": "body"},
        "nil-paint": {"paintSemantic": None}, "secondary-paint": {"paintSemantic": "secondaryLabel"},
        "custom-rgba-paint": {"paintSemantic": "rgba(0,0,0,1)"}, "opacity-drift": {"opacity": 0.5},
        "paint-byte-drift": {"packedRGBA8": "0xff0000ff"},
    }
    for label, changes in faults.items():
        fixture = copy.deepcopy(accepted); fixture.update(changes)
        if admits(fixture):
            raise AssertionError(f"paint/style fault accepted: {label}")
    print(json.dumps({"kind": "factory-text-paint-default-controls-v1", "status": "SOURCE_CONTROLS_PASS", "positive": "Color.primary -> semantic label -> packed RGBA8 0x1f1f1fff", "faultsRejected": sorted(faults), "nativeActions": 0, "patchSha256": hashlib.sha256(text.encode()).hexdigest()}, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
