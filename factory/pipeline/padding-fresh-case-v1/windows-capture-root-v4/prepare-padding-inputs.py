#!/usr/bin/env python3
"""Build source-bound Windows remap metadata from explicit Mac metadata & donor files.

This preparer never treats Windows paths as local paths, launches anything, or mutates
historic donor evidence. Windows files are represented by caller-supplied path/hash/size
records; donor capture/integration/helper references are derived from the sealed donor.
"""
from __future__ import annotations
import argparse, hashlib, json, stat
from pathlib import Path

MAX_FILE = 64 * 1024 * 1024; MAX_JSON = 2 * 1024 * 1024; MAX_TOTAL = 128 * 1024 * 1024
class Hold(ValueError): pass

def digest(path: Path, limit=MAX_FILE):
    st = path.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode): raise Hold(f"invalid donor file: {path}")
    if st.st_size > limit: raise Hold(f"bounded donor file exceeded: {path}")
    h = hashlib.sha256(); n = 0
    with path.open("rb") as src:
        while True:
            block = src.read(1024 * 1024)
            if not block: break
            n += len(block); h.update(block)
            if n > limit: raise Hold(f"donor file grew: {path}")
    if n != st.st_size: raise Hold(f"donor file changed: {path}")
    return h.hexdigest(), n

def read_json(path: Path, label: str):
    sha, n = digest(path, MAX_JSON)
    try: value = json.loads(path.read_text(encoding="utf-8-sig"))
    except Exception as exc: raise Hold(f"{label} invalid JSON") from exc
    if not isinstance(value, dict): raise Hold(f"{label} object required")
    return value, sha, n

def local_ref(path: Path, label: str, limit=MAX_FILE):
    sha, n = digest(path, limit)
    return {"path": str(path.resolve()), "sha256": "sha256:" + sha, "bytes": n, "origin": label}

