#!/usr/bin/env python3
"""CLI for bounded overlay-aware Count1 adapter successor."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path, PurePosixPath
import importlib.util

_HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("adapter_v4", _HERE / "adapter-v4.py")
if _spec is None or _spec.loader is None:
    raise RuntimeError("adapter-v4 import unavailable")
_mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_mod)


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inputs", required=True, type=Path)
    parser.add_argument("--archive-root", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    if args.output.exists():
        raise SystemExit("HOLD: refusing to overwrite output")
    root = args.archive_root.resolve()
    inputs = read_json(args.inputs)

    def read_bytes(ref):
        path = ref.get("path")
        parsed = PurePosixPath(path) if isinstance(path, str) else PurePosixPath(".")
        if parsed.is_absolute() or str(parsed) != path or ".." in parsed.parts or "\\" in path or ":" in path:
            raise ValueError("unsafe archive ref")
        file = (root / Path(*parsed.parts)).resolve()
        file.relative_to(root)
        raw = file.read_bytes()
        if "sha256:" + hashlib.sha256(raw).hexdigest() != ref.get("sha256") or len(raw) != ref.get("bytes"):
            raise ValueError("archive byte/hash mismatch")
        return raw

    result = _mod.normalize(inputs, read_bytes)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2, sort_keys=True)
        handle.write("\n")
    typed_status = result.get("typedStatus", "held")
    summary = {
        "status": typed_status,
        "typedStatus": typed_status,
        "qualified": result.get("qualified"),
        "nativeParity": result.get("nativeParity"),
        "issues": result.get("issues", []),
    }
    print(json.dumps(summary, sort_keys=True))
    return 0 if typed_status == "normalized-observational" else 2


if __name__ == "__main__":
    raise SystemExit(main())
