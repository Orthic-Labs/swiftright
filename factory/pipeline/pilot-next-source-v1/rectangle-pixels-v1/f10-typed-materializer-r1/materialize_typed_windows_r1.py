#!/usr/bin/env python3
"""Materialize measured Rectangle Windows20 bytes into F10 reader archives.

This source is source-bound only: it derives typed observational captures from
immutable native rows, then binds every gate input to exact bytes. It never
sets qualification, parity, or semantic verdicts.
"""
from __future__ import annotations
import argparse, hashlib, json, os, shutil, stat
from pathlib import Path, PurePosixPath
from typing import Any

MAX_JSON = 2 * 1024 * 1024
MAX_FILE = 16 * 1024 * 1024
MAX_ARCHIVE_BYTES = 32 * 1024 * 1024
MAX_ARCHIVE_FILES = 512
MAX_RUNS = 20
ROLES = ("outcome", "observation", "owned", "close", "plan", "compile", "witness", "exe", "renderer", "runtimeReceipt", "runtimeTree", "stdout", "stderr")

class InputError(ValueError): pass

def read_bytes(path: Path, limit: int = MAX_FILE) -> bytes:
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode) or st.st_size > limit:
        raise InputError(f"regular bounded file required: {path}")
    out = bytearray()
    with path.open("rb") as f:
        while len(out) <= limit:
            chunk = f.read(min(1024 * 1024, limit + 1 - len(out)))
            if not chunk: break
            out.extend(chunk)
            if len(out) > limit: raise InputError(f"file exceeds bound: {path}")
    return bytes(out)

def read_json(path: Path) -> Any:
    raw = read_bytes(path, MAX_JSON)
    try: return json.loads(raw.decode("utf-8-sig"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc: raise InputError(f"invalid JSON: {path}") from exc

def sha(raw: bytes) -> str: return "sha256:" + hashlib.sha256(raw).hexdigest()
def file_sha(path: Path, limit: int = MAX_FILE) -> str:
    st = path.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode) or st.st_size > limit:
        raise InputError(f"bounded hash file required: {path}")
    h = hashlib.sha256()
    total = 0
    with path.open("rb") as stream:
        while True:
            chunk = stream.read(min(1024 * 1024, limit + 1 - total))
            if not chunk: break
            total += len(chunk)
            if total > limit: raise InputError(f"file exceeds hash bound: {path}")
            h.update(chunk)
    return "sha256:" + h.hexdigest()
def ensure_digest(value: Any, label: str) -> str:
    if not isinstance(value, str): raise InputError(f"{label} hash missing")
    value = value if value.startswith("sha256:") else "sha256:" + value
    if len(value) != 71 or any(c not in "0123456789abcdef" for c in value[7:]): raise InputError(f"{label} hash invalid")
    return value

def safe_rel(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value or "\\" in value or "\x00" in value or value.startswith("/"):
        raise InputError(f"{label} path unsafe")
    p = PurePosixPath(value)
    if str(p) != value or ".." in p.parts or value in (".", ".."): raise InputError(f"{label} path unsafe")
    return value

def checked_root(path: Path, label: str) -> Path:
    path = Path(os.path.abspath(path))
    st = path.lstat()
    if not stat.S_ISDIR(st.st_mode) or stat.S_ISLNK(st.st_mode): raise InputError(f"{label} must be non-symlink directory")
    return path

def require_file(root: Path, rel: str, label: str) -> Path:
    rel = safe_rel(rel, label)
    root = checked_root(root, label + " root")
    current = root
    parts = PurePosixPath(rel).parts
    for part in parts[:-1]:
        current = current / part
        st = current.lstat()
        if stat.S_ISLNK(st.st_mode) or not stat.S_ISDIR(st.st_mode): raise InputError(f"{label} directory component unsafe")
    p = current / parts[-1]
    st = p.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode): raise InputError(f"{label} must be regular non-symlink")
    return p

def canonical(value: Any) -> str:
    # Matches factory.core.artifacts canonical_hash without importing mutable runtime.
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
    return sha(raw)

def bounded_link(src: Path, dst: Path, expected: str, expected_bytes: int | None = None) -> dict[str, Any]:
    src = src.resolve(strict=True); st = src.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode): raise InputError(f"source not regular: {src}")
    if st.st_size > MAX_FILE: raise InputError(f"source too large: {src}")
    if expected_bytes is not None and st.st_size != expected_bytes: raise InputError(f"source byte count mismatch: {src}")
    actual = file_sha(src)
    if actual != expected: raise InputError(f"source hash mismatch: {src}")
    if dst.is_symlink(): raise InputError(f"destination symlink forbidden: {dst}")
    if dst.exists():
        if not dst.is_file() or file_sha(dst) != expected or dst.stat().st_size != st.st_size:
            raise InputError(f"destination byte collision: {dst}")
        return {"path": str(dst), "source": str(src), "bytes": st.st_size, "sha256": actual, "materialization": "existing-verified"}
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(src, dst)
        mode = "hardlink"
    except OSError:
        # Explicit bounded copy fallback; never follows a destination symlink.
        with src.open("rb") as inp, dst.open("xb") as out:
            copied = 0
            while copied <= MAX_FILE:
                chunk = inp.read(min(1024 * 1024, MAX_FILE + 1 - copied))
                if not chunk: break
                out.write(chunk); copied += len(chunk)
            if copied != st.st_size: raise InputError(f"bounded copy count mismatch: {src}")
        mode = "copy"
    return {"path": str(dst), "source": str(src), "bytes": st.st_size, "sha256": actual, "materialization": mode}

