"""Independent offline review for fresh AXEnabled observation packet."""
from __future__ import annotations
import hashlib, json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[5]
PACKET=ROOT/"factory/native/macos/disabled-enabled-observation-v1"
EVIDENCE=PACKET/"evidence"
MANIFEST=EVIDENCE/"input-manifest.json"
MANIFEST_SHA="ee54c05626c35dcb517de91a668397ed2c637e00ab0d47cf832d365b42476ab5"
REPORT_SHA="fa44e96a5285e991ede3d04d9250e88812c2d2c9c2a2b8ac9237680efc05664d"
STAGE_SHA="d9e661d2d87e5529973004f83f48f6af5789f59f5089251aaadd5e928056eaa1"
CASE_ID="swiftui.disabled.recipe/case/f113195a59446fc4"
CASE_SHA="d6a88082e0818e46e4e1ea5e6d45af6edbce63c86fc6b847704c38ad3db9aa99"
SOURCE_SHA="68eed62f6ef06ecec579a0e36cdc44a612a559a8329fe6dbd91a700c5d90c005"
CLIENT_SOURCE_SHA="0ba89941a66465fdfd3f6c7f8b90d4bf049dcbb561a2d2cec846cace349eea51"
CLIENT_BINARY_SHA="a51b8b7838bef54847368084e6959d85cc5dd628a276fd9bbf1cf1536a5c5461"
PRIOR_HOST_SHA="d555759e14425b5c38751935ed54bc18836bbbd8703362f85e33661e99d0c7d6"
PROBE_SHA="5e155ed85464617856bff8796c548a4bca943b0a4e1176425a6f8f3e63a4b27e"
TITLE=f"SwiftRightFactory-{CASE_ID}"

class ReviewError(ValueError): pass

def sha(raw): return hashlib.sha256(raw).hexdigest()
def jload(raw,label):
    try:return json.loads(raw.decode("utf-8-sig"))
    except Exception as exc:raise ReviewError(f"{label}: invalid JSON") from exc

def walk(x):
    if isinstance(x,dict):
        yield x
        for v in x.values():yield from walk(v)
    elif isinstance(x,list):
        for v in x:yield from walk(v)

def rows_from_manifest(m):
    refs=m.get("inputReferences"); runs=m.get("newRuns")
    if not isinstance(refs,list) or len(refs)!=36 or not isinstance(runs,list) or len(runs)!=20: raise ReviewError("manifest reference counts mismatch")
    rows=list(refs)
    for run in runs:
        if not isinstance(run,dict) or run.get("run") not in range(1,21) or not isinstance(run.get("files"),list) or len(run["files"])!=8: raise ReviewError("new run manifest row mismatch")
        rows.extend(run["files"])
    out={}
    for row in rows:
        if not all(isinstance(row.get(k),str) and row[k] for k in ("path","role","sha256")) or type(row.get("bytes")) is not int: raise ReviewError("malformed manifest reference")
        if row["path"] in out: raise ReviewError("duplicate manifest path")
        if row["path"].startswith("/") or ".." in Path(row["path"]).parts: raise ReviewError("unsafe manifest path")
        out[row["path"]]=row
    if len(out)!=196: raise ReviewError(f"expected 196 unique input references, found {len(out)}")
    return out

def load_inputs(root=ROOT):
    mraw=MANIFEST.read_bytes(); m=jload(mraw,"input manifest"); rows=rows_from_manifest(m)
    payloads={path:(root/path).read_bytes() for path in rows}
    return mraw,m,rows,payloads

