#!/usr/bin/env python3
"""Build v3 candidate packet from fresh Mac seed-origin receipts & seeded Windows singles."""
from __future__ import annotations
import copy, hashlib, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "factory/pipeline/paired-five-seeded-observations-actual-v4"
MACROOT = ROOT / "factory/oracle/mac/seed-origin-actual-v1"
WINROOT = ROOT / "factory/native/windows/round1-seeded-native-v2"
MACLINEAGE = MACROOT / "lineage.json"
MACREVIEW = MACROOT / "independent-review/review-report.json"
MACPROCESS = MACROOT / "independent-review/independent-review-process-receipt.json"
AXCLIENT = MACROOT / "fresh-ax-client.json"
AXRECEIPT = MACROOT / "ax-compiler-receipt.json"
SEED = 14577611000270672472
ROLE_MAP = {"AXStaticText": "ControlType.Text"}
SUCCESS = "captured-single-observational-uia-printwindow"

CASES = {
    "stack": {"block": "swiftui.stack-overlay", "id": "swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258", "win": "single-stack-overlay-r1", "fetchComplete": 33},
    "custom": {"block": "swiftui.custom-layout", "id": "swiftui.custom-layout.recipe.gate-seeded.ca4e13f820f5d258", "win": "single-custom-layout-r1", "fetchComplete": 32},
    "padding": {"block": "swiftui.padding-frame", "id": "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258", "win": "single-padding-frame-r1", "fetchComplete": 33},
    "preference": {"block": "swiftui.preference-key", "id": "swiftui.preference-key.recipe.gate-seeded.ca4e13f820f5d258", "win": "single-preference-key-r1", "fetchComplete": 33},
    "scroll": {"block": "swiftui.scroll-view", "id": "swiftui.scroll-view.recipe.gate-seeded.ca4e13f820f5d258", "win": "single-scroll-view-r1", "fetchComplete": 34},
}

LINEAGE = None

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)

def inventory(root: Path):
    files = []
    for path in sorted((p for p in root.rglob("*") if p.is_file()), key=lambda p: p.relative_to(root).as_posix()):
        files.append({"path": path.relative_to(root).as_posix(), "bytes": path.stat().st_size, "sha256": sha(path)})
    encoded = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return {"root": str(root.relative_to(ROOT)), "exists": root.exists(), "fileCount": len(files), "bytes": sum(x["bytes"] for x in files), "inventorySha256": "sha256:" + hashlib.sha256(encoded).hexdigest(), "files": files}

def file_ref(path: Path):
    return {"path": str(path.relative_to(ROOT)), "bytes": path.stat().st_size, "sha256": sha(path)}

def receipt_ref(path: Path, status=None):
    data = load(path)
    return {"path": str(path.relative_to(ROOT)), "sha256": sha(path), "status": status or data.get("status") or data.get("decision")}

def source_refs(case_root: Path, summary):
    refs = []
    for name, value in sorted(summary["compilerReceipt"]["compiler"]["sourceAfter"].items()):
        archive = MACROOT / "archive" / case_root.name / "source" / name
        assert archive.exists() and sha(archive) == value["sha256"]
        refs.append(file_ref(archive))
    return refs