def manifest_rows(doc: Any) -> dict[str, dict[str, Any]]:
    if not isinstance(doc, dict) or not isinstance(doc.get("files"), list) or not doc["files"] or len(doc["files"]) > 2048:
        raise InputError("export manifest files must be bounded nonempty list")
    out = {}
    for item in doc["files"]:
        if not isinstance(item, dict): raise InputError("manifest row object required")
        rel = safe_rel(item.get("path"), "manifest")
        if rel in out: raise InputError(f"duplicate manifest row: {rel}")
        n = item.get("bytes"); d = ensure_digest(item.get("sha256"), f"manifest:{rel}")
        if type(n) is not int or n < 0 or n > MAX_FILE: raise InputError(f"manifest bytes invalid: {rel}")
        out[rel] = {"path": rel, "bytes": n, "sha256": d}
    return out

def archive_role(archive: Path, label: str, source: Path, digest: str, n: int, records: list[dict]) -> str:
    dest = archive / label
    records.append(bounded_link(source, dest, digest, n))
    return label

def source_bindings(plan: dict, host_root: Path, runtime_root: Path, tree: list[dict], archive: Path, records: list[dict]) -> tuple[list[dict], list[dict]]:
    hs = plan.get("sourceBindings")
    if not isinstance(hs, list) or not hs: raise InputError("plan sourceBindings missing")
    host = []
    for item in hs:
        rel = safe_rel(item.get("path"), "host source")
        d = ensure_digest(item.get("sha256"), f"host:{rel}")
        src = require_file(host_root, rel, f"host:{rel}")
        n = src.stat().st_size
        archive_role(archive, "host/" + rel, src, d, n, records)
        host.append({"path": rel, "bytes": n, "sha256": d})
    if not isinstance(tree, list) or not tree: raise InputError("runtime source tree missing")
    runtime = []
    for item in tree:
        rel = safe_rel(item.get("path"), "runtime source")
        d = ensure_digest(item.get("sha256"), f"runtime:{rel}")
        src = require_file(runtime_root, rel, f"runtime:{rel}")
        n = src.stat().st_size
        archive_role(archive, "runtime/" + rel, src, d, n, records)
        runtime.append({"path": rel, "bytes": n, "sha256": d})
    return host, runtime