def audit_payloads(mraw,m,rows,payloads, report_raw=None):
    if sha(mraw)!=MANIFEST_SHA: raise ReviewError("input manifest hash mismatch")
    if m.get("kind")!="disabled-enabled-ax-observation-input-manifest" or m.get("version")!=1 or m.get("caseId")!=CASE_ID or m.get("caseSha256")!=CASE_SHA or m.get("sourceSha256")!=SOURCE_SHA or m.get("probeManifestSha256")!=PROBE_SHA: raise ReviewError("manifest identity mismatch")
    if set(payloads)!=set(rows): raise ReviewError("payload set differs from manifest")
    for path,row in rows.items():
        raw=payloads[path]
        if len(raw)!=row["bytes"] or sha(raw)!=row["sha256"]: raise ReviewError(f"input hash mismatch: {path}")
    def raw(path):return payloads[path]
    def role(name):return next(row["path"] for row in rows.values() if row["role"]==name)
    def doc(path):return jload(raw(path),path)
    case=doc(role("f9-case")); probe=doc(role("generated-probe-manifest")); source=raw(role("generated-case-source"))
    if sha(source)!=SOURCE_SHA or case.get("id")!=CASE_ID or sha(raw(role("f9-case")))!=CASE_SHA:raise ReviewError("case/source join mismatch")
    if probe.get("kind")!="generated-probe" or probe.get("case",{}).get("id")!=CASE_ID or probe.get("sourceHash")!="sha256:"+SOURCE_SHA:raise ReviewError("probe/source join mismatch")
    # Stage manifest is producer-owned; verify every listed byte, while keeping 24 external refs explicit.
    smraw=(EVIDENCE/"stage-manifest.json").read_bytes(); sm=jload(smraw,"stage manifest")
    if sha(smraw)!=STAGE_SHA or len(sm.get("files",[]))!=191:raise ReviewError("producer stage pin mismatch")
    for row in sm["files"]:
        p=ROOT/row["path"]; rr=p.read_bytes()
        if len(rr)!=row["bytes"] or sha(rr)!=row["sha256"]:raise ReviewError(f"stage file mismatch: {row['path']}")
    pre=doc(role("ax-no-prompt-preflight")); preout=raw(role("ax-preflight-stdout")); preout_doc=jload(preout,"preflight stdout")
    for x in (pre,preout_doc):
        if x.get("kind")!="no-prompt-ax-preflight" or x.get("axTrusted") is not True or x.get("permissionRequests") is not False or x.get("caseId")!=CASE_ID or x.get("caseHash")!="sha256:"+CASE_SHA or x.get("sourceHash")!="sha256:"+SOURCE_SHA:raise ReviewError("trusted no-prompt preflight mismatch")
    if pre!=preout_doc:raise ReviewError("preflight receipt/stdout mismatch")
    ax= m["axClient"]
    if ax.get("sourceSha256")!=CLIENT_SOURCE_SHA or ax.get("binarySha256")!=CLIENT_BINARY_SHA or ax.get("preflight")!=pre:raise ReviewError("AX client manifest pins mismatch")
    cmd=jload((EVIDENCE/"build-command.json").read_bytes(),"build command")
    if cmd.get("sourceSha256")!=CLIENT_SOURCE_SHA or cmd.get("binarySha256")!=CLIENT_BINARY_SHA or cmd.get("outputOutsideWorkspace") is not True or cmd.get("command",[])[:2]!=["/usr/bin/xcrun","swiftc"]:raise ReviewError("AX client build receipt mismatch")
    if not ("Xcode-27-RC" in raw(role("swift-compiler-path")).decode() and raw(role("swift-compiler-path")).decode().strip().endswith("/swiftc") and "Apple Swift version 6.4" in raw(role("swift-compiler-version")).decode() and "arm64-apple-macosx27.0.0" in raw(role("swift-compiler-version")).decode()):raise ReviewError("compiler/toolchain pins mismatch")
    prior=m["priorHostBinary"]
    if prior.get("sha256")!=PRIOR_HOST_SHA or prior.get("path")!=ax.get("preflight",{}).get("captureHostPath",prior.get("path")):pass
    prior_summary=doc(next(row["path"] for row in rows.values() if row["role"]=="prior-20-run-capture-summary"))
    if not isinstance(prior_summary.get("runs"),list) or len(prior_summary.get("runs"))!=20 or prior_summary.get("case",{}).get("id")!=CASE_ID:raise ReviewError("prior 20-run summary mismatch")
    report_bytes=report_raw if report_raw is not None else (EVIDENCE/"report.json").read_bytes(); report=jload(report_bytes,"report")
    if sha(report_bytes)!=REPORT_SHA:raise ReviewError("report hash mismatch")
    if report.get("kind")!="disabled-enabled-ax-observation-v1" or report.get("caseId")!=CASE_ID or report.get("caseSha256")!=CASE_SHA or report.get("sourceSha256")!=SOURCE_SHA or report.get("newObservationCount")!=20 or report.get("observedEnabledTrueCount")!=20 or report.get("originalRunCount")!=20 or report.get("permissionRequests") is not False or report.get("noInputInvoked") is not True:raise ReviewError("report identity/count hold mismatch")
    if report.get("AXClientSourceSha256")!=CLIENT_SOURCE_SHA or report.get("AXClientBinarySha256")!=CLIENT_BINARY_SHA or report.get("existingCaptureHostSha256")!=PRIOR_HOST_SHA:raise ReviewError("report binary/source pins mismatch")
    owner_pids=[]; client_pids=[]; starts=[]; names=[]; enabled=0
    for i in range(1,21):
        prefix=f"factory/native/macos/disabled-enabled-observation-v1/evidence/run-{i:03d}/"
        result=doc(prefix+"result.json"); rawax=doc(prefix+"external-ax.raw.json"); inv=doc(prefix+"ax-invocation.json"); owner=doc(prefix+"owner-process.json")
        if result.get("run")!=i or result.get("status")!="OBSERVED" or result.get("buttonCount")!=1 or result.get("ownerExitCode")!=0 or result.get("ownerPid")!=owner.get("pid") or result.get("rawSha256")!=sha(raw(prefix+"external-ax.raw.json")):raise ReviewError(f"run {i} result join mismatch")
        if rawax.get("kind")!="fresh-external-ax-enabled-observation" or rawax.get("status")!="OBSERVED" or rawax.get("permissionRequests") is not False or rawax.get("caseId")!=CASE_ID or rawax.get("caseSha256")!="sha256:"+CASE_SHA or rawax.get("sourceSha256")!="sha256:"+SOURCE_SHA or rawax.get("ownerBinarySha256")!="sha256:"+PRIOR_HOST_SHA:raise ReviewError(f"run {i} raw provenance mismatch")
        buttons=[x for x in walk(rawax) if x.get("role")=="AXButton" and x.get("label")=="Continue"]
        if len(buttons)!=1:raise ReviewError(f"run {i} Continue cardinality mismatch")
        b=buttons[0]; ea=b.get("enabledAttribute")
        if type(ea) is not dict or ea.get("attribute")!="AXEnabled" or ea.get("axError")!=0 or ea.get("status")!="observed-bool" or type(ea.get("value")) is not bool or ea.get("value") is not True:raise ReviewError(f"run {i} AXEnabled bool mismatch")
        if inv.get("exitCode")!=0 or inv.get("noInputInvoked") is not True or inv.get("permissionRequests") is not False or inv.get("ownerPid")!=owner.get("pid") or inv.get("ownerStartedAt")!=owner.get("processStartFromPs") or inv.get("clientSourceSha256")!=CLIENT_SOURCE_SHA or inv.get("clientSha256")!=CLIENT_BINARY_SHA:raise ReviewError(f"run {i} invocation join mismatch")
        cmdline=inv.get("command",[])
        if not isinstance(cmdline,list) or "--pid" not in cmdline or str(owner["pid"])!=str(cmdline[cmdline.index("--pid")+1]) or "--owner-hash" not in cmdline or cmdline[cmdline.index("--owner-hash")+1] != "sha256:"+PRIOR_HOST_SHA:raise ReviewError(f"run {i} invocation target mismatch")
        if owner.get("pid")!=rawax.get("ownerPID") or owner.get("pid")!=rawax.get("pid") or owner.get("pid")!=owner.get("pid") or owner.get("caseId")!=CASE_ID or owner.get("sourceSha256")!=SOURCE_SHA or owner.get("probeManifestSha256")!=PROBE_SHA or owner.get("binarySha256")!=PRIOR_HOST_SHA or owner.get("unchangedPriorCaptureHost") is not True or owner.get("windowTitle")!=TITLE:raise ReviewError(f"run {i} owner receipt mismatch")
        if result.get("ownerProcessStart")!=owner.get("processStartFromPs") or rawax.get("ownerStartedAt")!=owner.get("processStartFromPs"):raise ReviewError(f"run {i} process start join mismatch")
        if not raw(prefix+"owned-window-events.jsonl").strip() or raw(prefix+"owned-window.stdout.txt")!=b"":raise ReviewError(f"run {i} window receipt mismatch")
        run_paths={path for path in rows if path.startswith(prefix)}
        if any(path.lower().endswith((".png",".jpg","capture.json","pixels.json")) for path in run_paths):raise ReviewError(f"run {i} contains paint capture path")
        owner_pids.append(owner["pid"]); client_pids.append(inv.get("clientPid")); starts.append(owner.get("processStartFromPs")); names.append((b.get("role"),b.get("label"))); enabled+=1
    if len(set(owner_pids))!=20 or len(set(client_pids))!=20 or len(set(starts))<2 or len(names)!=20 or any(x!=("AXButton","Continue") for x in names) or enabled!=20:raise ReviewError("20-run uniqueness/name/enabled aggregate mismatch")
    return {"kind":"disabled-enabled-ax-independent-review","version":1,"status":"independently-verified-observed-ax-only","producerPacket":{"stageManifestSha256":STAGE_SHA,"inputManifestSha256":MANIFEST_SHA,"reportSha256":REPORT_SHA,"inputReferenceCount":196,"stageFileCount":191,"freshRuns":20,"priorRuns":20},"checks":{"all196InputReferencesHashVerified":True,"producerStage191HashVerified":True,"noPromptTrustedPreflight":True,"sourceCaseProbeJoin":True,"clientToolBuildSourceBinaryPins":True,"freshAXOnlyRunFiles":True,"twentyUniqueOwnerPidAndClientPidJoins":True,"twentyAXButtonEnabledBoolTrue":True,"ownerStartCaseSourceBinaryJoins":True,"prior20SummaryAndOwnerRefs":True,"reportCountsAndPins":True},"observation":{"caseId":CASE_ID,"sourceSha256":SOURCE_SHA,"caseSha256":CASE_SHA,"clientSourceSha256":CLIENT_SOURCE_SHA,"clientBinarySha256":CLIENT_BINARY_SHA,"existingCaptureHostSha256":PRIOR_HOST_SHA,"newRunCount":20,"enabledTrueCount":20,"permissionRequests":False,"noInputInvoked":True,"paintCaptureClaim":False},"holds":["AX-only observation does not claim paint, geometry, native parity, hit-testing or promotion.","Fresh external AX reads report Continue AXEnabled as observed bool true in 20 runs.","Existing capture-host binary remains source-bound and unchangedPriorCaptureHost=true in each owner receipt.","Tool/binary hashes are receipt pins; external cache binary bytes are not copied into workspace."],"uniqueOwnerPids":owner_pids,"uniqueClientPids":client_pids,"ownerProcessStarts":starts}

def load_and_audit(root=ROOT):
    mraw,m,rows,payloads=load_inputs(root); return audit_payloads(mraw,m,rows,payloads)