def mac_case(key):
    cfg = CASES[key]
    root = MACROOT / cfg["id"]
    summary_path = root / "summary.json"
    summary = load(summary_path)
    line = next(c for c in LINEAGE["cases"] if c["caseId"] == cfg["id"])
    assert summary["case"]["id"] == cfg["id"] == line["caseId"]
    case_hash = summary["case"]["hash"]
    source_path = MACROOT / "input-snapshot" / (cfg["id"] + ".swift")
    assert source_path.exists()
    source_hash = sha(source_path)
    assert source_hash == summary["sourceHash"] == line["sourceInputSha256"]
    binary_path = MACROOT / "archive" / cfg["id"] / "binary" / "capture-host"
    assert binary_path.exists()
    binary_hash = sha(binary_path)
    assert binary_hash == summary["binaryHash"] == line["binarySha256"]
    compiler_path = root / "compiler-receipt.json"
    compiler = load(compiler_path)
    comp = compiler["compiler"]
    assert compiler["status"] == "SUCCESS" and comp["exitCode"] == 0
    assert comp["outputBinary"]["sha256"] == binary_hash
    assert sha(compiler_path) == line["compilerReceiptSha256"]
    runs = []
    for i in range(1, 21):
        run_root = root / f"run-{i:03d}"
        ext_path = run_root / "external-ax.raw.json"
        cap_path = run_root / "capture.json"
        inst_path = run_root / "instrumented.raw.json"
        clock_path = run_root / "clock.json"
        ext = load(ext_path)
        cap = load(cap_path)
        srun = next(r for r in summary["runs"] if r["run"] == i)
        lrun = next(r for r in line["runs"] if r["run"] == i)
        assert cap["case"]["id"] == cfg["id"] and cap["case"]["hash"] == case_hash
        assert srun["captureHash"] == lrun["captureHash"] == sha(cap_path)
        assert srun["externalAXRawHash"] == lrun["externalAXRawHash"] == sha(ext_path)
        assert srun["instrumented"]["rawHash"] == lrun["instrumentedRawHash"] == sha(inst_path)
        labels = [n.get("value") for n in walk(ext.get("steps", [{}])[0].get("tree", {})) if n.get("role") == "AXStaticText" and isinstance(n.get("value"), str) and n.get("value") != ext.get("windowTitle")]
        runs.append({
            "run": i,
            "rawAXSha256": sha(ext_path),
            "captureSha256": sha(cap_path),
            "instrumentedRawSha256": sha(inst_path),
            "clockSha256": sha(clock_path),
            "labels": labels,
            "rawStatus": srun["instrumented"]["status"],
            "externalAXStatus": srun.get("externalAX"),
            "offscreenStatus": srun.get("offscreen"),
            "timingRaw": load(clock_path),
        })
    return {
        "caseId": cfg["id"], "caseHash": case_hash, "sourceHash": source_hash,
        "path": str(root.relative_to(ROOT)), "summarySha256": sha(summary_path),
        "candidateOnly": True, "acceptance": "not-promoted", "fetchComplete": cfg["fetchComplete"],
        "sourceInput": file_ref(source_path), "binary": file_ref(binary_path),
        "mainCompiler": {"receipt": receipt_ref(compiler_path), "exitCode": comp["exitCode"], "argv": comp["argv"], "cwd": comp["cwd"], "sourceRefs": source_refs(root, summary)},
        "runs": runs, "rawInventory": inventory(root),
    }

