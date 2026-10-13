#!/usr/bin/env python3
"""Materialize fresh r11 source stage from explicit pinned repository paths.
No discovery, execution, lock mutation, or qualification claim is performed.
"""
from __future__ import annotations
import argparse, hashlib, json, os, shutil
from pathlib import Path

MAX_FILE = 64 * 1024 * 1024
MAX_TOTAL = 128 * 1024 * 1024
EXPECTED_MEMORY = 1_073_741_824
EXPECTED_FLAGS = 512

SOURCES = (
    ("coordinator", "factory/pipeline/sr0-display-selfjob-v4/coordinator-selfjob-v5.ps1", "coordinator-selfjob-v5.ps1"),
    ("parser", "factory/pipeline/sr0-display-selfjob-v4/receipt-parser-v4.ps1", "receipt-parser-v4.ps1"),
    ("helper", "factory/pipeline/pilot-next-source-v1/windows-capture-v1/Sr0OwnedJobProcess-v15.cs", "Sr0OwnedJobProcess-v15.cs"),
    ("launcherHelper", "factory/pipeline/sr0-display-selfjob-v4/Sr0LauncherOwnedJobProcess-v4.cs", "Sr0LauncherOwnedJobProcess-v4.cs"),
    ("frozenTask", "qualification/tuple12-takeover/workload-controls-v8/task-workload.ps1", "task-workload-v8.ps1"),
    ("collector", "factory/pipeline/sr0-display-selfjob-root-v4/native-r10c-recovery-v1/collector-selfjob-v8-drain-pidjoin.ps1", "collector-selfjob-v8-drain-pidjoin.ps1"),
    ("drainTask", "factory/pipeline/sr0-display-selfjob-v4/v5-r6-integration-v1/task-workload-drain-v1.ps1", "task-workload-drain-v1.ps1"),
    ("drainHelper", "factory/pipeline/sr0-display-selfjob-v4/v5-r6-integration-v1/workload-drain-helper-v1.ps1", "workload-drain-helper-v1.ps1"),
    ("identityHelper", "factory/pipeline/sr0-display-selfjob-root-v4/native-r10c-recovery-v1/workload-identity-v7.ps1", "workload-identity-v7.ps1"),
    ("worker", "factory/pipeline/sr0-display-selfjob-root-v4/native-r10c-recovery-v1/run-once-v8-status.ps1", "run-once-v8-status.ps1"),
    ("schedule", "factory/pipeline/sr0-display-selfjob-v4/prospective-native-stage-v1/schedule-once-v7.ps1", "schedule-once-v7.ps1"),
    ("wrapper", "factory/pipeline/sr0-display-selfjob-v4/prospective-native-stage-v1/launch-once-v7.vbs", "launch-once-v7.vbs"),
    ("controlTestCollector", "factory/pipeline/sr0-display-selfjob-root-v4/native-r10c-recovery-v1/next-run-stage-v1/test-collector-v8-source-controls-r11.ps1", "source-controls/test-collector-v8-source-controls-r11.ps1"),
    ("controlTestCoordinator", "factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/test-coordinator-forced-stop-controls-v1.ps1", "source-controls/test-coordinator-forced-stop-controls-v1.ps1"),
    ("controlTestWrapper", "factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/test-v5-wrapper-controls-v1.ps1", "source-controls/test-v5-wrapper-controls-v1.ps1"),
    ("controlDisplayAdapter", "factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/display-parser-adapter-v1.ps1", "source-controls/display-parser-adapter-v1.ps1"),
    ("controlTestDisplayAdapter", "factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/test-display-parser-adapter-controls-v1.ps1", "source-controls/test-display-parser-adapter-controls-v1.ps1"),
    ("controlObserver", "factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/observer-source-v5-r1.ps1", "source-controls/observer-source-v5-r1.ps1"),
    ("controlTestObserver", "factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/test-observer-source-v5-controls-r1.ps1", "source-controls/test-observer-source-v5-controls-r1.ps1"),
    ("controlForcedStop", "factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/test-forced-stop-admission-v5.ps1", "source-controls/test-forced-stop-admission-v5.ps1"),
    ("controlMaterialize", "factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/materialize-analysis-inputs-v1.ps1", "source-controls/materialize-analysis-inputs-v1.ps1"),
    ("controlTestMaterialize", "factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/test-materialize-analysis-inputs-controls-v1.ps1", "source-controls/test-materialize-analysis-inputs-controls-v1.ps1"),
    ("controlAnalyze", "factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/analyze_workload-v3-adapter-v1.py", "source-controls/analyze_workload-v3-adapter-v1.py"),
    ("legacySourcePins", "factory/pipeline/sr0-display-selfjob-root-v4/v5-root-r6/source-pins.json", "source-controls/v5-root-source-pins.json"),
    ("integrationSourcePins", "factory/pipeline/sr0-display-selfjob-v4/v5-r6-integration-v1/source-pins.json", "source-controls/v5-r6-integration-source-pins.json"),
    ("integrationReadme", "factory/pipeline/sr0-display-selfjob-v4/v5-r6-integration-v1/README.md", "source-controls/v5-r6-integration-README.md"),
    ("controlSampler", "qualification/tuple12-takeover/workload-controls-v8/sample-resources.ps1", "control-root/sample-resources.ps1"),
    ("controlsDrain", "factory/pipeline/sr0-display-selfjob-v4/prospective-native-stage-v1/test-workload-drain-controls-r10.ps1", "test-workload-drain-controls-r10.ps1"),
    ("drainControls", "factory/pipeline/sr0-display-selfjob-root-v4/native-r10c-recovery-v1/next-run-stage-v1/run-source-controls-r11.ps1", "run-source-controls-r11.ps1"),
)

