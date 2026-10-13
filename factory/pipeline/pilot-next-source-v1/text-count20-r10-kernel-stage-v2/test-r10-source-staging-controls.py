#!/usr/bin/env python3
"""Production graph controls; root runs only after source transport review."""
from __future__ import annotations
import argparse, copy, importlib.util, json
from pathlib import Path

def load_module(path:Path):
 spec=importlib.util.spec_from_file_location("r10_stage_controls",path)
 if spec is None or spec.loader is None: raise RuntimeError("stage module unavailable")
 mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod

def main():
 ap=argparse.ArgumentParser();ap.add_argument("--stage-script",required=True);ap.add_argument("--graph",required=True);ap.add_argument("--source-root")
 a=ap.parse_args();stage=load_module(Path(a.stage_script));graph,_,_=stage.load_json_bounded(Path(a.graph))
 stage.validate_graph(graph,a.source_root)
 faults=[]
 def reject(name,mutate):
  x=copy.deepcopy(graph);mutate(x)
  try: stage.validate_graph(x,a.source_root)
  except Exception: faults.append({"name":name,"rejected":True});return
  raise RuntimeError("accepted source fault: "+name)
 reject("count",lambda x:x.__setitem__("count",1))
 reject("count1-prerequisite",lambda x:x.__setitem__("count1FirstRequired",False))
 reject("exe-hash",lambda x:x.__setitem__("expectedExeHash","0"*64))
 reject("action-state",lambda x:x.__setitem__("nativeWindowActions",1))
 reject("compiler-action-state",lambda x:x.__setitem__("compilerActions",1))
 reject("lock-action-state",lambda x:x.__setitem__("lockActions",1))
 reject("helper-hash",lambda x:x.__setitem__("successorHelperSha256","0"*64))
 reject("budget",lambda x:x.__setitem__("streamDrainMilliseconds",1))
 reject("source-list-count",lambda x:x.__setitem__("sourceListCount",1))
 reject("aggregate-bytes",lambda x:x.__setitem__("aggregateBytes",0))
 reject("donor-mutation",lambda x:x.__setitem__("donorMutated",True))
 reject("row-hash",lambda x:x["files"][0].__setitem__("sha256","0"*64))
 reject("row-traversal",lambda x:x["files"][0].__setitem__("path","../escape"))
 reject("row-duplicate",lambda x:x["files"].append(copy.deepcopy(x["files"][0])))
 if len(faults)!=14: raise RuntimeError("unexpected control count")
 print(json.dumps({"status":"SOURCE_CONTROLS_PASS","baseline":True,"faults":faults,"faultCount":len(faults),"nativeActions":0,"compilerActions":0,"lockActions":0},sort_keys=True))

if __name__=="__main__": main()