def native_single(key):
    cfg = CASES[key]
    root = WINROOT / cfg["win"]
    batch = load(root / "batch.json")
    assert batch["requested"] == batch["attempted"] == 1 and batch["retry"] is False and len(batch["rows"]) == 1
    row = batch["rows"][0]
    run = root / "replays/run-001"
    nroot = run / "native-01"
    plan, obs, native, dispatch = [load(run / name) for name in ("plan.json", "observation.json", "native-observation.json", "dispatch.json")]
    ui = load(nroot / "native.uia.json")
    pixels = load(nroot / "native.pixels.json")
    cap = load(nroot / "capture-outcome.json")
    assert row["status"] == SUCCESS and dispatch["status"] == SUCCESS
    assert plan["case"]["id"] == native["case"]["id"] == cfg["id"] and plan["case"]["hash"] == native["case"]["hash"]
    assert plan["sourceHash"] == obs["sourceHash"] == native["sourceHash"]
    assert native["hostValid"] is True and native["exitCode"] == 0 and obs["exitCode"] == 0 and obs["timedOut"] is False
    assert obs["exeSha256"] == native["exeSha256"] == batch["exeHash"] and cap["exeHash"] == batch["exeHash"] and cap["sourceHash"] == cfg.get("sourceHash", plan["sourceHash"])
    assert cap["primaryError"] == "" and cap["cleanup"]["confirmedOwnedExit"] is True
    assert pixels["width"] == 800 and pixels["height"] == 600 and pixels["dpi"] == 240 and pixels["printWindowRepeatStable"] is True
    labels = [n.get("name") for n in walk(ui) if n.get("controlType") == "ControlType.Text" and isinstance(n.get("name"), str)]
    return {
        "mode": "windows-seeded-native-v2-single", "path": str(root.relative_to(ROOT)),
        "batchSha256": sha(root / "batch.json"), "caseId": cfg["id"], "caseHash": plan["case"]["hash"], "sourceHash": plan["sourceHash"],
        "exeHash": batch["exeHash"], "compileReceiptHash": batch["compileReceiptHash"], "requested": 1, "attempted": 1,
        "successfulObservations": 1, "nativeParity": "held", "shutdownQualification": "held-weak-hasexited-receipt",
        "row": {"index": 1, "run": "run-001", "valid": True, "exeHash": batch["exeHash"], "uiaLabels": labels,
                "uiaChildren": len(ui.get("children", [])), "uiaSha256": sha(nroot / "native.uia.json"),
                "nativeObservationSha256": sha(run / "native-observation.json"), "pixelsSha256": sha(nroot / "native.pixels.json"),
                "captureOutcomeSha256": sha(nroot / "capture-outcome.json"), "timingRaw": {k: obs.get(k) for k in ("startedAt", "processStartedAt", "finishedAt", "timedOut")}},
        "rawInventory": inventory(root),
    }

def auxiliary():
    client = load(AXCLIENT)
    receipt = load(AXRECEIPT)
    source = MACROOT / "archive/auxiliary/source/AXClient.swift"
    binary = MACROOT / "archive/auxiliary/binary/f5-ax-client"
    assert client["compilerStatus"] == "SUCCESS" and client["compilerExitCode"] == 0 and receipt["status"] == "SUCCESS"
    assert client["sourceHash"] == sha(source) and client["binaryHash"] == sha(binary)
    assert receipt["compiler"]["outputBinary"]["sha256"] == sha(binary)
    return {"client": file_ref(AXCLIENT), "source": file_ref(source), "binary": file_ref(binary), "compilerReceipt": receipt_ref(AXRECEIPT), "exitCode": receipt["compiler"]["exitCode"], "argv": receipt["compiler"]["argv"], "cwd": receipt["compiler"]["cwd"], "status": "SUCCESS"}

