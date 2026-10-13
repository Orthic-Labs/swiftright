#!/usr/bin/env python3
"""Stage one measured MTA profile with exact replacements, then reseal closure refs.

This tool never edits sourceRoot.  Inputs are explicit; no recursive discovery is used.
It refuses ambiguous token replacement, unsafe paths, duplicate rows, stale source bytes,
and output overwrite.  It writes integration-bindings.json and source-inputs.json only
after every requested source mutation has completed, then emits a sealed receipt.
"""
from __future__ import annotations
import argparse, base64, hashlib, json, os, re, stat, sys
from pathlib import Path

CHUNK = 1024 * 1024
MAX_SOURCE = 64 * 1024 * 1024
MAX_JSON = 2 * 1024 * 1024
MAX_ROWS = 512
TOKEN = re.compile(rb"[A-Za-z0-9_-]")


def die(msg: str) -> None:
    raise SystemExit(f"mta-profile-repair: {msg}")


def regular(path: Path, limit: int) -> int:
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode):
        die(f"not a regular non-symlink file: {path}")
    if st.st_size > limit:
        die(f"file exceeds bound ({st.st_size}>{limit}): {path}")
    return st.st_size


def digest(path: Path, limit: int = MAX_SOURCE) -> tuple[int, str, bytes]:
    before = regular(path, limit)
    h = hashlib.sha256(); total = 0; chunks: list[bytes] = []
    with path.open("rb") as f:
        while True:
            b = f.read(CHUNK)
            if not b: break
            total += len(b)
            if total > limit: die(f"file grew past bound: {path}")
            h.update(b)
            chunks.append(b)
    after = regular(path, limit)
    if before != after or before != total:
        die(f"source changed while read: {path}")
    return total, h.hexdigest(), b"".join(chunks)


def safe_rel(raw: str) -> Path:
    if not isinstance(raw, str) or not raw or "\\" in raw:
        die(f"unsafe relative path: {raw!r}")
    p = Path(raw)
    if p.is_absolute() or any(part in ("", ".", "..") for part in p.parts):
        die(f"unsafe relative path: {raw!r}")
    return p


def json_bytes(path: Path) -> tuple[dict, bytes]:
    n, _, raw = digest(path, MAX_JSON)
    try:
        obj = json.loads(raw.decode("utf-8-sig"))
    except Exception as e:
        die(f"invalid JSON {path}: {e}")
    if not isinstance(obj, dict): die(f"JSON object required: {path}")
    return obj, raw


def token_replace(raw: bytes, old: bytes, new: bytes, label: str) -> bytes:
    if not old: die(f"empty replacement token: {label}")
    starts: list[int] = []; at = 0
    while True:
        i = raw.find(old, at)
        if i < 0: break
        left = raw[i - 1:i] if i else b""
        right_i = i + len(old)
        right = raw[right_i:right_i + 1]
        if (not left or not TOKEN.fullmatch(left)) and (not right or not TOKEN.fullmatch(right)):
            starts.append(i)
        at = i + 1
    if len(starts) != 1:
        die(f"replacement {label!r} matched {len(starts)} whole tokens; exact one required")
    i = starts[0]
    return raw[:i] + new + raw[i + len(old):]


