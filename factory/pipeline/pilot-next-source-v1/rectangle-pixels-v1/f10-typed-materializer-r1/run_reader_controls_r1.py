#!/usr/bin/env python3
"""Reader-backed F10 controls for typed Rectangle Windows20 captures.

Controls execute production ``verify_windows_exit_admission`` through
``ArchiveByteReader``. Every result is observational; no semantic/parity pass
is emitted. Faults mutate in-memory capture/bytes only & never raw archives.
"""
from __future__ import annotations
import argparse, copy, hashlib, json, os, stat, sys
from pathlib import Path
from typing import Any
ROOT=Path(__file__).resolve().parents[5]
if str(ROOT) not in sys.path: sys.path.insert(0,str(ROOT))
from factory.core.artifacts import canonical_hash
from factory.gate.windows_exit_admission import verify_windows_exit_admission, ROLES
from factory.pipeline.archive_reader import ArchiveByteReader
MAX_JSON=2*1024*1024

def load(path:Path)->Any:
    st=path.lstat()
    if not stat.S_ISREG(st.st_mode) or stat.S_ISLNK(st.st_mode) or st.st_size>MAX_JSON: raise ValueError(f"bounded JSON required:{path}")
    return json.loads(path.read_bytes().decode("utf-8-sig"))
def digest(x:bytes)->str:return "sha256:"+hashlib.sha256(x).hexdigest()
def require(c:bool,m:str):
    if not c: raise ValueError(m)
def evaluate(capture:dict, reader:ArchiveByteReader, override=None):
    def read(reference):
        raw=reader(capture=capture,reference=reference)
        return override(reference,raw) if override else raw
    try:return verify_windows_exit_admission(capture,read_bytes=read)
    except (ValueError,KeyError,TypeError,OSError,UnicodeError) as exc:return {"status":"blocked","issues":[str(exc)]}
def direct_compile_fault(capture:dict, reader:ArchiveByteReader, mutate) -> dict:
    """Run gate directly with mutated measured plan/compile/outcome bytes.

    ArchiveByteReader supplies every untouched byte; only joins required to
    reach compiler-request validation are rehashed in this in-memory fault.
    No archive or capture source is changed.
    """
    files = capture["meta"]["conditions"]["windowsExitProof"]["files"]
    plan_path, compile_path, outcome_path = files["plan"]["path"], files["compile"]["path"], files["outcome"]["path"]
    plan = json.loads(reader(capture=capture, reference=plan_path).decode("utf-8-sig"))
    compile_doc = json.loads(reader(capture=capture, reference=compile_path).decode("utf-8-sig"))
    outcome = json.loads(reader(capture=capture, reference=outcome_path).decode("utf-8-sig"))
    mutate(plan, compile_doc)
    plan_raw = json.dumps(plan, sort_keys=True, separators=(",", ":")).encode()
    plan_hash = digest(plan_raw)
    compile_doc["planSha256"] = plan_hash.removeprefix("sha256:")
    compile_raw = json.dumps(compile_doc, sort_keys=True, separators=(",", ":")).encode()
    compile_hash = digest(compile_raw)
    outcome["compileReceiptHash"] = compile_hash.removeprefix("sha256:")
    outcome_raw = json.dumps(outcome, sort_keys=True, separators=(",", ":")).encode()
    outcome_hash = digest(outcome_raw)
    fault = copy.deepcopy(capture)
    fault_files = fault["meta"]["conditions"]["windowsExitProof"]["files"]
    fault_files["plan"]["hash"] = plan_hash
    fault_files["compile"]["hash"] = compile_hash
    fault_files["outcome"]["hash"] = outcome_hash
    def direct_read(reference):
        if reference == plan_path: return plan_raw
        if reference == compile_path: return compile_raw
        if reference == outcome_path: return outcome_raw
        return reader(capture=capture, reference=reference)
    try: return verify_windows_exit_admission(fault, read_bytes=direct_read)
    except (ValueError, KeyError, TypeError, OSError, UnicodeError) as exc: return {"status":"blocked","issues":[str(exc)]}