def make_report():
    mac = {key: mac_case(key) for key in CASES}
    win = {key: native_single(key) for key in CASES}
    comps = {}
    for key in CASES:
        wl = win[key]["row"]["uiaLabels"]
        ml = mac[key]["runs"][0]["labels"]
        all_same = all(run["labels"] == ml for run in mac[key]["runs"])
        if key == "custom":
            comps[key] = {"roleMap": ROLE_MAP, "windowsValues": [], "macValues": [], "macExternalAX": "held: AXHostingView has no AXStaticText", "exactSequenceMatch": False, "qualification": "held"}
        elif key == "scroll":
            comps[key] = {"roleMap": ROLE_MAP, "windowsValues": [{"role": "ControlType.Text", "value": x} for x in wl], "macValues": [{"role": "ControlType.Text", "value": x} for x in ml], "macRawStatuses": sorted({x["rawStatus"] for x in mac[key]["runs"]}), "exactSequenceMatch": False, "reason": "Mac offscreen status HELD; labels retained raw only", "qualification": "held"}
        else:
            comps[key] = {"roleMap": ROLE_MAP, "windowsValues": [{"role": "ControlType.Text", "value": x} for x in wl], "macValues": [{"role": "ControlType.Text", "value": x} for x in ml], "macRawStatuses": sorted({x["rawStatus"] for x in mac[key]["runs"]}), "exactSequenceMatch": all_same and wl == ml, "qualification": "held"}
    return {
        "kind": "f9-paired-five-seeded-observations-actual-v4", "version": 4, "candidateOnly": True, "seed": SEED,
        "caseCount": 5, "macFreshRuns": 100, "windowsSeedSingles": 5,
        "cases": {key: {"macFresh100": mac[key], "windowsSeedSingle": win[key]} for key in CASES},
        "accessibility": {"roleMap": ROLE_MAP, "adapter": "protected exact AXStaticText to ControlType.Text mapping; no role/name heuristics", "comparisons": comps},
        "provenance": {
            "macSeedOriginActualV1": {"root": str(MACROOT.relative_to(ROOT)), "lineage": receipt_ref(MACLINEAGE), "independentReview": receipt_ref(MACREVIEW), "reviewProcess": receipt_ref(MACPROCESS), "stageSha256": load(MACREVIEW)["stageSha256"]},
            "macCompilerOrigin": {"main": "admitted receipt-bound per case", "auxiliaryAX": "admitted receipt-bound", "auxiliary": auxiliary()},
            "macSourceArchive": {"path": str(MACROOT.relative_to(ROOT)), "kind": "fresh seed-origin actual-v1 source/case/raw/executable archive"},
            "seedNativeRoot": {"path": str(WINROOT.relative_to(ROOT)), "seed": SEED, "singleRunsOnly": True},
            "compilerOSOrigin": "Mac main & auxiliary AX compiler receipts admitted; Windows native OS exit remains held",
            "fetchCompleteByCase": {key: CASES[key]["fetchComplete"] for key in CASES},
        },
        "rawTiming": {"scope": "raw timestamps & clock hashes retained; no timing claim", "mac": {key: [x["timingRaw"] for x in mac[key]["runs"]] for key in CASES}, "windows": {key: win[key]["row"]["timingRaw"] for key in CASES}},
        "claims": {"semantic": "only exact role-mapped labels where fresh source/case/executable joins match & raw status is observed", "customAX": "held; Windows UIA children empty & Mac AXStaticText unavailable", "freshMacRawCaptures": 100, "legacyMacCaptureProofReused": False, "scrollOffscreen": "held", "preferenceSeedLabels": "0/1 only; no baseline 0/1/2 assumption", "nativeExit": "held", "nativeParity": "held", "qualifiedPaint": "held", "qualifiedTiming": "held", "goldens": 0, "registryPromotion": False, "promotion": "blocked-candidate-only"},
        "reviewReceipts": {key: receipt_ref(WINROOT / "independent-review/actual-review-f7-v1" / ("single-" + ("stack-overlay" if key == "stack" else "custom-layout" if key == "custom" else "padding-frame" if key == "padding" else "preference-key" if key == "preference" else "scroll-view") + "-r1.json")) for key in CASES},
        "statusCorrections": {"macReviewHashLabel": "198a1d27eea44fe01ad08a12d27623bca3495c8d30c340a47d016c3658fb1e64 is review-report hash, not review-process hash", "windowsCustomV5": "foreign-lock-busy-no-launch; diagnostic no-launch, not native failure"},
        "controls": {"runner": "build_report.py --fault-controls", "required": ["fresh source/case/executable mutation rejected", "fresh raw capture mutation rejected", "main compiler receipt mutation rejected", "auxiliary AX receipt mutation rejected", "old Mac proof path mutation rejected", "held parity/promotion mutation rejected"]},
        "rawPins": {"macRoots": {key: mac[key]["rawInventory"] for key in CASES}, "windowsRoots": {key: win[key]["rawInventory"] for key in CASES}},
    }

