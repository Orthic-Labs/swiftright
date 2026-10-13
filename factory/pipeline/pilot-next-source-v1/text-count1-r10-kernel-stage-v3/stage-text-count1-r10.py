#!/usr/bin/env python3
"""Bounded source-only Text Count1 r10 packer.

Donor files stay immutable.  Fresh plan, case, tuple, compile receipt &
serializer receipt are measured inputs supplied by caller; no qualification is
created by this tool.
"""
from __future__ import annotations
import argparse, hashlib, json, os, re, stat, zipfile
from pathlib import Path

MAX_FILE = 64 * 1024 * 1024
MAX_JSON = 2 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
MAX_FILES = 256
HEX64 = re.compile(r"^[0-9a-f]{64}$")

def fail(msg: str) -> None:
    raise SystemExit("text-count1-r10: " + msg)

def regular(path: Path, limit: int = MAX_FILE) -> os.stat_result:
    try:
        st = path.lstat()
    except OSError as exc:
        fail(f"stat failed: {path}: {exc}")
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode):
        fail(f"regular non-reparse file required: {path}")
    if st.st_size > limit:
        fail(f"file exceeds bound: {path}")
    return st

def safe_rel(raw: str) -> str:
    if not isinstance(raw, str) or not raw or raw.startswith(("/", "\\")) or ":" in raw or "\\" in raw:
        fail(f"unsafe relative path: {raw!r}")
    parts = raw.split("/")
    if any(p in ("", ".", "..") for p in parts):
        fail(f"unsafe relative path: {raw!r}")
    return raw

def stream(path: Path, limit: int = MAX_FILE) -> tuple[int, str, bytes | None]:
    st = regular(path, limit)
    digest = hashlib.sha256(); total = 0; data = bytearray() if st.st_size <= MAX_JSON else None
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(1024 * 1024)
            if not chunk: break
            total += len(chunk)
            if total > limit: fail(f"file grew past bound: {path}")
            digest.update(chunk)
            if data is not None: data.extend(chunk)
    if total != st.st_size: fail(f"file changed while reading: {path}")
    return total, digest.hexdigest(), bytes(data) if data is not None else None

def load_json(path: Path) -> tuple[object, int, str]:
    n, h, data = stream(path, MAX_JSON)
    if data is None: fail(f"JSON exceeds bound: {path}")
    try: value = json.loads(data.decode("utf-8-sig"))
    except Exception as exc: fail(f"invalid JSON {path}: {exc}")
    return value, n, h

