"""Independent offline review of paired-disabled-observation-v2."""
from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
PACKET=ROOT/"factory/pipeline/paired-disabled-observation-v2"; EVIDENCE=PACKET/"evidence"
MANIFEST_SHA="53e223357633c74d790e8c4af704882ab10d5d8d1727aa6bbc413e1c41d513cb"; REPORT_SHA="23b182324ac49ecbf9d7126db4c946a768a26cdcb11a7f6ea1c718ae11ced73f"; STAGE_SHA="0a3fbb9feb57ff5e6e6002347b746b4f9fd9e1b8adb54bece74316b97e355ed0"
CASE_ID="swiftui.disabled.recipe/case/f113195a59446fc4"; CASE_SHA="d6a88082e0818e46e4e1ea5e6d45af6edbce63c86fc6b847704c38ad3db9aa99"; SOURCE_SHA="68eed62f6ef06ecec579a0e36cdc44a612a559a8329fe6dbd91a700c5d90c005"; PROBE_SHA="5e155ed85464617856bff8796c548a4bca943b0a4e1176425a6f8f3e63a4b27e"; AX_CLIENT_SOURCE_SHA="0ba89941a66465fdfd3f6c7f8b90d4bf049dcbb561a2d2cec846cace349eea51"
MAC_AX_ROOT="factory/native/macos/disabled-enabled-observation-v1/evidence"; PAINT_ROOT="factory/native/macos/evidence/20261010-primary-next-five/swiftui.disabled.recipe_case_f113195a59446fc4"; WIN_ROOT="factory/native/windows/disabled-repeatability-batch-v1/actual-r1"
class ReviewError(ValueError):pass
def sha(x):return hashlib.sha256(x).hexdigest()
def jd(x,label):
 try:return json.loads(x.decode("utf-8-sig"))
 except Exception as e:raise ReviewError(f"invalid JSON {label}") from e
def walk(x):
 if isinstance(x,dict):
  yield x
  for v in x.values():yield from walk(v)
 elif isinstance(x,list):
  for v in x:yield from walk(v)
def load_inputs(root=ROOT):
 mpath=PACKET/"evidence/input-manifest.json"; mraw=mpath.read_bytes(); m=jd(mraw,"manifest"); rows=m.get("inputs")
 if sha(mraw)!=MANIFEST_SHA or not isinstance(rows,list) or len(rows)!=1131:raise ReviewError("frozen manifest pin/count mismatch")
 refs={}
 for row in rows:
  if not isinstance(row,dict) or not isinstance(row.get("path"),str) or not row["path"].startswith("factory/") or ".." in Path(row["path"]).parts or not isinstance(row.get("channel"),str) or not isinstance(row.get("sha256"),str) or len(row["sha256"])!=64 or type(row.get("bytes")) is not int:raise ReviewError("malformed input row")
  if row["path"] in refs:raise ReviewError("duplicate input path")
  refs[row["path"]]=row
 payloads={path:(root/path).read_bytes() for path in refs}
 return mraw,m,refs,payloads