def validate(report):
    assert report["kind"] == "f9-paired-five-seeded-observations-actual-v4" and report["version"] == 4
    assert report["candidateOnly"] is True and report["seed"] == SEED and report["caseCount"] == 5 and report["macFreshRuns"] == 100 and report["windowsSeedSingles"] == 5
    assert report["claims"]["legacyMacCaptureProofReused"] is False
    assert report["claims"]["nativeExit"] == report["claims"]["nativeParity"] == report["claims"]["qualifiedPaint"] == report["claims"]["qualifiedTiming"] == "held"
    assert report["claims"]["goldens"] == 0 and report["claims"]["registryPromotion"] is False
    assert "seed-corrections-v1" not in json.dumps(report["provenance"]["macSeedOriginActualV1"])
    assert report["provenance"]["macSeedOriginActualV1"]["stageSha256"].startswith("sha256:419f334b")
    assert report["provenance"]["macCompilerOrigin"]["main"] == "admitted receipt-bound per case"
    assert report["provenance"]["macCompilerOrigin"]["auxiliaryAX"] == "admitted receipt-bound"
    assert report["provenance"]["fetchCompleteByCase"] == {"stack": 33, "custom": 32, "padding": 33, "preference": 33, "scroll": 34}
    for key, cfg in CASES.items():
        m = report["cases"][key]["macFresh100"]
        w = report["cases"][key]["windowsSeedSingle"]
        actual_root = MACROOT / cfg["id"]
        actual_summary = load(actual_root / "summary.json")
        assert len(m["runs"]) == 20 and m["rawInventory"] == inventory(actual_root)
        assert m["caseId"] == cfg["id"] and m["caseHash"] == actual_summary["case"]["hash"] and m["sourceHash"] == sha(MACROOT / "input-snapshot" / (cfg["id"] + ".swift")) and m["binary"]["sha256"] == sha(MACROOT / "archive" / cfg["id"] / "binary/capture-host")
        assert m["mainCompiler"]["receipt"]["sha256"] == sha(actual_root / "compiler-receipt.json") and m["mainCompiler"]["exitCode"] == 0
        for run in m["runs"]:
            actual_run = next(x for x in actual_summary["runs"] if x["run"] == run["run"])
            assert run["captureSha256"] == actual_run["captureHash"] and run["rawAXSha256"] == actual_run["externalAXRawHash"] and run["instrumentedRawSha256"] == actual_run["instrumented"]["rawHash"]
        assert all(x["rawStatus"] in ("OBSERVED", "UNOBSERVED") for x in m["runs"])
        assert w["successfulObservations"] == 1 and w["caseHash"] == m["caseHash"] and w["sourceHash"] == m["sourceHash"]
        assert w["row"]["valid"] is True and w["shutdownQualification"].startswith("held")
        assert w["rawInventory"] == inventory(WINROOT / cfg["win"])
        receipt_path = WINROOT / "independent-review/actual-review-f7-v1" / ("single-" + ("stack-overlay" if key == "stack" else "custom-layout" if key == "custom" else "padding-frame" if key == "padding" else "preference-key" if key == "preference" else "scroll-view") + "-r1.json")
        assert report["reviewReceipts"][key] == receipt_ref(receipt_path)
    assert report["statusCorrections"]["macReviewHashLabel"].startswith("198a1d27")
    assert "foreign-lock-busy-no-launch" in report["statusCorrections"]["windowsCustomV5"]
    aux = report["provenance"]["macCompilerOrigin"]["auxiliary"]
    assert aux["exitCode"] == 0 and aux["status"] == "SUCCESS" and aux["compilerReceipt"]["sha256"] == sha(AXRECEIPT)
    assert report["accessibility"]["comparisons"]["custom"]["qualification"] == "held"
    assert report["accessibility"]["comparisons"]["scroll"]["qualification"] == "held" and report["accessibility"]["comparisons"]["scroll"]["exactSequenceMatch"] is False
    assert all(len(x["labels"]) == 0 for x in report["cases"]["custom"]["macFresh100"]["runs"])
    assert all(x["offscreenStatus"] == "HELD" for x in report["cases"]["scroll"]["macFresh100"]["runs"])
    return True