def dump_json(path: Path, value: object) -> tuple[int, str]:
    data = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
    if len(data) > MAX_JSON: fail(f"generated JSON exceeds bound: {path}")
    if path.exists() or path.is_symlink(): fail(f"fresh output collision: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as fh: fh.write(data)
    return len(data), hashlib.sha256(data).hexdigest()

def rewrite_json(path: Path, value: object) -> tuple[int, str]:
    data = (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
    if len(data) > MAX_JSON: fail(f"generated JSON exceeds bound: {path}")
    if path.is_symlink() or not path.is_file(): fail(f"existing regular JSON required: {path}")
    tmp = path.with_name(path.name + ".rewrite")
    if tmp.exists() or tmp.is_symlink(): fail(f"rewrite collision: {tmp}")
    with tmp.open("xb") as fh: fh.write(data)
    os.replace(tmp, path)
    return len(data), hashlib.sha256(data).hexdigest()

def copy_bytes(src: Path, dst: Path, size: int, digest: str) -> None:
    regular(src)
    if dst.exists() or dst.is_symlink(): fail(f"fresh output collision: {dst}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    h = hashlib.sha256(); total = 0
    with src.open("rb") as rf, dst.open("xb") as wf:
        while True:
            chunk = rf.read(1024 * 1024)
            if not chunk: break
            total += len(chunk)
            if total > MAX_FILE: fail(f"copy exceeds bound: {src}")
            h.update(chunk); wf.write(chunk)
    if total != size or h.hexdigest() != digest: fail(f"copy drift: {src}")

def literal_paths(text: str, replacements: list[tuple[str, str]]) -> str:
    for old, new in sorted(replacements, key=lambda pair: len(pair[0]), reverse=True):
        if old and old != new:
            text = text.replace(old, new)
    return text

def remap_value(value: object, replacements: list[tuple[str, str]]) -> object:
    if isinstance(value, str): return literal_paths(value, replacements)
    if isinstance(value, list): return [remap_value(item, replacements) for item in value]
    if isinstance(value, dict): return {key: remap_value(item, replacements) for key, item in value.items()}
    return value

def fix_expected_exe_hash(rel: str, text: str) -> str:
    """Make each retained-handle cleanup call carry exactly one verified hash.

    ExeHash is a mandatory, validated capture parameter.  Worker exeHash is
    computed from the retained executable before launch.  Existing source
    initialization is preserved; only duplicate/missing call arguments change.
    """
    if not rel.endswith(("capture-text-single-v3.ps1", "capture-text-count1-v1.ps1")):
        if not rel.endswith(("uia-worker-invoke-v2.ps1", "invoke-worker-mta.ps1", "invoke-worker.ps1")):
            return text
        variable = "$exeHash"
        times = r"(?:\$startedAt|\$ownedStartedAt)"
    else:
        variable = "$ExeHash"
        times = r"(?:\$ownedStartedAt|\$startedAt)"
    pattern = re.compile(r"Invoke-FactoryOwnedCleanup\s+\$p\s+\$exe\s+" + times + r"(?:\s+-ExpectedExeHash\s+[^\s}]+)*\s+-KnownStartedIdentity")
    def replace(match: re.Match[str]) -> str:
        prefix = re.sub(r"\s+-ExpectedExeHash\s+[^\s}]+", "", match.group(0))
        return prefix.replace(" -KnownStartedIdentity", f" -ExpectedExeHash {variable} -KnownStartedIdentity")
    return pattern.sub(replace, text)

def validate_cleanup_calls(rel: str, text: str) -> None:
    if "Invoke-FactoryOwnedCleanup" not in text: return
    for line in text.splitlines():
        if "Invoke-FactoryOwnedCleanup" not in line: continue
        if line.count("-ExpectedExeHash") > 1: fail(f"duplicate ExpectedExeHash at {rel}")
        if "-KnownStartedIdentity" in line and "-ExpectedExeHash" not in line:
            fail(f"unbound ExpectedExeHash at {rel}")

def load_rows(path: Path) -> list[dict[str, object]]:
    value, _, _ = load_json(path)
    rows = value.get("files") if isinstance(value, dict) else value
    if not isinstance(rows, list) or not rows or len(rows) > MAX_FILES: fail("source list must contain bounded rows")
    out=[]; seen=set(); total=0
    for row in rows:
        if not isinstance(row, dict): fail("invalid source row")
        rel=safe_rel(row.get("path")); n=int(row.get("bytes", -1)); h=str(row.get("sha256", "")).lower().replace("sha256:", "")
        if n < 0 or n > MAX_FILE or not HEX64.fullmatch(h) or rel in seen: fail(f"invalid source row: {rel}")
        seen.add(rel); total += n; out.append({"path": rel, "bytes": n, "sha256": h})
    if total > MAX_TOTAL: fail("source list exceeds total bound")
    return out

def validate_fresh(plan: dict, plan_hash: str, case: dict, case_hash: str, tuple_doc: dict, receipt: dict, serializer: Path) -> dict[str, object]:
    if plan.get("kind") != "factory-text-compiler-plan-v1" or plan.get("candidate") != "swiftui.text.layout.baseline.pilot-next": fail("fresh plan kind/candidate mismatch")
    if plan.get("executionEligible") is not True or plan.get("hostMode") != "renderer": fail("fresh plan is not final renderer plan")
    if not isinstance(plan.get("case"), dict) or plan["case"].get("id") != case.get("id"): fail("fresh case identity mismatch")
    if str(plan["case"].get("hash", "")).replace("sha256:", "").lower() != case_hash: fail("fresh case canonical/raw hash mismatch")
    if not isinstance(plan.get("tuple"), dict) or plan["tuple"].get("id") != tuple_doc.get("id"): fail("fresh tuple identity mismatch")
    if case.get("kind") not in ("case", "factory-case") or not tuple_doc.get("id"): fail("fresh case/tuple schema mismatch")
    if receipt.get("kind") != "factory-text-owned-compile-v1" or receipt.get("exitCode") != 0: fail("compile receipt is not successful measured Text receipt")
    for key in ("streamsSealed", "streamDrainComplete", "originalHandleRetained", "ownedExited"):
        if receipt.get(key) is not True: fail(f"compile receipt missing {key}")
    if receipt.get("jobActiveCount") != 0 or receipt.get("kernelWait") != 0: fail("compile receipt termination proof missing")
    exe = str(receipt.get("exeSha256") or receipt.get("exeHash") or "").lower().replace("sha256:", "")
    source = str(receipt.get("sourceHash") or plan.get("sourceHash") or "")
    if not HEX64.fullmatch(exe) or not source: fail("measured executable/source hash missing")
    if str(receipt.get("planSha256", "")).replace("sha256:", "").lower() != plan_hash: fail("compile receipt plan hash mismatch")
    if str(receipt.get("sourceHash", "")) != str(plan.get("sourceHash", "")): fail("compile receipt source hash mismatch")
    if str(receipt.get("rendererSha256", "")) != str(plan.get("rendererSha256", "")): fail("compile receipt renderer hash mismatch")
    sn, sh, _ = stream(serializer, MAX_JSON)
    return {"planHash": "", "caseID": case["id"], "tupleID": tuple_doc["id"], "sourceHash": source, "exeHash": exe, "serializerControlSha256": sh, "serializerBytes": sn}

def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument("--donor-root", required=True); ap.add_argument("--output-root", required=True); ap.add_argument("--source-list", required=True)
    ap.add_argument("--plan", required=True); ap.add_argument("--case", required=True); ap.add_argument("--tuple", required=True); ap.add_argument("--compile-receipt", required=True); ap.add_argument("--serializer", required=True)
    ap.add_argument("--cleanup-helper", required=True); ap.add_argument("--namespace", default="text-mta-r11-count1-r10"); ap.add_argument("--old-namespace", default="text-mta-r11-count1-r9")
    ap.add_argument("--path-replace", action="append", default=[], metavar="OLD=NEW", help="exact measured Windows path token replacement; repeatable")
    ap.add_argument("--zip-path"); ap.add_argument("--installer-path")
    args=ap.parse_args(); donor=Path(args.donor_root); out=Path(args.output_root)
    if out.exists(): fail(f"fresh output exists: {out}")
    rows=load_rows(Path(args.source_list)); plan,plan_n,plan_h=load_json(Path(args.plan)); case,case_n,case_h=load_json(Path(args.case)); tup,tup_n,tup_h=load_json(Path(args.tuple)); receipt,receipt_n,receipt_h=load_json(Path(args.compile_receipt)); fresh=validate_fresh(plan,plan_h,case,case_h,tup,receipt,Path(args.serializer))
    helper=Path(args.cleanup_helper); helper_n,helper_h,helper_data=stream(helper); helper_text=helper_data.decode("utf-8", "strict") if helper_data is not None else ""
    if not helper_text or "Invoke-FactoryOwnedCleanup" not in helper_text or "ExpectedExeHash" not in helper_text: fail("successor cleanup helper lacks retained-handle hash gate")
    replacements=[(args.old_namespace,args.namespace)]
    for item in args.path_replace:
        if "=" not in item: fail("--path-replace requires OLD=NEW")
        old,new=item.split("=",1)
        if not old or not new: fail("empty --path-replace token")
        replacements.append((old,new))
    # Frozen r5g cleanup pin is replaced only by explicitly supplied successor
    # helper.  Other helper roles remain byte-bound to donor rows.
    donor_cleanup_hash="a9386ddd954490a0da9565211248944ebeb5a27492465512f0e9a55f9dbf2bd7"
    replacements.append((donor_cleanup_hash, helper_h))
    staged=[]; total=0
    for row in rows:
        rel=str(row["path"]); src=donor/rel; n,h,data=stream(src)
        if rel == "stage-manifest.json":
            continue
        if n != row["bytes"] or h != row["sha256"]: fail(f"donor row drift: {rel}")
        if rel == "producer/support/cleanup.ps1": data=helper_data
        elif data is not None and rel.endswith((".ps1", ".json", ".md")):
            text=data.decode("utf-8", "strict"); text=literal_paths(text,replacements); text=fix_expected_exe_hash(rel,text); validate_cleanup_calls(rel,text); data=text.encode()
        dst=out/rel
        if data is None: copy_bytes(src,dst,n,h); out_n,out_h=n,h
        else:
            if dst.exists() or dst.is_symlink(): fail(f"fresh output collision: {dst}")
            dst.parent.mkdir(parents=True,exist_ok=True); dst.write_bytes(data); out_n,out_h=len(data),hashlib.sha256(data).hexdigest()
        total += out_n
        if total > MAX_TOTAL: fail("staged graph exceeds total bound")
        staged.append({"path":rel,"donorBytes":n,"donorSha256":h,"bytes":out_n,"sha256":out_h,"transformed":out_h != h})
    if not (out/"admission/source-inputs.json").is_file(): fail("staged source-inputs missing")
    si,_,_=load_json(out/"admission/source-inputs.json")
    if not isinstance(si,dict): fail("source-inputs must be object")
    si=remap_value(si,replacements)
    si.update({"kind":"factory-text-source-inputs-v1","count":1,"caseID":case["id"],"caseHash":str(plan["case"]["hash"]).replace("sha256:","").lower(),"tupleID":tup["id"],"tupleHash":tup_h,"sourceHash":fresh["sourceHash"],"planHash":plan_h,"compileReceiptHash":receipt_h,"exeHash":fresh["exeHash"],"serializerControlSha256":fresh["serializerControlSha256"],"serializerBytes":fresh["serializerBytes"],"planRef":{"path":"external/fresh-plan.json","sha256":plan_h,"bytes":plan_n},"caseRef":{"path":"external/fresh-case.json","sha256":case_h,"bytes":case_n},"tupleRef":{"path":"external/fresh-tuple.json","sha256":tup_h,"bytes":tup_n},"compileReceiptRef":{"path":"external/fresh-compile-receipt.json","sha256":receipt_h,"bytes":receipt_n},"serializerRef":{"path":"external/fresh-serializer.json","sha256":fresh["serializerControlSha256"],"bytes":fresh["serializerBytes"]},"successorCleanupHelperSha256":helper_h,"successorCleanupHelperBytes":helper_n,"nativeWindowActions":0,"compilerActions":0,"lockActions":0})
    si_n,si_h=rewrite_json(out/"admission/source-inputs.json",si)
    staged=[row for row in staged if row["path"] != "stage-manifest.json" and row["path"] != "admission/source-inputs.json"]
    stage_rows=staged+[{"path":"admission/source-inputs.json","bytes":si_n,"sha256":si_h}]
    stage_doc={"kind":"factory-text-mta-stage-v1","compilerActions":0,"files":stage_rows}
    stage_n,stage_h=dump_json(out/"stage-manifest.json",stage_doc)
    graph={"kind":"factory-text-count1-r10-kernel-source-graph-v1","profile":"text-count1-r10-kernel-authority-v1","namespace":args.namespace,"historicalDonor":str(donor),"donorMutated":False,"count":1,"count1Required":True,"count1CertificateRequired":True,"planRef":{"path":"external/fresh-plan.json","sha256":plan_h,"bytes":plan_n},"caseRef":{"path":"external/fresh-case.json","sha256":case_h,"bytes":case_n},"tupleRef":{"path":"external/fresh-tuple.json","sha256":tup_h,"bytes":tup_n},"compileReceiptRef":{"path":"external/fresh-compile-receipt.json","sha256":receipt_h,"bytes":receipt_n},"serializerRef":{"path":"external/fresh-serializer.json","sha256":fresh["serializerControlSha256"],"bytes":fresh["serializerBytes"]},"expectedExeHash":fresh["exeHash"],"successorCleanupHelperSha256":helper_h,"successorCleanupHelperBytes":helper_n,"sourceInputsHash":si_h,"sourceInputsBytes":si_n,"nativeWindowActions":0,"compilerActions":0,"lockActions":0,"rendererDeadlineSeconds":30,"exitDeadlineSeconds":15,"streamDrainMilliseconds":5000,"files":staged,"aggregateBytes":total}
    graph_n,graph_h=dump_json(out/"r10-source-graph.json",graph)
    manifest={"kind":"factory-text-count1-r10-stage-manifest-v1","files":staged+[{"path":"admission/source-inputs.json","bytes":si_n,"sha256":si_h},{"path":"stage-manifest.json","bytes":stage_n,"sha256":stage_h},{"path":"r10-source-graph.json","bytes":graph_n,"sha256":graph_h}],"fileCount":len(staged)+3,"payloadBytes":total+si_n+stage_n+graph_n,"maxFiles":MAX_FILES,"maxTotalBytes":MAX_TOTAL,"nativeWindowActions":0,"compilerActions":0,"lockActions":0}
    man_n,man_h=dump_json(out/"r10-stage-manifest.json",manifest)
    if args.zip_path:
        zp=Path(args.zip_path)
        if zp.exists(): fail(f"fresh ZIP exists: {zp}")
        zp.parent.mkdir(parents=True,exist_ok=True); entries=staged+[ {"path":"admission/source-inputs.json","bytes":si_n,"sha256":si_h},{"path":"stage-manifest.json","bytes":stage_n,"sha256":stage_h},{"path":"r10-source-graph.json","bytes":graph_n,"sha256":graph_h},{"path":"r10-stage-manifest.json","bytes":man_n,"sha256":man_h} ]
        if len(entries)>MAX_FILES: fail("ZIP file count exceeds bound")
        with zipfile.ZipFile(zp,"x",compression=zipfile.ZIP_DEFLATED) as z:
            for row in entries: z.write(out/row["path"],row["path"])
        zip_n,zip_h,_=stream(zp,MAX_TOTAL)
    else: zip_n=zip_h=None
    print(json.dumps({"status":"SOURCE_STAGE_READY","count":1,"namespace":args.namespace,"sourceGraphSha256":graph_h,"stageManifestSha256":man_h,"zipSha256":zip_h,"zipBytes":zip_n,"nativeWindowActions":0,"compilerActions":0,"lockActions":0},sort_keys=True))
    return 0

if __name__ == "__main__": raise SystemExit(main())