def fail(msg: str) -> None:
    raise SystemExit(f"r11 stage rejected: {msg}")

def digest(path: Path) -> tuple[int, str]:
    if path.is_symlink() or not path.is_file(): fail(f"source is not regular: {path}")
    size = path.stat().st_size
    if size > MAX_FILE: fail(f"source exceeds 64MiB: {path}")
    h = hashlib.sha256()
    with path.open("rb") as stream:
        while block := stream.read(1024 * 1024): h.update(block)
    return size, h.hexdigest()

def bounded_json(path: Path) -> dict:
    size, _ = digest(path)
    if size > 2 * 1024 * 1024: fail(f"JSON exceeds 2MiB: {path}")
    with path.open("r", encoding="utf-8") as stream: value = json.load(stream)
    if not isinstance(value, dict): fail(f"JSON object required: {path}")
    return value

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repository-root", required=True)
    ap.add_argument("--stage-root", required=True)
    ap.add_argument("--factory-root", required=True)
    ap.add_argument("--control-root", required=True)
    ap.add_argument("--control-receipt-root", required=True)
    ap.add_argument("--controls-receipt", required=True)
    ap.add_argument("--plan-out", required=True)
    ap.add_argument("--manifest-out", required=True)
    ap.add_argument("--run-root", required=True)
    ap.add_argument("--task-name", default="SR0-factory-display-selfjob-v7-root-r11")
    ap.add_argument("--tag", default="SR0-factory-display-selfjob-v7-root-r11")
    ap.add_argument("--base", default=r"D:\Claude\swiftright\.work\sr0-r12-workload-v1")
    ap.add_argument("--workload-exe", default=r"D:\Claude\swiftright\.work\sr0-r12-workload-v1\scratch\out\Products\Release-windows-x86_64\WorkloadWin.exe")
    ap.add_argument("--renderer-dll", default=r"D:\Claude\swiftright\.work\sr0-r12-workload-v1\scratch\out\Products\Release-windows-x86_64\swiftright_render.dll")
    ap.add_argument("--presentmon-exe", default=r"D:\Claude\tools\presentmon\PresentMon-2.6.0-x64.exe")
    ap.add_argument("--workload-exe-bytes", type=int, default=5233152)
    ap.add_argument("--workload-exe-sha256", default="7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c")
    ap.add_argument("--renderer-dll-bytes", type=int, default=11887616)
    ap.add_argument("--renderer-dll-sha256", default="7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2")
    ap.add_argument("--presentmon-exe-bytes", type=int, default=980320)
    ap.add_argument("--presentmon-exe-sha256", default="b2a706bc6ad475749e3b7e3409263aa1e6906d45bdcf993f6dbc0f660188f1af")
    ap.add_argument("--lock-path", default=r"D:\Claude\desktop.lock")
    args = ap.parse_args()
    repo = Path(args.repository_root).resolve()
    stage = Path(args.stage_root)
    if stage.exists(): fail(f"stage must be fresh: {stage}")
    controls = Path(args.controls_receipt)
    control_receipt = bounded_json(controls)
    if control_receipt.get("kind") != "sr0-display-workload-drain-controls-r10" or control_receipt.get("status") != "passed-source-controls" or control_receipt.get("nativeQualificationClaim") is not False:
        fail("drain controls receipt is not admitted source-controls evidence")
    stage.mkdir(parents=True)
    total = 0; entries = []; by_name = {}
    for name, source_rel, staged_rel in SOURCES:
        source = repo / source_rel
        size, sha = digest(source); total += size
        if total > MAX_TOTAL: fail("source mirror exceeds 128MiB")
        target = stage / staged_rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        check_size, check_sha = digest(target)
        if (size, sha) != (check_size, check_sha): fail(f"staged source drift: {name}")
        row = {"name": name, "path": staged_rel.replace(os.sep, "/"), "source": source_rel, "bytes": size, "sha256": sha}
        entries.append(row); by_name[name] = row
    control_root = Path(args.control_receipt_root)
    control_root.mkdir(parents=True, exist_ok=True)
    control_copy = control_root / "source-controls-donor-r10.json"
    if control_copy.exists(): fail(f"control receipt must be fresh: {control_copy}")
    shutil.copyfile(controls, control_copy)
    if digest(control_copy) != digest(controls): fail("control receipt copy drift")
    for fresh_path, label in ((Path(args.control_root), "control root"), (Path(args.run_root), "run root")):
        if fresh_path.exists() and any(fresh_path.iterdir()): fail(f"{label} must be fresh and empty: {fresh_path}")
        fresh_path.mkdir(parents=True, exist_ok=True)
    controls_sha = digest(controls)[1]
    binaries = (("workloadExe", args.workload_exe, args.workload_exe_bytes, args.workload_exe_sha256), ("rendererDll", args.renderer_dll, args.renderer_dll_bytes, args.renderer_dll_sha256), ("presentMonExe", args.presentmon_exe, args.presentmon_exe_bytes, args.presentmon_exe_sha256))
    binary_rows = []
    for name, binary_path, expected_bytes, expected_sha in binaries:
        observed_bytes, observed_sha = digest(Path(binary_path))
        if observed_bytes != expected_bytes or observed_sha.lower() != expected_sha.lower(): fail(f"binary pin mismatch: {name}")
        total += observed_bytes
        if total > MAX_TOTAL: fail("source closure exceeds 128MiB")
        binary_rows.append({"name":name,"path":binary_path,"source":binary_path,"bytes":observed_bytes,"sha256":observed_sha,"external":True})
    entries.extend(binary_rows)
    (stage / "source-input-rows.json").write_text(json.dumps({"schema":"sr0-display-selfjob-r11-source-input-rows","rows":entries,"totalBytes":total}, indent=2)+"\n", encoding="utf-8")
    paths = {name: str(stage / row["path"]) for name, row in by_name.items()}
    run = args.run_root
    source_pins = {name: row["sha256"] for name, row in by_name.items()}
    source_pins.update({"drainControlTestSha256": by_name["controlsDrain"]["sha256"], "drainControlRunnerSha256": by_name["drainControls"]["sha256"], "collector": by_name["collector"]["sha256"], "identityHelper": by_name["identityHelper"]["sha256"], "drainHelper": by_name["drainHelper"]["sha256"]})
    plan = {"schema":"sr0-display-selfjob-v4-fresh-one-run-r11","status":"source-pin-plan","execution":"fresh native diagnostic only; strict display gate retained; no eligibility claim","stageRoot":str(stage),"base":args.base,"factoryRoot":args.factory_root,"controlRoot":args.control_root,"controlReceiptRoot":args.control_receipt_root,"requiredControlReceipts":["drain-controls-r11.json"],"donorControlReceipt":control_copy.name,"runRoot":run,"manifestPath":str(Path(args.manifest_out)),"sourceRowsPath":str(stage / "source-input-rows.json"),"taskName":args.task_name,"tag":args.tag,"schedulePath":paths["schedule"],"workerPath":paths["worker"],"collectorPath":paths["collector"],"coordinatorPath":paths["coordinator"],"wrapperPath":paths["wrapper"],"frozenTaskPath":paths["frozenTask"],"drainTaskPath":paths["drainTask"],"helperPath":paths["helper"],"drainHelperPath":paths["drainHelper"],"identityHelperPath":paths["identityHelper"],"parserPath":paths["parser"],"launcherHelperPath":paths["launcherHelper"],"workloadExe":args.workload_exe,"rendererDll":args.renderer_dll,"presentMonExe":args.presentmon_exe,"workloadExeSha256":args.workload_exe_sha256,"rendererDllSha256":args.renderer_dll_sha256,"presentMonSha256":args.presentmon_exe_sha256,"lockPath":args.lock_path,"memoryLimitFlags":"0x200","aggregateJobMemoryLimitBytes":EXPECTED_MEMORY,"killOnJobClose":False,"deadlineSeconds":900,"pollSeconds":1,"warmup":10,"measure":60,"runs":1,"rows":200,"keyRate":10,"noActivate":True,"noResources":True,"streamCapBytes":8388608,"csvCapBytes":67108864,"nativeActions":0,"qualificationClaim":False,"sourcePins":source_pins,"sourceFiles":entries}
    plan_path = Path(args.plan_out); manifest_path = Path(args.manifest_out)
    plan_path.parent.mkdir(parents=True, exist_ok=True); manifest_path.parent.mkdir(parents=True, exist_ok=True)
    plan_path.write_text(json.dumps(plan, indent=2)+"\n", encoding="utf-8")
    manifest = {"schema":"sr0-display-selfjob-v5-one-shot","candidateLineage":"native-r10c-recovery-v1-r11","taskName":args.task_name,"tag":args.tag,"base":args.base,"controlRoot":args.control_root,"controlReceiptRoot":args.control_receipt_root,"requiredControlReceipts":["drain-controls-r11.json"],"donorControlReceipt":control_copy.name,"noActivate":True,"noResources":True,"runs":1,"warmup":10,"measure":60,"rows":200,"keyRate":10,"deadlineSeconds":900,"pollSeconds":1,"aggregateJobMemoryLimitBytes":EXPECTED_MEMORY,"aggregateLimitFlags":EXPECTED_FLAGS,"killOnJobClose":False,"workloadExe":args.workload_exe,"rendererDll":args.renderer_dll,"presentMonExe":args.presentmon_exe,"lockPath":args.lock_path,"runRoot":run,"resultFile":run+"\\result-workload.txt","memoryReceiptPath":run+"\\collector-receipt.json","startReceiptPath":run+"\\start-receipt.json","coordinatorOutputPath":run+"\\coordinator-verdict.json","launcherReceiptPath":run+"\\launcher-receipt.json","sourceRowsPath":str(stage / "source-input-rows.json"),"controlsReceiptSha256":controls_sha}
    for name, row in by_name.items():
        manifest[name + "Path"] = paths[name]; manifest[name + "Sha256"] = row["sha256"]
    manifest["workloadExeSha256"] = args.workload_exe_sha256
    manifest["rendererDllSha256"] = args.renderer_dll_sha256
    manifest["presentMonSha256"] = args.presentmon_exe_sha256
    manifest_path.write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"status":"staged-source-only","stageRoot":str(stage),"plan":str(plan_path),"manifest":str(manifest_path),"sourceCount":len(entries),"totalBytes":total,"nativeQualificationClaim":False}))
    return 0
if __name__ == "__main__": raise SystemExit(main())
