"""Read-only actual archive v2 audit; no native/compiler execution."""
from __future__ import annotations
import hashlib, importlib.util, json, sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[5]))

ROOT = Path(__file__).resolve().parents[1]
ARCHIVE = ROOT / "archive"
MAP = json.loads((ROOT / "archive-map.json").read_text())
BY_HASH = {row["sha256"]: ROOT / row["path"] for row in MAP["files"]}
# Tool bytes are read only from current exact paths when archive has no tool copy.
TOOL_PATHS = {"/usr/bin/xcrun": Path("/usr/bin/xcrun"), "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend": Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend")}
READ_CACHE: dict[str, bytes] = {}
spec = importlib.util.spec_from_file_location("mac_origin_live", Path(__file__).resolve().parents[5] / "factory/gate/mac_origin_admission.py")
guard = importlib.util.module_from_spec(spec); assert spec.loader is not None; spec.loader.exec_module(guard)

def digest(raw: bytes) -> str: return "sha256:" + hashlib.sha256(raw).hexdigest()
def ref(path: Path) -> dict[str, object]:
    raw = path.read_bytes(); return {"path": str(path), "sha256": digest(raw), "bytes": len(raw)}
def reader(value: dict[str, object]) -> bytes:
    expected = value.get("sha256")
    if isinstance(expected, str) and expected in READ_CACHE:
        return READ_CACHE[expected]
    path = BY_HASH.get(expected)
    if path is None and str(value.get("path")) in TOOL_PATHS:
        path = TOOL_PATHS[str(value["path"])]
    if path is None: raise ValueError(f"unbound hash/path: {expected} {value.get('path')}")
    raw = path.read_bytes()
    if digest(raw) != expected: raise ValueError(f"hash mismatch: {path}")
    READ_CACHE[str(expected)] = raw
    return raw

def check_shape(case_dir: Path, summary: dict[str, object], failures: list[str]) -> dict[str, object]:
    cid = case_dir.name
    def fail(code: str, detail: str = ""): failures.append(f"{cid}:{code}" + (f":{detail}" if detail else ""))
    case_path = ROOT / "archive/inputs" / f"{cid}.json"
    archive_dir = ARCHIVE / cid
    witness, adapter, binary = archive_dir / "source/Witness.swift", archive_dir / "source/CaptureHost.swift", archive_dir / "binary/capture-host"
    generic_adapter = ROOT.parents[2] / "oracle/mac/seed-origin-v7/CaptureHost.swift"
    if not all(p.is_file() and p.stat().st_size > 0 for p in (case_path,witness,adapter,binary)): fail("archive-fields")
    expected_case = {"id":cid,"hash":digest(case_path.read_bytes())}
    if summary.get("case") != expected_case: fail("case-join")
    if summary.get("candidateOnly") is not True or summary.get("status") != "CANDIDATE_CAPTURED": fail("candidate-policy")
    if summary.get("sourceHash") != digest(witness.read_bytes()): fail("witness-join")
    if summary.get("adapterSourceHash") != digest(generic_adapter.read_bytes()) or summary.get("compiledAdapterHash") != digest(adapter.read_bytes()): fail("adapter-join")
    if summary.get("binaryHash") != digest(binary.read_bytes()): fail("binary-join")
    receipt = summary.get("compilerReceipt")
    receipt_path = case_dir / "compiler-receipt.json"
    if not isinstance(receipt, dict) or not receipt_path.is_file(): fail("receipt-missing"); return {"case":cid,"runs":len(summary.get("runs",[]))}
    if json.loads(receipt_path.read_text()) != receipt: fail("receipt-embedded-join")
    comp = receipt.get("compiler") if isinstance(receipt,dict) else None; resolver = receipt.get("resolver") if isinstance(receipt,dict) else None
    if receipt.get("status") != "SUCCESS" or receipt.get("sourceDrift") is not False or receipt.get("invocationMode") != "xcrun": fail("receipt-status")
    if not isinstance(comp,dict) or not isinstance(resolver,dict): fail("receipt-shape"); return {"case":cid,"runs":len(summary.get("runs",[]))}
    if resolver.get("argv") != ["/usr/bin/xcrun","--find","swiftc"] or resolver.get("exitCode") != 0: fail("resolver-argv-exit")
    if comp.get("argv") != ["/usr/bin/xcrun","swiftc","-parse-as-library","-O","-o",comp.get("outputBinary",{}).get("path"),comp.get("sourceBefore",{}).get("Witness.swift",{}).get("path"),comp.get("sourceBefore",{}).get("CaptureHost.swift",{}).get("path")]: fail("compiler-argv")
    if comp.get("exitCode") != 0 or comp.get("timedOut") is not False or comp.get("ownedProcessGroup") is not True or comp.get("pid") != comp.get("pgid"): fail("compiler-process")
    if resolver.get("exitCode") != 0 or resolver.get("ownedProcessGroup") is not True or resolver.get("pid") != resolver.get("pgid"): fail("resolver-process")
    if comp.get("sourceBefore") != comp.get("sourceAfter") or comp.get("realToolBefore") != comp.get("realToolAfter") or comp.get("realToolDrift") is not False: fail("source-tool-drift")
    if comp.get("sourceBefore",{}).get("Witness.swift",{}).get("sha256") != digest(witness.read_bytes()) or comp.get("sourceBefore",{}).get("CaptureHost.swift",{}).get("sha256") != digest(adapter.read_bytes()): fail("receipt-source-join")
    if comp.get("outputBinary",{}).get("sha256") != digest(binary.read_bytes()): fail("receipt-binary-join")
    for proc,label in ((resolver,"resolver"),(comp,"compiler")):
        cleanup=proc.get("cleanup",{})
        for key in ("timedOut","drainTimedOut","killSent","termSent","groupMissing"):
            if cleanup.get(key) is not False: fail("cleanup",label+"."+key)
        for stream in ("stdoutPath","stderrPath"):
            p=ROOT/Path(proc.get(stream,"")) if str(proc.get(stream,"")).startswith(str(ROOT)) else Path(proc.get(stream,""))
            if not p.is_file(): fail("stream-missing",label+"."+stream); continue
            key=stream.replace("Path","Hash")
            if digest(p.read_bytes()) != proc.get(key): fail("stream-hash",label+"."+stream)
    runs=summary.get("runs")
    if not isinstance(runs,list) or len(runs)!=20: fail("run-cardinality")
    else:
        for idx,run in enumerate(runs,1):
            if not isinstance(run,dict) or run.get("run") != idx or not isinstance(run.get("captureHash"),str): fail("run-shape",str(idx)); continue
            cap=case_dir/f"run-{idx:03d}/capture.json"; plain=case_dir/f"run-{idx:03d}/plain.raw.json"; instr=case_dir/f"run-{idx:03d}/instrumented.raw.json"; ax=case_dir/f"run-{idx:03d}/external-ax.raw.json"
            for p in (cap,plain,instr,ax):
                if not p.is_file(): fail("run-file",f"{idx}:{p.name}")
            if cap.is_file() and digest(cap.read_bytes()) != run.get("captureHash"): fail("capture-hash",str(idx))
            if cap.is_file():
                c=json.loads(cap.read_text())
                if c.get("case") != expected_case: fail("capture-case",str(idx))
                if c.get("platform") != "macos" or c.get("meta",{}).get("conditions",{}).get("candidateOnly") is not True: fail("capture-meta",str(idx))
                images={item.get("id"): item for item in c.get("images",[]) if isinstance(item,dict)}
                for image_id, summary_key, raw_name, png_name in (("macos.plain","plain","plain.raw.json","plain.png"),("macos.instrumented","instrumented","instrumented.raw.json","instrumented.png"),("macos.compositor",None,"compositor.raw.json","compositor.png")):
                    image=images.get(image_id)
                    if not isinstance(image,dict): fail("normalized-image",f"{idx}:{image_id}"); continue
                    png=case_dir/f"run-{idx:03d}"/png_name; raw=case_dir/f"run-{idx:03d}"/raw_name
                    if not png.is_file() or not raw.is_file(): continue
                    if image.get("hash") != digest(png.read_bytes()): fail("normalized-png-join",f"{idx}:{image_id}")
                    if summary_key is not None:
                        normalized=run.get(summary_key,{})
                        if normalized.get("pngHash") != digest(png.read_bytes()) or normalized.get("rawHash") != digest(raw.read_bytes()): fail("normalized-summary-join",f"{idx}:{image_id}")
                        shape=normalized.get("image",{}); expected_shape={"width":image.get("widthPx"),"height":image.get("heightPx"),"scale":image.get("captureScale")}
                        if not all(shape.get(key)==value for key,value in expected_shape.items()): fail("normalized-shape-join",f"{idx}:{image_id}")
                    elif run.get("compositorPngHash") != digest(png.read_bytes()) or run.get("compositorRawHash") != digest(raw.read_bytes()):
                        fail("normalized-summary-join",f"{idx}:{image_id}")
            for p, key in ((plain,"plain"),(instr,"instrumented")):
                if p.is_file():
                    raw=json.loads(p.read_text())
                    if raw.get("permissions",{}).get("permissionRequests") is not False: fail("permission",f"{idx}:{key}")
                    if raw.get("status") != "OBSERVED" or not isinstance(raw.get("pid"),int) or raw.get("pid")<=0: fail("raw-process",f"{idx}:{key}")
            if ax.is_file():
                raw=json.loads(ax.read_text())
                if raw.get("permissionRequests") is not False or raw.get("status") not in {"OBSERVED","HELD"}: fail("ax",str(idx))
    # Supplemental F10 descriptor uses exact archived refs and current exact tool bytes only.
    summary_ref=ref(case_dir/"summary.json"); case_ref=ref(case_path); source_ref=ref(witness); adapter_ref=ref(adapter); binary_ref=ref(binary); receipt_ref=ref(receipt_path)
    origin={"version":"1","summary":summary_ref,"case":case_ref,"source":source_ref,"adapter":adapter_ref,"binary":binary_ref,"compilerReceipt":receipt_ref}
    ax_client=summary.get("freshAXClient")
    if isinstance(ax_client,dict) and ax_client.get("externalAX")=="AVAILABLE":
        ax_receipt=ROOT/"ax-compiler-receipt.json"; ax_source=ROOT/"archive/internal-scratch-seed-origin-v8-capture-20261011/external-ax-client/AXClient.swift"; ax_binary=ROOT/"archive/internal-scratch-seed-origin-v8-capture-20261011/external-ax-client/f5-ax-client"
        origin["auxiliaryAX"]={"receipt":ref(ax_receipt),"source":ref(ax_source),"binary":ref(ax_binary)}
    capture={"platform":"macos","case":expected_case,"meta":{"conditions":{"macOrigin":origin}}}
    issues=guard.mac_origin_admission_issues(capture,reader)
    if issues: fail("f10-guard", ";".join(issues[:4]))
    return {"case":cid,"runs":len(runs) if isinstance(runs,list) else 0,"f10Issues":issues}

def main():
    failures=[]; rows=[]
    for case_dir in sorted(p for p in ROOT.iterdir() if p.is_dir() and p.name.startswith("swiftui.")):
        rows.append(check_shape(case_dir,json.loads((case_dir/"summary.json").read_text()),failures))
    command=json.loads((ROOT/"capture-command-receipt.json").read_text())
    if command.get("candidateOnly") is not True or command.get("permissionRequests") is not False or command.get("caseRoot") != "factory/oracle/mac/seed-origin-v8/inputs": failures.append("capture-command:preflight-or-case-root")
    faults=json.loads((ROOT/"fault-controls.json").read_text())
    controls=faults.get("controls",[])
    if faults.get("baseline",{}).get("cases") != 5 or faults.get("baseline",{}).get("runs") != 100 or len(controls) != 7 or any(c.get("acceptedBaseline") is not True or c.get("rejected") is not True for c in controls): failures.append("fault-controls:baseline-or-control")
    map_bad=[]
    map_bad_details=[]
    for row in MAP["files"]:
        p=ROOT/row["path"]
        if not p.is_file() or len(p.read_bytes()) != row["bytes"] or digest(p.read_bytes()) != row["sha256"]:
            map_bad.append(row["path"])
            map_bad_details.append({"path":row["path"],"expectedSha256":row["sha256"],"actualSha256":digest(p.read_bytes()) if p.is_file() else None,"expectedBytes":row["bytes"],"actualBytes":p.stat().st_size if p.is_file() else None})
    report={"kind":"seed-origin-actual-v2-independent-review","version":"1","candidateOnly":True,"cases":len(rows),"runs":sum(r["runs"] for r in rows),"rows":rows,"archiveMapRows":len(MAP["files"]),"archiveMapIntegrityFailures":map_bad,"archiveMapIntegrityDetails":map_bad_details,"failures":failures,"nativeCompilerRemoteRuns":0,"notes":["capture-command-receipt explicitly records no collector parent-PID receipt; per-case resolver/compiler/AX process receipts are retained","font resolution remains HELD; shapes external AX remains HELD","no parity or promotion decision"],"sourcePins":{"v8StageManifest":"sha256:0641bf7030594ecd4dfd86ca60d30961f0ed3c849e7b79a0576dd25f13530942","v8Collector":"sha256:737399fcb39f13d79a8e908507210d0de733a3180b8eded63dfa7ec70ed2f8bf","v8CaptureHost":"sha256:749fb3b497784aa8edc344868c15fcf0d69c2bd9a63cdb37a8592949ef77688b","v8AXClient":"sha256:9514c4ed6964a9a078058fc909ea72a89ad6363fd0662ed2e9369788af59c404","actualArchiveMap":"sha256:e33bdf9f96b5b989d946d8be152cf7a560f7adb793bff6f2bc08dae547d9e7df","actualStageManifest":"sha256:6a41b76a6bd6129e2f4b212d9b9997c73d31800968a99077ee5b5d4c04c84515"},"decision":"CLEAR" if not failures and not map_bad else "BLOCKED"}
    print(json.dumps(report,indent=2,sort_keys=True))
    (Path(__file__).resolve().parent/"report.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
    raise SystemExit(0 if report["decision"]=="CLEAR" else 1)
if __name__=="__main__": main()
