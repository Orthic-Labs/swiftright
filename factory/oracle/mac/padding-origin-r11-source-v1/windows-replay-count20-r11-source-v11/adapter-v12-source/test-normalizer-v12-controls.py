#!/usr/bin/env python3
"""Source-only normalizer controls over real v12 output; faults mutate memory only."""
from __future__ import annotations
import argparse, copy, importlib.util, json, re
from pathlib import Path

SHA = re.compile(r"^sha256:[0-9a-f]{64}$")
MAX_JSON = 4 * 1024 * 1024


class Hold(ValueError):
    pass


HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("normalizer_v12_controls", HERE / "normalize-inputs-v12.py")
if _spec is None or _spec.loader is None:
    raise SystemExit("HOLD: normalizer source unavailable")
normalizer = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(normalizer)


def validate(value: object) -> None:
    if not isinstance(value, dict) or value.get("kind") != "factory-native-count20-r17-normalized-inputs-v12" or value.get("version") != 12:
        raise Hold("normalized v12 schema mismatch")
    if value.get("typedStatus") != "normalized-observational" or value.get("qualified") is not False:
        raise Hold("normalizer must remain observational")
    profile = value.get("freshSourceProfile") or {}
    case = {"id": profile.get("caseID"), "hash": profile.get("caseHash")}
    if not isinstance(case["id"], str) or not SHA.fullmatch(str(case["hash"])):
        raise Hold("fresh case profile missing")
    host_hash = (profile.get("hostHashes") or {}).get("windows")
    if not SHA.fullmatch(str(host_hash)):
        raise Hold("fresh host hash profile missing")
    captures = value.get("captures")
    if not isinstance(captures, list) or len(captures) != 20:
        raise Hold("normalized capture count mismatch")
    ids: set[str] = set()
    images: set[str] = set()
    for index, capture in enumerate(captures, 1):
        if not isinstance(capture, dict) or capture.get("meta", {}).get("run") != index or capture.get("case") != case:
            raise Hold(f"run {index} fresh case/run join missing")
        cid, image = capture.get("id"), (capture.get("images") or [{}])[0]
        if not isinstance(cid, str) or cid in ids or not isinstance(image, dict) or not isinstance(image.get("id"), str) or image["id"] in images:
            raise Hold(f"run {index} capture/image identity missing")
        ids.add(cid); images.add(image["id"])
        if capture.get("meta", {}).get("host", {}).get("hash") != host_hash:
            raise Hold(f"run {index} measured executable join missing")
        evidence = capture.get("meta", {}).get("conditions", {}).get("readerEvidence")
        if not isinstance(evidence, dict) or evidence.get("kind") != "measured-uia-paint-proof-v1":
            raise Hold(f"run {index} UIA paint proof missing")
        for key in ("uiaSha256", "pixelsReceiptSha256", "printWindowSha256", "printWindowRepeatSha256", "stdoutSha256"):
            if not SHA.fullmatch(str(evidence.get(key))):
                raise Hold(f"run {index} reader evidence hash missing: {key}")
        if evidence.get("uiaParsed") is not True or evidence.get("pixelsReceiptParsed") is not True or not isinstance(evidence.get("uiaNodeCount"), int) or evidence["uiaNodeCount"] <= 0:
            raise Hold(f"run {index} UIA/pixels parse proof missing")
        dimensions = evidence.get("printWindow") or {}
        if not isinstance(dimensions.get("widthPx"), int) or dimensions["widthPx"] <= 0 or not isinstance(dimensions.get("heightPx"), int) or dimensions["heightPx"] <= 0:
            raise Hold(f"run {index} PrintWindow dimensions missing")
        if image.get("hash") != evidence.get("printWindowSha256") or image.get("widthPx") != dimensions.get("widthPx") or image.get("heightPx") != dimensions.get("heightPx"):
            raise Hold(f"run {index} UIA/paint image join missing")


def reject(label: str, value: dict, inputs: dict, root: Path) -> dict:
    try:
        normalizer.validate_normalized(value, inputs, root)
        validate(value)
    except (Hold, normalizer.Hold, ValueError) as exc:
        return {"name": label, "status": "rejected", "reason": str(exc)}
    raise SystemExit("control unexpectedly accepted: " + label)


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--normalized", required=True, type=Path); ap.add_argument("--inputs", required=True, type=Path); ap.add_argument("--repo", required=True, type=Path); ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: output must be fresh")
    try:
        if any(path.is_symlink() or not path.is_file() or path.stat().st_size > MAX_JSON for path in (args.normalized, args.inputs)):
            raise Hold("normalizer controls input exceeds bounded JSON read")
        baseline = json.loads(args.normalized.read_text(encoding="utf-8-sig"))
        inputs = json.loads(args.inputs.read_text(encoding="utf-8-sig"))
        root = args.repo.resolve()
        normalizer.validate_normalized(baseline, inputs, root)
        validate(baseline)
        faults = []
        bad_case = copy.deepcopy(baseline); bad_case["captures"][0]["case"]["id"] = "legacy-plan-case"; faults.append(reject("legacy-case", bad_case, inputs, root))
        bad_host = copy.deepcopy(baseline); bad_host["captures"][0]["meta"]["host"]["hash"] = "sha256:" + "0" * 64; faults.append(reject("compile-exe-join", bad_host, inputs, root))
        bad_uia = copy.deepcopy(baseline); bad_uia["captures"][0]["meta"]["conditions"]["readerEvidence"]["uiaSha256"] = "sha256:" + "0" * 64; faults.append(reject("uia-paint-proof", bad_uia, inputs, root))
        missing_pixels = copy.deepcopy(baseline); del missing_pixels["captures"][0]["meta"]["conditions"]["readerEvidence"]["pixelsReceiptSha256"]; faults.append(reject("pixels-receipt", missing_pixels, inputs, root))
        bad_image = copy.deepcopy(baseline); bad_image["captures"][0]["images"][0]["hash"] = "sha256:" + "0" * 64; faults.append(reject("printwindow-image-join", bad_image, inputs, root))
        output = {"schema": "factory-native-count20-r17-normalizer-controls-v12", "status": "baseline-admitted-faults-rejected", "count": 20, "faultControls": faults, "nativeActions": 0, "lockActions": 0, "qualification": "source-control-only"}
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True); args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": output["status"], "faults": len(output["faultControls"]), "nativeActions": 0, "lockActions": 0}, sort_keys=True)); return 0


if __name__ == "__main__":
    raise SystemExit(main())
