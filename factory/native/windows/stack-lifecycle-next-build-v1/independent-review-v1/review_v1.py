from __future__ import annotations
from pathlib import Path
import hashlib,json,re
ROOT=Path(__file__).resolve().parents[5]
P=ROOT/"factory/native/windows/stack-lifecycle-next-build-v1"
S=ROOT/"factory/native/windows/stack-lifecycle-next-v1"
OLD=ROOT/"factory/native/windows/seed-stack-lifecycle-host-v1/package/Sources/FactoryProbe/main.swift"
def h(q):return hashlib.sha256(q.read_bytes()).hexdigest()
def j(q):return json.loads(q.read_text())
def run():
 failures=[]; man=j(P/"root-stage-manifest.json"); listed={x["path"] for x in man["files"]}; actual={str(q.resolve().relative_to(ROOT)).replace("\\","/") for q in P.rglob("*") if q.is_file() and "__pycache__" not in q.parts}
 for x in man["files"]:
  q=ROOT/x["path"]
  if not q.exists() or h(q)!=x["hash"].removeprefix("sha256:") or q.stat().st_size!=x["bytes"]: failures.append("stage-pin:"+x["path"])
 if len(man["files"])!=63: failures.append("stage-count")
 plan=j(P/"package/plan.json"); source=P/"package/Sources/FactoryProbe/Witness.swift"; old=OLD.read_text(); new=(P/"package/Sources/FactoryProbe/main.swift").read_text()
 if h(P/"package/plan.json")!="9e385e4e50b46c109103cf28b9d8e93be01298fed6c35f2426a1d6a3cdaacef1" or h(source)!="fe91bed344011c7464a18c1ae5ee757a113f6eda6f7f4e0c4cb0258a258d8c35": failures.append("source-plan-hash")
 if h(S/"source-manifest.json")!=h(P/"dependencies/lifecycle-source-manifest.json") or (S/"source-manifest.json").read_bytes()!=(P/"dependencies/lifecycle-source-manifest.json").read_bytes(): failures.append("source-manifest-join")
 srcman=j(P/"dependencies/lifecycle-source-manifest.json")
 for row in srcman["files"]:
  q=(P/row["path"] if (P/row["path"]).exists() else (P/"dependencies"/row["path"]))
  if not q.exists() or h(q)!=row["sha256"] or q.stat().st_size!=row["bytes"]: failures.append("source-pin:"+row["path"])
 # predecessor source preservation: exactly one changed main line, loader path.
 old_lines=old.splitlines(); new_lines=new.splitlines(); diffs=[(i,a,b) for i,(a,b) in enumerate(zip(old_lines,new_lines),1) if a!=b]
 if len(old_lines)!=len(new_lines) or len(diffs)!=1 or "Bridge.load(path:" not in diffs[0][1] or "D:\\\\Claude\\\\swiftright\\\\.factory-work" not in diffs[0][2]: failures.append("main-source-delta")
 events=lambda text:re.findall(r'factoryLifecycle\(\"([^\"]+)',text)
 if events(old)!=events(new) or len(events(new))!=12: failures.append("lifecycle-markers")
 if [x for x in ("window-closed-enter","graph-teardown-return","measure-release-return","shutdown-complete-return","bridge-run-return","unhook-enter","unhook-return","actor-return-result-\\(result)","before-exit-result-\\(result)") if x not in events(new)]: failures.append("acceptance-markers")
 canonical=j(P/"dependencies/canonical-inputs-manifest.json")
 if h(P/"dependencies/canonical-inputs-manifest.json")!="208689e04f06a0e397ccd611bb8aca3828e0cf7ec15fd7df0a4dab8436389efa" or len([x for x in canonical["files"] if x["path"].startswith("SwiftRightBridge/")])!=10: failures.append("canonical-bridge")
 bridge={x["path"].split("/",1)[1]:x for x in canonical["files"] if x["path"].startswith("SwiftRightBridge/")}
 if {x["path"] for x in plan["bridgeBindings"]}!=set(bridge): failures.append("bridge-membership")
 for x in plan["bridgeBindings"]:
  q=P/"dependencies/SwiftRightBridge"/x["path"]; a=bridge[x["path"]]
  if not q.exists() or h(q)!=x["sha256"] or x["sha256"]!=a["sha256"] or q.stat().st_size!=a["bytes"]: failures.append("bridge-pin:"+x["path"])
 req=plan["compileRequest"]; expected={"kind":"swiftpm-windows-gui-release/1","packagePath":r"D:\Claude\swiftright\.factory-work\hosts\stack-lifecycle\package","scratchPath":r"D:\Claude\swiftright\.factory-work\hosts\stack-lifecycle\package\build-lifecycle-r1\scratch","compilerPath":plan["compilerPath"],"target":"windows-x86_64","configuration":"release"}
 if req!=expected: failures.append("compile-request")
 if plan["runtimePackagePath"]!=r"D:\Claude\swiftright\.factory-work\runtime-stage\runtime" or plan["bridgePackagePath"]!=r"D:\Claude\swiftright\.factory-work\inputs\SwiftRightBridge" or plan["rendererPath"]!=r"D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll" or plan["runtimeSourceCommit"]!="37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b" or plan["bridgeSourceCommit"]!="0a745ab" or plan["bridgeHeaderCommit"]!="862997c": failures.append("owned-inputs")
 if plan["executionEligible"] is not False or plan["nativeParity"]!="hold" or plan["frozenTupleBound"] is not False or plan["closureBinding"] is not None: failures.append("held-state")
 build=(P/"build-hosts-v2.ps1").read_text(); stream=(P/"stream-seal.ps1").read_text(); bounded=(P/"test-process-streams-bounded.ps1").read_text()
 for needle,label in [("$handle=$p.Handle","retained-handle"),("WaitForExit(300000)","compiler-300s"),("WaitForSingleObject($handle,5000)","terminate-5s"),("Complete-FactoryRawStreams $streams","stream-complete"),("Close-FactoryRawStreamDestination $stream","stream-close")]:
  if needle not in build: failures.append(label)
 if "WaitForSingleObject" not in build or "5000" not in stream or "WaitForExit(15000)" not in bounded or "$streams[0].task.Wait(5000)" not in bounded: failures.append("bounds")
 controls=j(P/"controls/source-tests.json"); report=j(P/"report.json")
 if controls.get("tests")!=9 or controls.get("exitCode")!=0 or controls.get("compilerActions")!=0 or controls.get("nativeActions")!=0: failures.append("control-receipt")
 if report.get("compilerRuns")!=0 or report.get("nativeRuns")!=0 or report.get("remoteActions")!=0 or report.get("qualification")!="hold": failures.append("report-hold")
 return {"kind":"stack-lifecycle-next-independent-review","version":"1","decision":"CLEAR_SOURCE_ONLY_HOLD" if not failures else "HOLD","failures":failures,"sourceStageSha256":h(S/"source-manifest.json"),"buildStageSha256":h(P/"root-stage-manifest.json"),"planSha256":h(P/"package/plan.json"),"sourceHash":h(P/"package/Sources/FactoryProbe/Witness.swift"),"mainHash":h(P/"package/Sources/FactoryProbe/main.swift"),"canonicalBridgeManifestSha256":h(P/"dependencies/canonical-inputs-manifest.json"),"canonicalBridgeMembers":10,"lifecycleMarkerCallsites":12,"acceptanceMarkers":9,"sourceControls":9,"compilerRuns":0,"nativeRuns":0,"remoteActions":0,"qualification":"hold","reviewScope":"offline source/code/compiler-request/bounded-control audit; no compiler/native/remote action"}
if __name__=="__main__":print(json.dumps(run(),indent=2,sort_keys=True))
