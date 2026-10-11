from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[5]
P=ROOT/"factory/native/windows/remaining-five-hosts-v5"
LABELS=("disabled","image","shapes.fill-stroke","text.bundled-font","toggle")
def h(q): return hashlib.sha256(q.read_bytes()).hexdigest()
def j(q): return json.loads(q.read_text())
def run():
 failures=[]; m=j(P/"root-stage-manifest.json"); listed={x["path"] for x in m["files"]}; actual={str(q.resolve().relative_to(ROOT)).replace("\\","/") for q in P.rglob("*") if q.is_file() and "__pycache__" not in q.parts}
 if m.get("kind")!="remaining-five-hosts-source-stage-v5" or len(m["files"])!=146: failures.append("stage-shape")
 if listed-actual: failures.append("manifest-missing")
 if any(h(ROOT/x["path"])!=x["hash"].removeprefix("sha256:") or ROOT.joinpath(x["path"]).stat().st_size!=x["bytes"] for x in m["files"]): failures.append("manifest-pin")
 pins=j(P/"reviewed-v3-controls/source-pins.json"); src=ROOT/"factory/native/windows/padding-settled-build-v3"
 if pins.get("kind")!="reviewed-padding-build-v3-control-source-pins" or len(pins.get("files",[]))!=24 or h(src/"root-stage-manifest.json")!=pins["sourceManifestSha256"].removeprefix("sha256:"): failures.append("v3-source-manifest")
 for e in pins["files"]:
  q=P/"reviewed-v3-controls"/e["path"]; old=src/e["path"]
  if not q.exists() or not old.exists() or h(q)!=e["sha256"].removeprefix("sha256:") or q.stat().st_size!=e["bytes"] or q.read_bytes()!=old.read_bytes(): failures.append("v3-pin:"+e["path"])
 ready=j(P/"readiness.json")
 expected_compiler=r"C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe"
 for row,label in zip(ready["rows"],LABELS):
  d=j(P/label/"package/plan.json"); case=j(P/label/"package/case.json"); req=d["compileRequest"]; package=rf"D:\Claude\swiftright\.factory-work\hosts\{label}\package"
  if row["label"]!=label or row["planHash"]!="sha256:"+h(P/label/"package/plan.json") or row["case"]["hash"]!=d["case"]["hash"] or row["sourceHash"]!=d["sourceHash"]: failures.append("readiness:"+label)
  if req != {"compilerPath":expected_compiler,"configuration":"release","kind":"swiftpm-windows-gui-release/1","packagePath":package,"scratchPath":package+r"\build-v5-r1\scratch","target":"windows-x86_64"}: failures.append("compile-request:"+label)
  if d["stage"]!=r"D:\Claude\swiftright" or d["inputsRoot"]!=r"D:\Claude\swiftright\.factory-work\inputs" or d["runtimePackagePath"]!=r"D:\Claude\swiftright\.factory-work\runtime-stage\runtime": failures.append("namespace:"+label)
  if d["executionEligible"] is not False or d["nativeParity"]!="hold" or d["frozenTupleBound"] is not False or d["closureBinding"] is not None: failures.append("qualification:"+label)
  if d["prospectiveNativeCandidate"] is not (label=="disabled"): failures.append("candidate:"+label)
 review_files={str(q.resolve().relative_to(ROOT)).replace("\\","/") for q in (P/"independent-review-v1").rglob("*") if q.is_file()}
 return {"kind":"remaining-five-hosts-v5-independent-review","version":"1","decision":"CLEAR_SOURCE_ONLY_HOLD" if not failures else "HOLD","failures":failures,"stageManifestSha256":h(P/"root-stage-manifest.json"),"reportSha256":h(P/"report.json"),"readinessSha256":h(P/"readiness.json"),"verifyPacketSha256":h(P/"verify_packet.py"),"testPacketSha256":h(P/"test_packet.py"),"v3PinsSha256":h(P/"reviewed-v3-controls/source-pins.json"),"v3SourceManifestSha256":pins["sourceManifestSha256"],"hostCount":5,"manifestEntries":146,"manifestExtraFiles":sorted(actual-listed-review_files),"v3HelperFiles":24,"compilerRuns":0,"nativeRuns":0,"remoteActions":0,"qualificationGranted":False,"nativeEligibility":"hold","providerBoundaries":"disabled candidate only; image/shapes/text/toggle provider requirements held","reviewScope":"offline source/case/witness/plan/compiler-argv/source-scope/runtime/bridge/renderer namespace audit; no compiler/native/remote action"}
if __name__=="__main__": print(json.dumps(run(),indent=2,sort_keys=True))