def windows_ref(obj, key):
    if not isinstance(obj, dict): raise Hold(f"Windows input {key} must be object")
    path = obj.get("path"); sha = obj.get("sha256"); size = obj.get("bytes")
    if not isinstance(path, str) or not path or not (":" in path or path.startswith("\\\\")): raise Hold(f"Windows path missing: {key}")
    if not isinstance(sha, str) or not sha.startswith("sha256:") or len(sha) != 71: raise Hold(f"Windows hash missing: {key}")
    if not isinstance(size, int) or size < 0 or size > MAX_FILE: raise Hold(f"Windows bytes invalid: {key}")
    return {"path": path, "sha256": sha, "bytes": size, "role": obj.get("role", key), "windowsOnly": True}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--donor-root", required=True, type=Path)
    ap.add_argument("--case-meta", required=True, type=Path)
    ap.add_argument("--tuple-meta", required=True, type=Path)
    ap.add_argument("--plan-meta", required=True, type=Path)
    ap.add_argument("--compile-meta", required=True, type=Path)
    ap.add_argument("--windows-input-map", required=True, type=Path)
    ap.add_argument("--output", required=True, type=Path)
    ap.add_argument("--count", required=True, type=int, choices=(1, 20))
    a = ap.parse_args(); donor = a.donor_root.resolve()
    if not donor.is_dir() or donor.is_symlink(): raise Hold("donor root invalid")
    case, case_sha, _ = read_json(a.case_meta, "case metadata")
    tup, tup_sha, _ = read_json(a.tuple_meta, "tuple metadata")
    plan, plan_sha, _ = read_json(a.plan_meta, "fresh compile plan")
    compile_receipt, compile_sha, _ = read_json(a.compile_meta, "compile receipt")
    winmap, winmap_sha, winmap_bytes = read_json(a.windows_input_map, "Windows input map")
    if not isinstance(winmap.get("inputs"), dict) or not winmap["inputs"]: raise Hold("Windows input map inputs missing")
    if not isinstance(case.get("id"), str) or not isinstance(tup.get("id", tup.get("candidateID")), str): raise Hold("fresh identity missing")
    if compile_receipt.get("exitCode") not in (None, 0): raise Hold("compile receipt failed")
    donor_files = {
      "capturePlan": "capture-plan.json", "integrationBindings": "integration-bindings.json",
      "helperManifest": "root-stage-manifest.json", "sourceChecks": "source-checks.json",
      "externalRefs": "external-refs.json", "prepareCapture": "prepare-capture.ps1",
      "captureRepeat": "capture-repeat.ps1", "coordinator": "coordinator.ps1",
      "dispatch": "dispatch.ps1", "interactiveTask": "interactive-task.ps1",
      "issueBeforeLaunch": "issue-before-launch.ps1", "runControls": "run-controls.ps1",
      "sourceVerifier": "verify-source.py",
    }
    refs = {}; total = 0
    for key, rel in donor_files.items():
        p = donor / rel
        refs[key] = local_ref(p, "historical-padding-donor")
        total += refs[key]["bytes"]
    support = ["all-owned-release.ps1", "cleanup.ps1", "final-exit-certificate.ps1", "first-proof.ps1", "host-inputs.ps1", "integration.ps1", "lifecycle-timing.ps1", "owned-close.ps1", "pixels-background.ps1", "stream-seal.ps1", "verify-runtime-source.ps1"]
    worker = ["README.md", "invoke-worker.ps1", "local-source-controls.json", "read-uia.ps1", "root-stage-manifest.json", "run-controls.ps1", "schema.ps1", "test-final-release.ps1", "test-pure.ps1", "verify-source.py", "worker-contract.json", "worker.ps1"]
    helper_refs = []
    for rel in support:
        key = "support/" + rel; p = donor / key; r = local_ref(p, "historical-padding-donor"); helper_refs.append({"relativePath": key, **r}); total += r["bytes"]
    for rel in worker:
        key = "dependencies/uia-worker/" + rel; p = donor / key; r = local_ref(p, "historical-padding-donor"); helper_refs.append({"relativePath": key, **r}); total += r["bytes"]
    if total > MAX_TOTAL: raise Hold("donor refs exceed bounded total")
    capture_plan = json.loads((donor / "capture-plan.json").read_text(encoding="utf-8-sig"))
    context = {"kind": "historical-padding-donor-context-v1", "case": capture_plan.get("case"), "sourcePackagePath": capture_plan.get("sourcePackagePath"), "compiledHostPackagePath": capture_plan.get("compiledHostPackagePath"), "renderer": capture_plan.get("renderer"), "hostArguments": capture_plan.get("hostArguments"), "qualification": capture_plan.get("qualification"), "historical": True}
    win = {key: windows_ref(value, key) for key, value in winmap["inputs"].items()}
    doc = {
      "kind": "factory-padding-source-inputs-v3", "status": "fresh-source-bound-windows-remap-required", "count": a.count,
      "caseID": case["id"], "caseMetadataRef": local_ref(a.case_meta, "fresh-case-metadata", MAX_JSON),
      "tupleID": str(tup.get("id", tup.get("candidateID"))), "tupleMetadataRef": local_ref(a.tuple_meta, "fresh-tuple-metadata", MAX_JSON),
      "freshPlanRef": local_ref(a.plan_meta, "fresh-compile-plan", MAX_JSON), "compileReceiptRef": local_ref(a.compile_meta, "fresh-compile-receipt", MAX_JSON),
      "caseHash": "sha256:" + case_sha, "tupleHash": "sha256:" + tup_sha, "freshPlanHash": "sha256:" + plan_sha, "compileReceiptHash": "sha256:" + compile_sha,
      "windowsInputMapRef": {"path": str(a.windows_input_map.resolve()), "sha256": "sha256:" + winmap_sha, "bytes": winmap_bytes},
      "windowsInputs": win, "historicalDonor": True, "donorRoot": str(donor), "donorRefs": refs,
      "capturePlanRef": refs["capturePlan"], "captureContext": context,
      "contextRef": {"kind": "derived-historical-donor-context-v1", "capturePlanRef": refs["capturePlan"], "fields": context},
      "integrationBindingsRef": refs["integrationBindings"], "helperManifestRef": refs["helperManifest"], "helperRefs": helper_refs,
      "runtimeSourceCommit": str(tup.get("runtimeCommit", plan.get("runtimeSourceCommit", ""))),
      "rendererSha256": str(tup.get("rendererSha256", plan.get("renderer", {}).get("sha256", ""))),
      "freshIDsRequired": True, "historicalCaseReuse": False, "nativeActions": 0, "compilerActions": 0, "lockActions": 0,
      "limits": {"maxFileBytes": MAX_FILE, "maxJsonBytes": MAX_JSON, "maxTotalDonorBytes": MAX_TOTAL},
    }
    if a.output.exists(): raise Hold("fresh output required")
    raw = (json.dumps(doc, indent=2, sort_keys=True) + "\n").encode()
    if len(raw) > MAX_JSON: raise Hold("output metadata bound")
    a.output.parent.mkdir(parents=True, exist_ok=True); a.output.write_bytes(raw)
    print(json.dumps({"kind": doc["kind"], "output": str(a.output.resolve()), "donorFiles": len(refs) + len(helper_refs), "windowsInputs": len(win), "nativeActions": 0, "lockActions": 0}, separators=(",", ":")))

if __name__ == "__main__":
    try: main()
    except Exception as exc: raise SystemExit("HOLD: " + str(exc))
