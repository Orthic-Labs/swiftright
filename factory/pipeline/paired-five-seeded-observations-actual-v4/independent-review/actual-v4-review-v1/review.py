#!/usr/bin/env python3
"""Offline review of v4 packet delta plus previously checked observation joins."""
import hashlib, importlib.util, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[5]
V3 = ROOT / "factory/pipeline/paired-five-seeded-observations-actual-v3"
V4 = ROOT / "factory/pipeline/paired-five-seeded-observations-actual-v4"
EXPECTED_STAGE = "ca853e374c071a9c519ca1920ef43784b1c3edf034c2babef0214e024e384c29"
EXPECTED_REPORT = "9060c5f2ddc3ec7349e9ce2661fca3eecd23d114e16b33edfe37fdce7fbda134"
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def load(path): return json.loads(path.read_text(encoding="utf-8-sig"))
def import_file(name, path):
    spec=importlib.util.spec_from_file_location(name,path)
    mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod
def verify():
    stage_path=V4/"stage-manifest.json"; stage=load(stage_path)
    assert sha(stage_path)==EXPECTED_STAGE
    assert stage["kind"]=="f9-paired-five-seeded-observations-actual-v4-stage" and stage["fileCount"]==5
    actual={p.name:p for p in V4.iterdir() if p.is_file() and p.name!="stage-manifest.json"}
    expected={x["path"]:x for x in stage["files"]}
    assert set(actual)==set(expected)
    for name,path in actual.items():
        item=expected[name]; assert path.stat().st_size==item["bytes"] and "sha256:"+sha(path)==item["sha256"]
    assert stage["totalBytes"]==sum(p.stat().st_size for p in actual.values())
    report_path=V4/"report.json"; report=load(report_path); assert sha(report_path)==EXPECTED_REPORT
    builder=import_file("paired_v4_builder",V4/"build_report.py")
    assert builder.validate(report) is True
    producer=builder.controls(report)
    assert len(producer)==10 and set(producer.values())=={"rejected"}
    archived=load(V4/"fault-controls.json")
    assert archived=={"baseline":"accepted","controls":producer}
    # All observation inventories & source/process joins are unchanged from v3; only report schema/version,
    # corrected F7 receipt references & explicit status-correction notes differ.
    assert sha(V3/"raw-pins.json")==sha(V4/"raw-pins.json")
    old=load(V3/"report.json")
    assert report["rawPins"]==old["rawPins"]
    assert report["caseCount"]==old["caseCount"]==5 and report["macFreshRuns"]==old["macFreshRuns"]==100
    assert report["windowsSeedSingles"]==old["windowsSeedSingles"]==5
    expected_names={"stack":"single-stack-overlay-r1.json","custom":"single-custom-layout-r1.json","padding":"single-padding-frame-r1.json","preference":"single-preference-key-r1.json","scroll":"single-scroll-view-r1.json"}
    for key, name in expected_names.items():
        ref=report["reviewReceipts"][key]
        path=ROOT/ref["path"]
        assert path.is_file() and path.name==name
        receipt=load(path)
        assert ref["status"]==receipt["decision"]=="CLEAR-ACTUAL-OBSERVATIONAL-JOINS"
        assert ref["sha256"]=="sha256:"+sha(path)
        assert receipt["count"]==1 and receipt["case"]["id"]==report["cases"][key]["macFresh100"]["caseId"]
    assert report["statusCorrections"]["macReviewHashLabel"].startswith("198a1d27")
    assert "foreign-lock-busy-no-launch" in report["statusCorrections"]["windowsCustomV5"]
    # Reuse v3's detailed, already exercised independent join walk against same raw/source bytes.
    # Adapt only the report's schema revision & receipt reference representation.
    verifier=import_file("paired_v3_independent_join_verifier",V3/"independent-review/actual-v3-review-v1/review.py")
    compatible=json.loads(json.dumps(report)); compatible["kind"]="f9-paired-five-seeded-observations-actual-v3"; compatible["version"]=3
    compatible["reviewReceipts"]={k:v["path"] for k,v in report["reviewReceipts"].items()}
    compatible.pop("statusCorrections")
    joins=verifier.verify(compatible,live=True)
    independent=verifier.fault_controls(compatible)
    assert joins["brokenWindowsReviewReferences"]=={}
    assert len(independent)==15 and set(independent.values())=={"rejected"}
    assert joins["macRuns"]==100 and joins["windowsRuns"]==5
    return {"decision":"CLEAR-OBSERVATIONAL-JOINS-ONLY","stageSha256":"sha256:"+sha(stage_path),"reportSha256":"sha256:"+sha(report_path),"stageFiles":len(actual),"stageBytes":stage["totalBytes"],"macRuns":joins["macRuns"],"windowsSingles":joins["windowsRuns"],"rawPinsIdenticalToV3":True,"reviewReceiptsResolvedAndHashBound":5,"producerFaultsRejected":len(producer),"independentFaultsRejected":len(independent),"legacyMacRawOrCaptureHashesReused":False,"holds":["custom AX labels unavailable","scroll raw labels unobserved & offscreen held","Windows native OS termination unproven; HasExited receipt only","native parity","qualified paint","qualified timing","goldens","registry promotion"]}
if __name__=="__main__": print(json.dumps(verify(),indent=2,sort_keys=True))