def audit(mraw,m,refs,payloads):
 if sha(mraw)!=MANIFEST_SHA or m.get("kind")!="paired-disabled-observation-v2-input-manifest" or m.get("version")!=2 or m.get("caseId")!=CASE_ID or m.get("sourceSha256")!=SOURCE_SHA:raise ReviewError("manifest identity mismatch")
 if set(payloads)!=set(refs):raise ReviewError("payload set differs manifest")
 for path,row in refs.items():
  if len(payloads[path])!=row["bytes"] or sha(payloads[path])!=row["sha256"]:raise ReviewError(f"input hash mismatch {path}")
 chans={r["channel"] for r in refs.values()}
 expected={"macos-ax-batch","macos-ax-review","macos-paint-batch","windows-repeatability-batch","windows-review","shared-source"}
 if chans!=expected:raise ReviewError("channel set mismatch")
 if m.get("batches")!=[{"channel":"macos-ax-batch","id":"macos-disabled-ax-20-v1","root":MAC_AX_ROOT,"runs":20},{"channel":"macos-paint-batch","id":"macos-disabled-paint-20-historical","root":PAINT_ROOT,"runs":20},{"channel":"windows-repeatability-batch","id":"windows-disabled-repeatability-20-actual-r1","root":WIN_ROOT,"runs":20}]:raise ReviewError("batch manifest mismatch")
 def raw(path):return payloads[path]
 def doc(path):return jd(raw(path),path)
 def path(channel,suffix):
  vals=[x["path"] for x in refs.values() if x["channel"]==channel and x["path"].endswith(suffix)]
  if len(vals)!=1:raise ReviewError(f"expected one {channel} {suffix}, got {len(vals)}")
  return vals[0]
 casep="factory/pipeline/cases/swiftui.disabled.recipe--case--f113195a59446fc4.json"; sourcep="factory/pipeline/probes/swiftui.disabled.recipe_case_f113195a59446fc4.swift"; probep="factory/pipeline/probes/swiftui.disabled.recipe_case_f113195a59446fc4.manifest.json"
 case=doc(casep); probe=doc(probep)
 if sha(raw(casep))!=CASE_SHA or sha(raw(sourcep))!=SOURCE_SHA or sha(raw(probep))!=PROBE_SHA or case.get("id")!=CASE_ID or case.get("block")!="swiftui.disabled" or probe.get("sourceHash")!="sha256:"+SOURCE_SHA or probe.get("case",{}).get("hash")!="sha256:"+CASE_SHA:raise ReviewError("case/source/probe join mismatch")
 # Confirm every channel owns expected path scope; review/shared rows remain explicit.
 for row in refs.values():
  p=row["path"]; c=row["channel"]
  if c=="macos-ax-batch" and not (p.startswith(MAC_AX_ROOT+"/") or p.startswith("factory/pipeline/") or p.startswith("factory/native/macos/disabled-enabled-observation-v1/")):raise ReviewError("AX channel path scope mismatch")
  if c=="macos-paint-batch" and not p.startswith(PAINT_ROOT+"/"):raise ReviewError("paint channel path scope mismatch")
  if c=="windows-repeatability-batch" and not p.startswith("factory/native/windows/disabled-repeatability-batch-v1/"):raise ReviewError("Windows channel path scope mismatch")
 ax_report_path="factory/native/macos/disabled-enabled-observation-v1/evidence/report.json"; ax_input_path="factory/native/macos/disabled-enabled-observation-v1/evidence/input-manifest.json"; paint_summary_path=PAINT_ROOT+"/summary.json"; win_analysis_path="factory/native/windows/disabled-repeatability-batch-v1/analysis.json"; mac_review_path="factory/native/macos/disabled-enabled-observation-v1/independent-review/independent-review.json"; win_review_path="factory/native/windows/disabled-repeatability-batch-v1/actual-review/report.json"
 ax_report=doc(ax_report_path); ax_input=doc(ax_input_path); paint=doc(paint_summary_path); win_analysis=doc(win_analysis_path); mac_review=doc(mac_review_path); win_review=doc(win_review_path)
 if ax_report.get("kind")!="disabled-enabled-ax-observation-v1" or ax_report.get("caseId")!=CASE_ID or ax_report.get("newObservationCount")!=20 or ax_report.get("observedEnabledTrueCount")!=20 or ax_report.get("permissionRequests") is not False or ax_report.get("noInputInvoked") is not True:raise ReviewError("Mac AX source report mismatch")
 if ax_input.get("caseSha256")!=CASE_SHA or ax_input.get("sourceSha256")!=SOURCE_SHA or ax_input.get("probeManifestSha256")!=PROBE_SHA or ax_input.get("axClient",{}).get("sourceSha256")!=AX_CLIENT_SOURCE_SHA:raise ReviewError("Mac AX input lineage mismatch")
 if mac_review.get("kind")!="disabled-enabled-ax-independent-review" or mac_review.get("observation",{}).get("enabledTrueCount")!=20 or mac_review.get("observation",{}).get("newRunCount")!=20 or mac_review.get("observation",{}).get("noInputInvoked") is not True or not all(x is True for x in mac_review.get("checks",{}).values()):raise ReviewError("Mac AX independent review mismatch")
 if paint.get("kind")!="macos-host-capture-candidate" or paint.get("case",{}).get("id")!=CASE_ID or paint.get("sourceHash")!="sha256:"+SOURCE_SHA or paint.get("independentProcessesPerRun") is not True or len(paint.get("runs",[]))!=20 or paint.get("acceptance")!="not-promoted":raise ReviewError("historical paint summary mismatch")
 # Old paint raw records must not acquire new AXEnabled data.
 old_json=[p for p,r in refs.items() if r["channel"]=="macos-paint-batch" and p.endswith(("capture.json","external-ax.raw.json","plain.raw.json"))]
 for p in old_json:
  for node in walk(doc(p)):
   if "enabledAttribute" in node or (node.get("role")=="AXButton" and node.get("label")=="Continue" and "enabled" in node):raise ReviewError(f"old paint record contains AX enabled field {p}")
 if win_analysis.get("kind")!="windows-disabled-observational-repeatability" or win_analysis.get("runs")!=20 or win_analysis.get("uniquePids")!=20 or win_analysis.get("caseId")!=CASE_ID or win_analysis.get("sourceHash")!=SOURCE_SHA or win_analysis.get("qualifiedWindowsBatches")!=0 or win_analysis.get("observedSemanticRepeatability") is not True or win_analysis.get("printWindowDistinctHashes")!=1 or win_analysis.get("qualifiedTiming")!="unavailable" or win_analysis.get("hitTesting")!="not-attempted" or win_analysis.get("nativeParity")!="hold":raise ReviewError("Windows analysis mismatch")
 if win_review.get("kind")!="independent-disabled-repeatability-actual-review" or win_review.get("verdict")!="VERIFIED-BOUNDED-20-RAW-OBSERVATIONS" or win_review.get("pins",{}).get("analysis")!=refs[win_analysis_path]["sha256"] or win_review.get("pins",{}).get("sourceHash")!=SOURCE_SHA or win_review.get("pins",{}).get("caseHash")!=CASE_SHA or win_review.get("checks",{}).get("runs")!=20 or win_review.get("checks",{}).get("uniquePids")!=20 or win_review.get("checks",{}).get("uniqueHwnds")!=20 or win_review.get("checks",{}).get("locksReleased") is not True or win_review.get("checks",{}).get("pixelRepeatsExact") is not True or win_review.get("qualification",{}).get("qualifiedWindowsBatches")!=0:raise ReviewError("Windows independent review mismatch")
 mac_pids=set(); mac_clients=set(); mac_rows=[]
 for i in range(1,21):
  base=f"{MAC_AX_ROOT}/run-{i:03d}"; rp=base+"/external-ax.raw.json"; res=doc(base+"/result.json"); rawax=doc(rp); owner=doc(base+"/owner-process.json"); inv=doc(base+"/ax-invocation.json")
  buts=[n for n in walk(rawax) if n.get("role")=="AXButton" and n.get("label")=="Continue"]; a=buts[0].get("enabledAttribute") if len(buts)==1 else None
  sums=[x for x in ax_report.get("results",[]) if x.get("run")==i]
  if len(buts)!=1 or rawax.get("status")!="OBSERVED" or rawax.get("caseId")!=CASE_ID or rawax.get("sourceSha256")!="sha256:"+SOURCE_SHA or rawax.get("permissionRequests") is not False or type(a) is not dict or a.get("attribute")!="AXEnabled" or a.get("status")!="observed-bool" or type(a.get("value")) is not bool or a.get("value") is not True or res.get("run")!=i or res.get("ownerExitCode")!=0 or res.get("rawSha256")!=sha(raw(rp)) or len(sums)!=1 or sums[0].get("rawSha256")!=sha(raw(rp)) or sums[0].get("ownerPid")!=owner.get("pid") or rawax.get("ownerPID")!=owner.get("pid") or owner.get("caseId")!=CASE_ID or owner.get("sourceSha256")!=SOURCE_SHA or owner.get("unchangedPriorCaptureHost") is not True or inv.get("noInputInvoked") is not True or inv.get("exitCode")!=0 or inv.get("ownerPid")!=owner.get("pid") or inv.get("clientSourceSha256")!=AX_CLIENT_SOURCE_SHA:raise ReviewError(f"Mac AX run {i} mismatch")
  if owner.get("pid") in mac_pids or rawax.get("clientPID") in mac_clients:raise ReviewError("Mac PID reuse")
  mac_pids.add(owner["pid"]); mac_clients.add(rawax["clientPID"]); mac_rows.append({"run":i,"pid":owner["pid"],"role":buts[0]["role"],"label":buts[0]["label"],"enabled":a["value"],"rawSha256":refs[rp]["sha256"]})
 win_pids=set(); print_hashes=set(); win_rows=[]
 for i in range(1,21):
  base=f"{WIN_ROOT}/disabled-repeatability-r1-{i:02d}"; np=base+"/native-observation.json"; op=base+"/observation.json"; pp=base+"/plan.json"; native=doc(np); obs=doc(op); plan=doc(pp); owner=doc(base+"/native-01/owned-process.json"); up=base+"/native-01/native.uia.json"; uia=doc(up); pix=doc(base+"/native-01/native.pixels.json")
  bs=[n for n in walk(uia) if n.get("controlType")=="ControlType.Button" and n.get("name")=="Continue"]
  if native.get("index")!=1 or native.get("case",{}).get("id")!=CASE_ID or native.get("case",{}).get("hash")!="sha256:"+CASE_SHA or native.get("manifestHash")!="sha256:"+PROBE_SHA or native.get("sourceHash")!="sha256:"+SOURCE_SHA or native.get("hostValid") is not True or native.get("occlusionQualified") is not False or native.get("nativeParity")!="hold" or native.get("frozenTupleBound") is not False or native.get("closureBinding") is not None or plan.get("case",{}).get("id")!=CASE_ID or plan.get("sourceHash")!="sha256:"+SOURCE_SHA or obs.get("planSha256")!=sha(raw(pp)) or obs.get("exitCode")!=0 or obs.get("timedOut") is not False or obs.get("nativeWindowOpened") is not False or obs.get("sourceHash")!="sha256:"+SOURCE_SHA or owner.get("path")!=obs.get("exePath") or native.get("exeSha256")!=obs.get("exeSha256") or len(bs)!=1 or type(bs[0].get("enabled")) is not bool or bs[0].get("enabled") is not True or pix.get("pid")!=owner.get("pid") or pix.get("width")!=800 or pix.get("height")!=600 or pix.get("dpi")!=240:raise ReviewError(f"Windows run {i} mismatch")
  if owner["pid"] in win_pids:raise ReviewError("Windows PID reuse")
  win_pids.add(owner["pid"]); files={f.get("path"):f.get("sha256") for f in native.get("files",[]) if isinstance(f,dict)}
  for leaf in ("native.uia.json","native.pixels.json","owned-process.json","native.printwindow.png","native.printwindow.repeat.png"):
   if files.get(leaf)!=refs[f"{base}/native-01/{leaf}"]["sha256"]:raise ReviewError(f"Windows sidecar link {i} {leaf}")
  if files.get("native.printwindow.png")!=files.get("native.printwindow.repeat.png"):raise ReviewError(f"Windows repeat mismatch {i}")
  print_hashes.add(files["native.printwindow.png"]); win_rows.append({"run":i,"pid":owner["pid"],"role":bs[0]["controlType"],"label":bs[0]["name"],"enabled":bs[0]["enabled"],"printWindowSha256":files["native.printwindow.png"]})
 if len(mac_pids)!=20 or len(mac_clients)!=20 or len(win_pids)!=20 or len(print_hashes)!=1:raise ReviewError("run aggregate mismatch")
 report=jd((EVIDENCE/"report.json").read_bytes(),"report")
 if sha((EVIDENCE/"report.json").read_bytes())!=REPORT_SHA or report.get("kind")!="f9-paired-disabled-observational-report" or report.get("version")!="2" or report.get("status")!="observational-enabled-match-parity-held" or report.get("promotion")!="none":raise ReviewError("candidate report identity/status mismatch")
 if report.get("rawInputManifest",{}).get("sha256")!=MANIFEST_SHA or report.get("rawInputManifest",{}).get("inputCount")!=1131 or report.get("rawInputManifest",{}).get("inputs")!=m["inputs"]:raise ReviewError("report input manifest binding mismatch")
 if report.get("semanticComparison")!={"attributeMapping":{"macOS":"AXEnabled.value","windows":"IsEnabled"},"batchValuesMatch":True,"exactValueType":"bool","label":"Continue","macOSValueCounts":{"false":0,"true":20},"pairing":"independent batches; no run-to-run pairing asserted","roleMapping":{"AXButton":"ControlType.Button"},"windowsValueCounts":{"false":0,"true":20}}:raise ReviewError("semantic mapping/count mismatch")
 q=report.get("qualification",{})
 if q.get("acceptedGoldenCount")!=0 or q.get("nativeParity")!="held" or q.get("qualifiedTiming")!="held" or q.get("hitTesting")!="held-not-attempted" or q.get("controlledOcclusion")!="held-unqualified" or q.get("frozenTuple")!="held-unbound":raise ReviewError("qualification holds mismatch")
 b=report.get("batches",{})
 if b.get("macOSAXEnabled",{}).get("runs")!=20 or b.get("macOSAXEnabled",{}).get("rawEnabledTrueCount")!=20 or b.get("macOSPaint",{}).get("runs")!=20 or b.get("macOSPaint",{}).get("enabledAttribute")!="not captured in this historical paint batch" or b.get("windowsUIA",{}).get("runs")!=20 or b.get("windowsUIA",{}).get("distinctPrintWindowHashes")!=1:raise ReviewError("batch report mismatch")
 sm=jd((EVIDENCE/"stage-manifest.json").read_bytes(),"stage");
 if sha((EVIDENCE/"stage-manifest.json").read_bytes())!=STAGE_SHA or len(sm.get("files",[]))!=10 or sm.get("inputManifestSha256")!=MANIFEST_SHA or sm.get("reportSha256")!=REPORT_SHA or sm.get("testCount")!=8:raise ReviewError("stage manifest mismatch")
 for x in sm["files"]:
  p=ROOT/"factory/pipeline/paired-disabled-observation-v2"/x["path"] if not x["path"].startswith("factory/") else ROOT/x["path"]
  if len(p.read_bytes())!=x["bytes"] or sha(p.read_bytes())!=x["sha256"]:raise ReviewError(f"stage file mismatch {x['path']}")
 return {"kind":"paired-disabled-observation-v2-independent-review","version":1,"status":"independently-verified-observational-enabled-match-parity-held","producerPins":{"manifestSha256":MANIFEST_SHA,"reportSha256":REPORT_SHA,"stageManifestSha256":STAGE_SHA,"inputCount":1131,"stageFiles":10,"producerMutationTests":8},"checks":{"all1131PayloadBytesAndHashes":True,"channelScopeAndThreeBatchManifest":True,"F9SourceCaseProbeJoin":True,"macOSAX20RawBoolOwnerClientJoins":True,"oldMacPaintAXEnabledSeparation":True,"windows20UIARawAndPrintWindowJoins":True,"strictRoleLabelBoolMapping":True,"qualificationHoldsAndNoPromotion":True,"producerMutationTestsReceipt":True},"batches":{"macOSAXEnabled":{"runs":20,"enabledTrue":20,"uniqueOwnerPids":20,"uniqueClientPids":20,"inputInvoked":False,"permissionRequests":False},"macOSPaint":{"runs":20,"enabledField":"not captured","source":"historical paint batch"},"windowsUIA":{"runs":20,"enabledTrue":20,"uniqueOwnerPids":20,"distinctPrintWindowHashes":1}},"semanticComparison":{"macOS":"AXButton/Continue/AXEnabled.value/bool true","windows":"ControlType.Button/Continue/IsEnabled/bool true","pairing":"independent batches; no run-to-run pairing"},"qualification":{"acceptedGoldenCount":0,"nativeParity":"held","qualifiedTiming":"held","hitTesting":"held-not-attempted","controlledOcclusion":"held-unqualified","frozenTuple":"held-unbound","promotion":"none"},"independentReviewRefs":{"macOSAX":"factory/native/macos/disabled-enabled-observation-v1/independent-review/independent-review.json","windows":"factory/native/windows/disabled-repeatability-batch-v1/actual-review/report.json"}}
def load_and_audit():mraw,m,refs,payloads=load_inputs();return audit(mraw,m,refs,payloads)