def write_new(path: Path, raw: bytes) -> None:
    if path.exists() or path.is_symlink(): die(f"refusing overwrite: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as f:
        f.write(raw)


def canonical(obj: object) -> bytes:
    return (json.dumps(obj, sort_keys=True, indent=2, ensure_ascii=False) + "\n").encode()


def update_ref(obj: dict, key: str, path_value: str, n: int, sha: str) -> None:
    ref = obj.get(key)
    if isinstance(ref, dict):
        ref["path"] = path_value
        ref["bytes"] = n
        ref["sha256"] = "sha256:" + sha


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source-root", required=True, type=Path)
    ap.add_argument("--binding-template", required=True, type=Path)
    ap.add_argument("--source-inputs-template", required=True, type=Path)
    ap.add_argument("--replacement-manifest", required=True, type=Path)
    ap.add_argument("--output-root", required=True, type=Path)
    ap.add_argument("--profile", required=True, choices=("text", "circle"))
    ap.add_argument("--tag", required=True)
    ap.add_argument("--binding-kind", required=True)
    ap.add_argument("--binding-ref-path", required=True)
    ap.add_argument("--expected-path-fragment", required=True)
    args = ap.parse_args()

    src = args.source_root.resolve(); out = args.output_root
    if out.exists(): die(f"output root already exists: {out}")
    if not src.is_dir(): die(f"source root missing: {src}")
    binding, _ = json_bytes(args.binding_template)
    inputs, _ = json_bytes(args.source_inputs_template)
    spec, _ = json_bytes(args.replacement_manifest)
    if spec.get("profile") != args.profile or spec.get("tag") != args.tag:
        die("replacement manifest profile/tag does not match CLI")
    repl_by_path: dict[str, list[dict]] = {}
    for item in spec.get("replacements", []):
        if not isinstance(item, dict): die("replacement entries must be objects")
        rel = str(safe_rel(item.get("path")))
        old = base64.b64decode(item.get("oldB64", ""), validate=True)
        new = base64.b64decode(item.get("newB64", ""), validate=True)
        repl_by_path.setdefault(rel, []).append({"old": old, "new": new, "label": item.get("label", rel)})
    if len(repl_by_path) > MAX_ROWS: die("too many replacement paths")

    rows = binding.get("files")
    if not isinstance(rows, list) or not rows or len(rows) > MAX_ROWS:
        die("binding template files must be bounded nonempty list")
    seen: set[str] = set(); final_rows: list[dict] = []
    for row in rows:
        if not isinstance(row, dict): die("binding row must be object")
        rel_s = str(safe_rel(row.get("path")))
        if rel_s in seen: die(f"duplicate binding path: {rel_s}")
        seen.add(rel_s)
        source = src / rel_s
        n, sha, raw = digest(source)
        expected_n = row.get("bytes"); expected_sha = row.get("sha256")
        if expected_n != n or expected_sha != sha:
            die(f"template binding drift for {rel_s}; measured {n}/{sha}")
        for r in repl_by_path.get(rel_s, []):
            raw = token_replace(raw, r["old"], r["new"], str(r["label"]))
        # Replacement is applied in memory; a second hash is taken over final bytes.
        final_rows.append({"path": rel_s, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
        write_new(out / "producer" / rel_s, raw)

    # Explicit extra source files are staged only when listed; no directory discovery.
    extras = spec.get("extraFiles", [])
    if not isinstance(extras, list) or len(extras) > MAX_ROWS: die("invalid extraFiles")
    for raw_rel in extras:
        rel_s = str(safe_rel(raw_rel))
        if rel_s in seen: die(f"extra duplicates binding path: {rel_s}")
        seen.add(rel_s)
        source = src / rel_s
        _, _, raw = digest(source)
        for r in repl_by_path.get(rel_s, []):
            raw = token_replace(raw, r["old"], r["new"], str(r["label"]))
        write_new(out / "producer" / rel_s, raw)

    binding_final = {"files": sorted(final_rows, key=lambda x: x["path"]), "kind": args.binding_kind}
    binding_raw = canonical(binding_final)
    binding_out = out / "producer" / "integration-bindings.json"
    write_new(binding_out, binding_raw)
    bn, bsha, _ = digest(binding_out)

    # Only known closure fields are changed; all candidate/runtime/case fields stay measured inputs.
    inputs["integrationBindingsHash"] = bsha
    update_ref(inputs, "integrationBindingsRef", args.binding_ref_path, bn, bsha)
    for row in final_rows:
        if row["path"] == "dependencies/uia-worker/invoke-worker-mta.ps1":
            inputs["uiaWorkerHash"] = row["sha256"]
            update_ref(inputs, "uiaWorkerRef", args.binding_ref_path.replace("integration-bindings.json", "dependencies/uia-worker/invoke-worker-mta.ps1"), row["bytes"], row["sha256"])
        if row["path"] == "dependencies/uia-worker/worker-contract.json":
            inputs["workerContractHash"] = row["sha256"]
    if args.expected_path_fragment not in str(inputs.get("capturePlanPath", "")):
        die("source-inputs capturePlanPath does not contain expected measured profile fragment")
    inputs_raw = canonical(inputs)
    inputs_out = out / "admission" / "source-inputs.json"
    write_new(inputs_out, inputs_raw)
    in_n, in_sha, _ = digest(inputs_out, MAX_JSON)
    receipt = {
        "schema": "mta-profile-repair-receipt-v1",
        "status": "source-staged-reseal-required-review",
        "qualification": "held",
        "profile": args.profile,
        "tag": args.tag,
        "binding": {"path": "producer/integration-bindings.json", "bytes": bn, "sha256": "sha256:" + bsha},
        "sourceInputs": {"path": "admission/source-inputs.json", "bytes": in_n, "sha256": "sha256:" + in_sha},
        "replacementCount": sum(len(v) for v in repl_by_path.values()),
        "sourceRows": len(final_rows),
        "native": False,
        "remote": False,
        "tests": False,
    }
    write_new(out / "admission" / "mta-profile-repair-receipt.json", canonical(receipt))
    print(json.dumps(receipt, sort_keys=True))
    return 0

if __name__ == "__main__":
    main()
