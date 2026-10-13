#!/usr/bin/env python3
"""Source-graph controls; root runs under bounded supervisor after transport."""
from __future__ import annotations
import argparse, copy, importlib.util, json
from pathlib import Path

def load(path: Path):
    spec=importlib.util.spec_from_file_location("text_count1_r10_stage", path)
    if spec is None or spec.loader is None: raise RuntimeError("stage import failed")
    mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod

def main() -> int:
    ap=argparse.ArgumentParser(); ap.add_argument("--stage-script",required=True); ap.add_argument("--graph",required=True); ap.add_argument("--source-root")
    args=ap.parse_args(); mod=load(Path(args.stage_script)); graph,_,_=mod.load_json(Path(args.graph)); mod.validate_graph if hasattr(mod,"validate_graph") else None
    if not isinstance(graph,dict) or graph.get("kind") != "factory-text-count1-r10-kernel-source-graph-v1": raise RuntimeError("wrong graph kind")
    if graph.get("count") != 1 or graph.get("count1Required") is not True or graph.get("count1CertificateRequired") is not True: raise RuntimeError("baseline identity rejected")
    if graph.get("nativeWindowActions") != 0 or graph.get("compilerActions") != 0 or graph.get("lockActions") != 0: raise RuntimeError("baseline effect state rejected")
    if graph.get("rendererDeadlineSeconds") != 30 or graph.get("exitDeadlineSeconds") != 15 or graph.get("streamDrainMilliseconds") != 5000: raise RuntimeError("baseline lifecycle drift")
    expected_exe=graph.get("expectedExeHash")
    expected_helper=graph.get("successorCleanupHelperSha256")
    expected_rows=[(row.get("path"),row.get("sha256")) for row in graph.get("files",[])]
    def valid(x):
        if x.get("count") != 1 or x.get("count1Required") is not True or x.get("count1CertificateRequired") is not True: raise ValueError("identity")
        if x.get("nativeWindowActions") != 0 or x.get("compilerActions") != 0 or x.get("lockActions") != 0: raise ValueError("effects")
        if x.get("rendererDeadlineSeconds") != 30 or x.get("exitDeadlineSeconds") != 15 or x.get("streamDrainMilliseconds") != 5000: raise ValueError("budget")
        if x.get("expectedExeHash") != expected_exe or x.get("successorCleanupHelperSha256") != expected_helper: raise ValueError("measured hash")
        rows=x.get("files")
        if not isinstance(rows,list) or len(rows) != len(expected_rows): raise ValueError("rows")
        for row, (path,digest) in zip(rows,expected_rows):
            raw=str(row.get("path",""))
            if raw != path or not raw or raw.startswith(("/","\\")) or ":" in raw or "\\" in raw or any(p in ("",".","..") for p in raw.split("/")): raise ValueError("path")
            if row.get("sha256") != digest: raise ValueError("row hash")
        return True
    valid(graph)
    faults=[]
    def reject(name, mutate):
        x=copy.deepcopy(graph); mutate(x)
        try:
            valid(x)
        except Exception as exc:
            faults.append({"name":name,"rejected":True,"reason":str(exc)}); return
        raise RuntimeError("accepted source fault: "+name)
    reject("count",lambda x:x.__setitem__("count",20))
    reject("missing-count1-certificate",lambda x:x.__setitem__("count1CertificateRequired",False))
    reject("wrong-executable-hash",lambda x:x.__setitem__("expectedExeHash","0"*64))
    reject("native-window-action",lambda x:x.__setitem__("nativeWindowActions",1))
    reject("compiler-action",lambda x:x.__setitem__("compilerActions",1))
    reject("lock-action",lambda x:x.__setitem__("lockActions",1))
    reject("renderer-budget",lambda x:x.__setitem__("rendererDeadlineSeconds",31))
    reject("exit-budget",lambda x:x.__setitem__("exitDeadlineSeconds",14))
    reject("drain-budget",lambda x:x.__setitem__("streamDrainMilliseconds",1))
    reject("helper-hash",lambda x:x.__setitem__("successorCleanupHelperSha256","0"*64))
    reject("row-hash",lambda x:x["files"][0].__setitem__("sha256","0"*64))
    reject("row-traversal",lambda x:x["files"][0].__setitem__("path","../escape"))
    if len(faults)!=12: raise RuntimeError("fault count drift")
    print(json.dumps({"status":"SOURCE_CONTROLS_PASS","baseline":True,"faults":faults,"faultCount":len(faults),"nativeWindowActions":0,"compilerActions":0,"lockActions":0},sort_keys=True))
    return 0
if __name__ == "__main__": raise SystemExit(main())