def build_capture(run: int, row: dict, plan: dict, compile_doc: dict, tuple_doc: dict, outcome: dict, proof: dict, obs_hash: str, identity: dict) -> dict:
    source = ensure_digest(plan.get("sourceHash"), "sourceHash")
    exe = ensure_digest(row.get("exeSha256"), "row exe")
    renderer = ensure_digest(row.get("rendererSha256"), "row renderer")
    capture = {
        "platform": "windows",
        "case": plan["case"],
        "tuple": tuple_doc["tuple"],
        "provenance": {"sourceHash": source, "captureID": identity["captureID"], "imageID": identity["imageID"], "producer": "factory/pipeline/pilot-next-source-v1/rectangle-pixels-v1/f10-typed-materializer-r1/materialize_typed_windows_r1.py", "nativeParity": "hold"},
        "meta": {
            "run": run,
            "host": {"hash": exe, "kind": "owned-renderer"},
            "clock": {"correlationHash": obs_hash, "identity": identity["measuredClockIdentity"]},
            "measuredHostIdentity": identity["measuredHostIdentity"],
            "compile": {"request": plan["compileRequest"], "measuredArgv": compile_doc["argv"], "planSha256": compile_doc["planSha256"], "compileReceiptSha256": proof["compile"]["hash"]},
            "conditions": {
                "actualSourceHash": source,
                "actualHostExecutableHash": exe,
                "actualRendererHash": renderer,
                "rawReceiptHash": obs_hash,
                "nativeParity": "hold",
                "windowsExitProof": {"version": 1, "files": proof},
            },
        },
    }
    return capture

