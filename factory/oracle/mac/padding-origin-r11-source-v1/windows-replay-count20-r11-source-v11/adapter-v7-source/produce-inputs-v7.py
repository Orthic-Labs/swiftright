#!/usr/bin/env python3
"""Fresh r11 Count20 input admission over frozen adapter-v6 producer logic."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
V6 = Path("factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/adapter-v6-source/produce-inputs-v6.py")
spec = importlib.util.spec_from_file_location("produce_inputs_v6", V6)
if spec is None or spec.loader is None:
    raise SystemExit("HOLD: frozen adapter-v6 producer unavailable")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

TUPLE_ID = "sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011"
CASE_ID = "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9"
CASE_HASH = "sha256:037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de"
SOURCE_HASH = "sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b"
MAC_HOST = "sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777"


def read_ref(ref: dict, root: Path) -> bytes:
    if not isinstance(ref, dict) or not isinstance(ref.get("path"), str):
        raise ValueError("archive ref required")
    path = (root.resolve() / ref["path"]).resolve()
    path.relative_to(root.resolve())
    raw = path.read_bytes()
    if "sha256:" + hashlib.sha256(raw).hexdigest() != ref.get("sha256") or len(raw) != ref.get("bytes"):
        raise ValueError("archive ref byte/hash mismatch: " + ref["path"])
    return raw


def validate_fresh(document: dict, root: Path) -> None:
    roles = document.get("roles")
    if not isinstance(roles, dict):
        raise ValueError("roles required")
    issued_ref = roles.get("issuedMetadata")
    if not isinstance(issued_ref, dict):
        raise ValueError("issued metadata ref required")
    issued = json.loads(read_ref(issued_ref, root).decode("utf-8-sig"))
    if issued.get("expectedCount") != 20 or issued.get("frozenTupleBound") is not False:
        raise ValueError("fresh Count20 metadata boundary mismatch")
    captures = issued.get("captures")
    if not isinstance(captures, list) or len(captures) != 20:
        raise ValueError("fresh Count20 capture cardinality mismatch")
    if sorted(c.get("run") for c in captures) != list(range(1, 21)):
        raise ValueError("fresh Count20 run sequence mismatch")
    if any(not isinstance(c.get("captureID"), str) or not c["captureID"].startswith("capture/") or len(c["captureID"]) != 40 for c in captures):
        raise ValueError("fresh capture provenance IDs missing")
    if any(not isinstance(c.get("imageID"), str) or not c["imageID"].startswith("image/") or len(c["imageID"]) != 38 for c in captures):
        raise ValueError("fresh image provenance IDs missing")
    if len({c["captureID"] for c in captures}) != 20 or len({c["imageID"] for c in captures}) != 20:
        raise ValueError("duplicate fresh capture/image provenance IDs")
    tuple_ref = roles.get("tuple")
    tuple_doc = json.loads(read_ref(tuple_ref, root).decode("utf-8-sig"))
    if tuple_doc.get("candidateID") != TUPLE_ID or tuple_doc.get("case", {}).get("id") != CASE_ID or tuple_doc.get("case", {}).get("hash") != CASE_HASH:
        raise ValueError("fresh tuple/case identity mismatch")
    value = tuple_doc.get("tuple", {})
    if value.get("hostHashes", {}).get("macos") != MAC_HOST or value.get("id") != TUPLE_ID:
        raise ValueError("fresh Mac tuple host join mismatch")
    if issued.get("sourceHash") != SOURCE_HASH:
        raise ValueError("fresh source hash mismatch")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--input-map", required=True, type=Path)
    ap.add_argument("--archive-root", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    args = ap.parse_args()
    if args.output.exists():
        raise SystemExit("HOLD: refusing to overwrite output")
    try:
        document = json.loads(args.input_map.read_text(encoding="utf-8-sig"))
        validate_fresh(document, args.archive_root)
        output = mod.produce(args.input_map, args.archive_root)
        output["kind"] = "settled-capture-adapter-inputs-v7-fresh-r11"
        output["version"] = 7
        output["freshSourceProfile"] = {"tupleID": TUPLE_ID, "caseID": CASE_ID, "sourceHash": SOURCE_HASH, "expectedCount": 20, "nativeActions": 0, "qualification": "source-admitted-observation-only"}
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("x", encoding="utf-8") as handle:
        json.dump(output, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(json.dumps({"status": "produced-fresh-r11-v7", "count": 20, "nativeActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