def main()->int:
    ap=argparse.ArgumentParser();ap.add_argument("--reader-input",type=Path,required=True);ap.add_argument("--captures",type=Path,required=True);ap.add_argument("--output",type=Path,required=True);args=ap.parse_args()
    manifest=load(args.reader_input); payload=load(args.captures); captures=payload.get("captures") if isinstance(payload,dict) else payload
    require(manifest.get("version")==1 and manifest.get("expectedWindows")==20,"F10 manifest mismatch")
    require(isinstance(captures,list) and len(captures)==20,"exact Windows20 captures required")
    base=args.reader_input.parent
    archives={k:str((base/v).resolve(strict=True)) for k,v in manifest.get("windowsArchives",{}).items()}
    reader=ArchiveByteReader(windows_archives=archives,max_bytes=32*1024*1024)
    rows=[]; passed=0
    for cap in captures:
        r=evaluate(cap,reader); passed += int(r.get("status")=="pass"); rows.append({"run":cap.get("meta",{}).get("run"),"captureHash":canonical_hash(cap),"status":r.get("status"),"issues":r.get("issues",[]),"evidenceHash":r.get("evidenceHash")})
    # Meaningful production-path faults: role omission, hash drift, identity drift,
    # & reader byte mutation. Each must be blocked, while baseline remains unmodified.
    c0=captures[0]
    def mutate_missing(c):
        x=json.loads(json.dumps(c)); del x["meta"]["conditions"]["windowsExitProof"]["files"]["stderr"]; return x
    def mutate_hash(c):
        x=json.loads(json.dumps(c)); x["meta"]["conditions"]["windowsExitProof"]["files"]["stdout"]["hash"]="sha256:"+"0"*64; return x
    def mutate_case(c):
        x=json.loads(json.dumps(c)); x["case"]={"id":"fault","hash":"sha256:"+"0"*64}; return x
    faults=[]
    for name,mut in (("missing-role",mutate_missing),("proof-hash",mutate_hash),("case-drift",mutate_case)):
        rr=evaluate(mut(c0),reader); faults.append({"name":name,"status":rr.get("status"),"issues":rr.get("issues",[])})
        require(rr.get("status")=="blocked",f"fault accepted:{name}")
    proof=c0["meta"]["conditions"]["windowsExitProof"]["files"]["stdout"]["path"]
    def mutate_bytes(reference,raw): return (raw+b"fault") if reference==proof else raw
    rr=evaluate(c0,reader,mutate_bytes); faults.append({"name":"reader-byte-drift","status":rr.get("status"),"issues":rr.get("issues",[])})
    require(rr.get("status")=="blocked","reader byte mutation accepted")
    # Compiler-request fault matrix reaches the production request parser with
    # all dependent raw joins rehashed from mutated bytes.
    compile_faults=[]
    mutations=(
        ("jobs2", lambda p,c: p["compileRequest"].__setitem__("maxParallelJobs",2)),
        ("jobs-bool", lambda p,c: p["compileRequest"].__setitem__("maxParallelJobs",True)),
        ("jobs-string", lambda p,c: p["compileRequest"].__setitem__("maxParallelJobs","1")),
        ("missing-argv-flag", lambda p,c: c.__setitem__("argv",c["argv"].replace(" --jobs 1", ""))),
        ("undeclared-argv-flag", lambda p,c: p["compileRequest"].pop("maxParallelJobs",None)),
        ("extra-unknown", lambda p,c: p["compileRequest"].__setitem__("unexpected",True)),
    )
    for name, mutation in mutations:
        fr=direct_compile_fault(c0,reader,mutation); compile_faults.append({"name":name,"status":fr.get("status"),"issues":fr.get("issues",[])})
        require(fr.get("status")=="blocked",f"compiler fault accepted:{name}")
    faults.extend(compile_faults)
    result={"schema":"factory-rectangle-f10-reader-controls-r1","status":"reader-verified" if passed==20 else "reader-observed-rejections","qualified":False,"nativeParityGranted":False,"baseline":{"count":len(rows),"passed":passed,"rows":rows},"faults":faults,"comparison":{"status":"held-observation-only","semantic":"held","timing":"raw-only","nativeParity":"held","pixelParity":"held"}}
    require(not args.output.exists(),"output must be fresh");args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+"\n");print(json.dumps({"status":result["status"],"baselinePassed":passed,"faultCount":len(faults)},sort_keys=True));return 0
if __name__=="__main__":raise SystemExit(main())