def materialize(args: argparse.Namespace) -> int:
    raw_root = checked_root(args.raw_root, "raw root"); artifact_root = checked_root(args.artifact_root, "artifact root"); out = Path(os.path.abspath(args.output_root))
    if out.exists(): raise InputError("output root must be fresh")
    export_path = raw_root / "export-manifest.json"; export = read_json(export_path); rows = manifest_rows(export)
    if export.get("kind") != "factory-native-observation-export-v1": raise InputError("native export kind mismatch")
    if export.get("count") != len(rows) or len(rows) < MAX_RUNS: raise InputError("native manifest declared count mismatch")
    input_map = read_json(args.input_map.resolve(strict=True))
    if input_map.get("kind") != "factory-rectangle-f10-adapter-input-v3" or input_map.get("status") != "ready-for-root-materialization" or input_map.get("qualified") is not False:
        raise InputError("F10 input map is not ready observational input")
    source_meta = input_map.get("source", {})
    if source_meta.get("manifestSha256") != file_sha(export_path) or source_meta.get("requiredCount") != MAX_RUNS:
        raise InputError("input map/native export identity mismatch")
    if input_map.get("export", {}).get("declaredCount") != len(rows):
        raise InputError("input map dynamic native row count mismatch")
    plan = read_json(raw_root / "native/plan.json"); compile_doc = read_json(raw_root / "native/observation.json")
    observations = read_json(raw_root / "native/native-observation.json")
    if not isinstance(observations, list) or len(observations) != MAX_RUNS: raise InputError("native observation must contain exactly20 rows")
    tuple_doc = read_json(raw_root / "admission/candidate-tuple.json"); binding = read_json(raw_root / "admission/candidate-binding.json")
    if not isinstance(tuple_doc.get("tuple"), dict) or not isinstance(tuple_doc["tuple"].get("id"), str): raise InputError("candidate tuple schema mismatch")
    if binding.get("case") != plan.get("case") or binding.get("sourceHash") != plan.get("sourceHash"): raise InputError("candidate/plan source identity mismatch")
    art_rows = manifest_rows(read_json(artifact_root / "export-manifest.json")); art_doc = read_json(artifact_root / "export-manifest.json")
    if art_doc.get("count") != 3: raise InputError("artifact export count mismatch")
    role_src = {}
    for item in art_doc.get("files", []):
        role = item.get("role"); rel = safe_rel(item.get("path"), "artifact")
        if role in role_src or rel not in art_rows: raise InputError("artifact role/path mismatch")
        role_src[role] = (artifact_root / rel, art_rows[rel])
    if set(role_src) != {"compiler", "exe", "renderer"}: raise InputError("artifact roles incomplete")
    runtime_root = checked_root(args.runtime_root, "runtime root"); host_root = checked_root(args.host_root, "host root")
    runtime_tree_doc = read_json(raw_root / "native/runtime-source-tree.json")
    if not isinstance(runtime_tree_doc, list) or not runtime_tree_doc: raise InputError("measured runtime tree missing")
    captures=[]; archives={}; archive_stats=[]; source_facts=[]
    for run in range(1, MAX_RUNS+1):
        row = observations[run-1]
        if row.get("index") != run or row.get("case") != plan.get("case"): raise InputError(f"row {run} identity mismatch")
        identity = read_json(raw_root / f"native/native-{run:02d}/measured-capture-identity.json")
        measured = identity.get("measuredHostIdentity")
        clock = identity.get("measuredClockIdentity")
        if identity.get("run") != run or not isinstance(identity.get("captureID"), str) or not isinstance(identity.get("imageID"), str): raise InputError(f"run {run} measured capture IDs missing")
        if not isinstance(measured, dict) or measured.get("hash") != ensure_digest(row.get("exeSha256"), f"run{run} host") or measured.get("pid") != row.get("ownedIdentity", {}).get("pid") or measured.get("path") != row.get("ownedIdentity", {}).get("path") or measured.get("startedAt") != row.get("ownedIdentity", {}).get("startedAt"): raise InputError(f"run {run} measured host identity mismatch")
        if not isinstance(clock, dict) or clock.get("clockId") != identity.get("plannedClockIdentity") or clock.get("crossProcessQualified") is not False: raise InputError(f"run {run} measured clock identity mismatch")
        rawrefs = row.get("files")
        if not isinstance(rawrefs, list) or not rawrefs: raise InputError(f"row {run} native files missing")
        run_dir = raw_root / f"native/native-{run:02d}"
        archive = out / "windows-archives" / f"pending-{run:02d}"
        archive.mkdir(parents=True, exist_ok=True)
        records=[]; raw_count=0
        # Dynamic closure: count exactly what row declares; do not assume legacy 24.
        for ref in rawrefs:
            rel=safe_rel(ref.get("path"), f"run{run} raw"); d=ensure_digest(ref.get("sha256"), f"run{run}:{rel}")
            src=require_file(run_dir, rel, f"run{run}:{rel}"); archive_role(archive, rel, src, d, src.stat().st_size, records); raw_count += 1
        obs_path=raw_root/"native/native-observation.json"; obs_digest=file_sha(obs_path)
        # Global roles are renamed into per-capture archive to keep proof refs safe & unique.
        globals_src={"observation":(obs_path,obs_digest),"plan":(raw_root/"native/plan.json",file_sha(raw_root/"native/plan.json")),"compile":(raw_root/"native/observation.json",file_sha(raw_root/"native/observation.json")),"runtimeReceipt":(raw_root/"native/runtime-source-receipt.json",file_sha(raw_root/"native/runtime-source-receipt.json")),"runtimeTree":(raw_root/"native/runtime-source-tree.json",file_sha(raw_root/"native/runtime-source-tree.json")),"witness":(raw_root/"native/Sources/FactoryProbe/Witness.swift",file_sha(raw_root/"native/Sources/FactoryProbe/Witness.swift"))}
        for name,(src,d) in globals_src.items(): archive_role(archive, {"observation":"native-observation.json","plan":"plan.json","compile":"observation.json","runtimeReceipt":"runtime-source-receipt.json","runtimeTree":"runtime-source-tree.json","witness":"Witness.swift"}[name], src, d, src.stat().st_size, records)
        run_dir=run_dir.resolve(strict=True)
        outcome_src=run_dir/"capture-outcome.json"; owned_src=run_dir/"owned-process.json"; close_src=run_dir/"owned-close.json"; stdout_src=run_dir/"host.stdout.txt"; stderr_src=run_dir/"host.stderr.txt"
        for p in (outcome_src,owned_src,close_src,stdout_src,stderr_src):
            if not p.exists(): raise InputError(f"run {run} required role missing: {p.name}")
        role_source={"outcome":outcome_src,"owned":owned_src,"close":close_src,"stdout":stdout_src,"stderr":stderr_src}
        for role,src in role_source.items(): archive_role(archive, {"outcome":"capture-outcome.json","owned":"owned-process.json","close":"owned-close.json","stdout":"host.stdout.txt","stderr":"host.stderr.txt"}[role], src, file_sha(src), src.stat().st_size, records)
        for role,(src,expected) in role_src.items(): archive_role(archive, {"compiler":"tool/compiler.bin","exe":"FactoryProbe.exe","renderer":"swiftright_render.dll"}[role], src, expected["sha256"], expected["bytes"], records)
        host, runtime = source_bindings(plan, host_root, runtime_root, runtime_tree_doc, archive, records)
        if len(records) > MAX_ARCHIVE_FILES: raise InputError(f"archive file count exceeds bound run{run}")
        archive_bytes = sum(item["bytes"] for item in records if item["materialization"] != "existing-verified")
        if archive_bytes > MAX_ARCHIVE_BYTES: raise InputError(f"archive byte bound exceeded run{run}")
        outcome=read_json(outcome_src); obs_hash="sha256:"+hashlib.sha256(read_bytes(obs_path)).hexdigest()
        proof={"outcome":{"path":"capture-outcome.json","hash":file_sha(outcome_src)},"observation":{"path":"native-observation.json","hash":obs_hash},"owned":{"path":"owned-process.json","hash":file_sha(owned_src)},"close":{"path":"owned-close.json","hash":file_sha(close_src)},"plan":{"path":"plan.json","hash":file_sha(raw_root/"native/plan.json")},"compile":{"path":"observation.json","hash":file_sha(raw_root/"native/observation.json")},"witness":{"path":"Witness.swift","hash":file_sha(raw_root/"native/Sources/FactoryProbe/Witness.swift")},"exe":{"path":"FactoryProbe.exe","hash":role_src["exe"][1]["sha256"]},"renderer":{"path":"swiftright_render.dll","hash":role_src["renderer"][1]["sha256"]},"runtimeReceipt":{"path":"runtime-source-receipt.json","hash":file_sha(raw_root/"native/runtime-source-receipt.json")},"runtimeTree":{"path":"runtime-source-tree.json","hash":file_sha(raw_root/"native/runtime-source-tree.json")},"stdout":{"path":"host.stdout.txt","hash":file_sha(stdout_src)},"stderr":{"path":"host.stderr.txt","hash":file_sha(stderr_src)}}
        capture=build_capture(run,row,plan,compile_doc,tuple_doc,outcome,proof,obs_hash,identity); cap_hash=canonical(capture).removeprefix("sha256:")
        final_archive=out/"windows-archives"/("capture-"+cap_hash); archive.rename(final_archive); archives[cap_hash]=str(final_archive.relative_to(out)); captures.append(capture)
        archive_stats.append({"run":run,"captureHash":cap_hash,"nativeFileCount":raw_count,"archiveFileCount":len(records),"sourceFacts":{"host":len(host),"runtime":len(runtime)}})
    reader_manifest={"version":1,"expectedWindows":20,"windowsCaptures":"typed-captures.json","windowsArchives":archives,"source":{"nativeManifestSha256":file_sha(raw_root/"export-manifest.json"),"inputMapSha256":file_sha(args.input_map.resolve(strict=True)),"artifactManifestSha256":file_sha(artifact_root/"export-manifest.json")},"comparison":{"status":"held-observation-only","nativeParity":"held","semantic":"held","timing":"raw-only"}}
    out.mkdir(parents=True,exist_ok=True); (out/"typed-captures.json").write_text(json.dumps({"typedStatus":"normalized-observational","captures":captures},indent=2,sort_keys=True)+"\n"); (out/"reader-input.json").write_text(json.dumps(reader_manifest,indent=2,sort_keys=True)+"\n")
    receipt={"schema":"factory-rectangle-f10-typed-materializer-r1","status":"typed-observational-only","qualified":False,"nativeParityGranted":False,"runCount":20,"nativeManifestRowCount":len(rows),"archiveStats":archive_stats,"source":{"rawRoot":str(raw_root),"artifactRoot":str(artifact_root),"runtimeRoot":str(runtime_root),"hostRoot":str(host_root),"inputMap":str(args.input_map.resolve(strict=True))},"proofRoles":list(ROLES)}
    (out/"materializer-receipt.json").write_text(json.dumps(receipt,indent=2,sort_keys=True)+"\n")
    return 0

def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--raw-root",type=Path,required=True); ap.add_argument("--artifact-root",type=Path,required=True); ap.add_argument("--runtime-root",type=Path,required=True); ap.add_argument("--host-root",type=Path,required=True); ap.add_argument("--input-map",type=Path,required=True); ap.add_argument("--output-root",type=Path,required=True); args=ap.parse_args()
    try: return materialize(args)
    except (InputError,OSError,KeyError,TypeError,ValueError) as exc: print(json.dumps({"status":"blocked","error":str(exc)})); return 2
if __name__ == "__main__": raise SystemExit(main())
