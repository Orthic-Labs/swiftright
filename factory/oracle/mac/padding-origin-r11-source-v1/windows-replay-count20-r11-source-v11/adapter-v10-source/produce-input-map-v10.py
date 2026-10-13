#!/usr/bin/env python3
"""Strict v10 input-map producer with issued run/task lineage."""
from __future__ import annotations
import argparse, importlib.util, json, re, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
V9 = HERE.parent / "adapter-v9-source" / "produce-input-map-v9.py"
sys.path.insert(0, str(V9.parent))
spec = importlib.util.spec_from_file_location("adapter_input_map_v9", V9)
if spec is None or spec.loader is None:
    raise SystemExit("HOLD: frozen v9 input-map producer unavailable")
v9 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v9)
from bounded_io_v9 import beneath, output_path  # noqa: E402
from lineage_v10 import canonical_hash  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--template", type=Path, required=True)
    ap.add_argument("--template-native-root", type=Path, required=True)
    ap.add_argument("--template-metadata-root", type=Path, required=True)
    ap.add_argument("--template-overlay-root", type=Path, required=True)
    ap.add_argument("--metadata-root", type=Path, required=True)
    ap.add_argument("--native-root", type=Path, required=True)
    ap.add_argument("--overlay-root", type=Path, required=True)
    ap.add_argument("--issuer-source", type=Path, required=True)
    ap.add_argument("--issued-metadata", type=Path)
    ap.add_argument("--task-result", type=Path, required=True)
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--repo", type=Path, default=Path("."))
    ap.add_argument("--allow-pending", action="store_true")
    args = ap.parse_args()
    if args.allow_pending:
        raise SystemExit("HOLD: v10 task lineage requires completed task result; pending mode is forbidden")
    output_path(args.output)
    try:
        repo = args.repo.absolute()
        task_rel = args.task_result.as_posix()
        if args.task_result.is_absolute() or ":" in task_rel or "\\" in task_rel:
            raise ValueError("unsafe task-result path")
        ref = v9.ref(repo, Path(task_rel), False)
        task_ref = dict(ref)
        result = v9.build(args)
        if not isinstance(result.get("roles"), dict):
            raise ValueError("producer roles missing")
        issued_ref = result["roles"].get("issuedMetadata")
        if not isinstance(issued_ref, dict):
            raise ValueError("issued metadata ref missing")
        issued = v9.bounded_json(v9.beneath(repo, issued_ref["path"]))
        run_id = issued.get("runID")
        if not isinstance(run_id, str) or not re.fullmatch(r"[0-9a-f]{32}", run_id):
            raise ValueError("issued runID malformed")
        issued_hash = canonical_hash(issued_ref.get("sha256"))
        result["roles"]["taskResult"] = task_ref
        result["lineage"] = {"runID": run_id, "issuedMetadataSha256": issued_hash, "taskResult": task_ref}
        result["schema"] = "factory-native-count20-input-map-v10"
        result["pending"] = {"status": "ready-for-v10-normalization", "count": 20, "metadataFiles": 40, "nativeActions": 0, "lockActions": 0, "qualification": "hold-until-production-proof2-reader"}
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(result, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": result["pending"]["status"], "count": 20, "taskLineage": result["lineage"]["runID"], "nativeActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
