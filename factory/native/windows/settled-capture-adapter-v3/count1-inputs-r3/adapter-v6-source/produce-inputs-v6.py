#!/usr/bin/env python3
"""Produce successor adapter inputs from explicit archived refs only.

This stage validates producer/overlay/issuer/tuple joins, then writes one fresh
v6 input document. It never discovers files, rewrites native observations, or
relabels frozen producer bytes.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json
from pathlib import Path, PurePosixPath

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("adapter_v6", HERE / "adapter-v6.py")
mod = importlib.util.module_from_spec(spec); assert spec.loader; spec.loader.exec_module(mod)
spec2 = importlib.util.spec_from_file_location("support_v5", HERE.parent / "adapter-v5-source" / "support-v5.py")
support = importlib.util.module_from_spec(spec2); assert spec2.loader; spec2.loader.exec_module(support)


def digest(raw: bytes) -> str:
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def safe_path(value: str) -> Path:
    p = PurePosixPath(value)
    if not isinstance(value, str) or not value or p.is_absolute() or str(p) != value or ".." in p.parts or "\\" in value or ":" in value:
        raise ValueError("unsafe archive ref path")
    return Path(*p.parts)


def produce(input_path: Path, root: Path) -> dict:
    document = json.loads(input_path.read_text(encoding="utf-8-sig"))
    if not isinstance(document, dict):
        raise ValueError("input map must be object")
    root = root.resolve()
    if not root.is_dir():
        raise ValueError("archive root is not directory")

    def read_bytes(ref):
        if not isinstance(ref, dict) or not isinstance(ref.get("path"), str):
            raise ValueError("archive ref object required")
        path = (root / safe_path(ref["path"])).resolve()
        path.relative_to(root)
        raw = path.read_bytes()
        if digest(raw) != ref.get("sha256") or (ref.get("bytes") not in (None, 0) and len(raw) != ref.get("bytes")):
            raise ValueError("archive ref byte/hash mismatch:" + ref["path"])
        return raw

    roles = document.get("roles")
    if not isinstance(roles, dict):
        raise ValueError("roles required")
    issued_ref = roles.get("issuedMetadata")
    issued = json.loads(read_bytes(issued_ref).decode("utf-8-sig"))
    count = issued.get("expectedCount")
    if count not in (1, 20):
        raise ValueError("expectedCount must be 1 or 20")
    # Successor support accepts exact frozen r4-r7/r2-r4 roots & prospective r8/r5.
    mod._overlay_v4(document, read_bytes)
    support.validate_issued_ids(issued, count, issued.get("runRoot"))
    support.validate_node_epochs(issued)

    # Every explicit ref is checked recursively. Windows producer path strings
    # remain metadata; only path/sha256/bytes ref objects are archive reads.
    seen = set()
    def check(value):
        if isinstance(value, dict):
            if {"path", "sha256", "bytes"}.issubset(value):
                marker = (value["path"], value["sha256"], value["bytes"])
                if marker not in seen:
                    seen.add(marker); read_bytes(value)
            for child in value.values(): check(child)
        elif isinstance(value, list):
            for child in value: check(child)
    check(document)
    if len(seen) < 1:
        raise ValueError("no archived refs admitted")
    output = json.loads(json.dumps(document))
    output["kind"] = "settled-capture-adapter-inputs-v6"
    output["version"] = 6
    output["successorProfile"] = {
        "kind": "factory-telemetry-successor-source-profile-v1",
        "profileSha256": support.PROFILE["baseProfileSha256"],
        "capturePlanSha256": support.PROFILE["capturePlanSha256"],
        "expectedCount": count,
        "overlayRoot": document["executionOverlay"]["overlayRoot"],
        "validatedRefs": len(seen),
        "nativeActions": 0,
        "qualification": "source-admitted-observation-only",
    }
    return output


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-map", required=True, type=Path)
    ap.add_argument("--archive-root", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists(): raise SystemExit("HOLD: refusing to overwrite output")
    try: out = produce(args.input_map, args.archive_root)
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as h: json.dump(out, h, indent=2, sort_keys=True); h.write("\n")
    print(json.dumps({"status":"produced-source-admitted-v6", "count":out["successorProfile"]["expectedCount"], "overlayRoot":out["successorProfile"]["overlayRoot"], "nativeActions":0}, sort_keys=True))
    return 0

if __name__ == "__main__": raise SystemExit(main())