def controls(report):
    validate(report)
    mutations = {
        "fresh-source": lambda q: q["cases"]["stack"]["macFresh100"].__setitem__("sourceHash", "sha256:" + "0" * 64),
        "fresh-case": lambda q: q["cases"]["padding"]["macFresh100"].__setitem__("caseHash", "sha256:" + "1" * 64),
        "fresh-executable": lambda q: q["cases"]["scroll"]["macFresh100"]["binary"].__setitem__("sha256", "sha256:" + "2" * 64),
        "fresh-raw": lambda q: q["cases"]["custom"]["macFresh100"]["runs"][0].__setitem__("captureSha256", "sha256:" + "3" * 64),
        "main-receipt": lambda q: q["cases"]["stack"]["macFresh100"]["mainCompiler"]["receipt"].__setitem__("sha256", "sha256:" + "4" * 64),
        "aux-receipt": lambda q: q["provenance"]["macCompilerOrigin"]["auxiliary"]["compilerReceipt"].__setitem__("sha256", "sha256:" + "5" * 64),
        "old-proof-path": lambda q: q["provenance"]["macSeedOriginActualV1"].__setitem__("legacyProof", "factory/oracle/mac/seed-corrections-v1/evidence"),
        "parity": lambda q: q["claims"].__setitem__("nativeParity", "qualified"),
        "dangling-review-receipt": lambda q: q["reviewReceipts"]["stack"].__setitem__("path", "factory/missing-review.json"),
        "wrong-custom-status": lambda q: q["statusCorrections"].__setitem__("windowsCustomV5", "native-failure"),
    }
    out = {}
    for name, mutate in mutations.items():
        trial = copy.deepcopy(report)
        mutate(trial)
        try:
            validate(trial)
        except (AssertionError, KeyError):
            out[name] = "rejected"
        else:
            out[name] = "accepted-BUG"
    assert all(value == "rejected" for value in out.values()), out
    return out

def stage_manifest():
    files = []
    for path in sorted(p for p in OUT.iterdir() if p.is_file() and p.name != "stage-manifest.json"):
        files.append({"path": path.name, "bytes": path.stat().st_size, "sha256": sha(path)})
    assert all(x["bytes"] < 100 * 1024 * 1024 for x in files)
    return {"kind": "f9-paired-five-seeded-observations-actual-v4-stage", "fileCount": len(files), "totalBytes": sum(x["bytes"] for x in files), "files": files}

def main():
    global LINEAGE
    LINEAGE = load(MACLINEAGE)
    report = make_report()
    validate(report)
    (OUT / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    (OUT / "raw-pins.json").write_text(json.dumps(report["rawPins"], indent=2, sort_keys=True) + "\n")
    controls_result = controls(report)
    (OUT / "fault-controls.json").write_text(json.dumps({"baseline": "accepted", "controls": controls_result}, indent=2, sort_keys=True) + "\n")
    (OUT / "README.md").write_text("""# Paired five seeded observations actual v4\n\nThis candidate packet binds fresh `oracle/mac/seed-origin-actual-v1` Mac source, case, raw, executable & main/auxiliary compiler receipts to five existing seeded-native-v2 Windows singles. It does not reuse legacy Mac capture proof. AXStaticText maps only to ControlType.Text. Custom AX & scroll offscreen remain held; Windows native exit remains held on weak HasExited receipts. Raw timing stays separate; parity, paint, timing qualification, goldens & promotion remain held.\n""")
    (OUT / "stage-manifest.json").write_text(json.dumps(stage_manifest(), indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": "ok", "macFreshRuns": 100, "windowsSeedSingles": 5, "macCompilerOrigin": "admitted", "scrollOffscreen": "held", "customAX": "held", "nativeExit": "held", "goldens": 0}, indent=2))

if __name__ == "__main__":
    main()
