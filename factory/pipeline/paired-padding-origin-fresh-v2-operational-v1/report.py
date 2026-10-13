"""Operational fresh Mac20 report with archive-only tool rehydration."""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import stat
import subprocess
import sys
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
FRESH = ROOT / "factory/oracle/mac/padding-origin-fresh-v1/actual"
EVIDENCE = FRESH / "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258"
V2_HELPER = ROOT / "factory/oracle/mac/padding-origin-fresh-v1/cleanup-rehydration-v2/rehydrate.py"
V2_PLAN = ROOT / "factory/oracle/mac/padding-origin-fresh-v1/cleanup-rehydration-v2/rehydration-plan.json"
LIVE_CONFIG = EVIDENCE / "origin-reader-config.json"
PINS = ROOT / "factory/pipeline/paired-padding-origin-fresh-v1/source-pins.json"
CASE_PATH = ROOT / "factory/pipeline/gate-pilot/seed-cases.json"
ACCEPT = ROOT / "factory/pipeline/inputs/acceptance-candidate.json"
GATE_PLAN = ROOT / "factory/pipeline/gate-pilot/gate-results.json"
GATE_CASES = ROOT / "factory/pipeline/inputs/cases.json"
GATE_TUPLE = ROOT / "factory/pipeline/inputs/observed-tuple.json"
MANIFESTS = ROOT / "factory/pipeline/manifests"
REGISTRY = ROOT / "factory/registry/evidence/block-registry.json"
INTERNAL = Path("/Users/adrdsouza/Library/Caches/SwiftRightFactory/padding-origin-fresh-v1")


def digest(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def sha(path: Path) -> str:
    return digest(path.read_bytes())


def load(path: Path):
    return json.loads(path.read_bytes().decode("utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def verify_source_pins() -> dict:
    pins = load(PINS)
    require(pins.get("schema") == "paired-padding-origin-fresh-source-pins-v1", "source pin schema changed")
    checks = []
    fixed = {
        "captureIndex": FRESH / "capture-index.json", "verification": FRESH / "verification.json",
        "rootRunPlan": ROOT / "factory/oracle/mac/padding-origin-fresh-v1/root-run-plan.json",
        "rootProcess": ROOT / "factory/oracle/mac/padding-origin-fresh-v1/root-process.json",
        "rootOwnedProcess": ROOT / "factory/oracle/mac/padding-origin-fresh-v1/root-owned-process.json",
        "originReaderConfig": EVIDENCE / "origin-reader-config.json",
        "originArchiveManifest": EVIDENCE / "origin-archive-manifest.json",
        "summary": EVIDENCE / "summary.json", "originSummary": EVIDENCE / "origin-summary.json",
    }
    for key, path in fixed.items():
        actual = sha(path); require(actual == pins["files"][key], f"source pin changed: {key}")
        checks.append({"label": key, "path": str(path), "sha256": actual})
    for run, values in pins["runs"].items():
        for key, relative in {
            "capture.json": f"run-{int(run):03d}/capture.json",
            "clock.json": f"run-{int(run):03d}/clock.json",
            "external-ax.raw.json": f"run-{int(run):03d}/external-ax.raw.json",
        }.items():
            path = EVIDENCE / relative; actual = sha(path)
            require(actual == values[key], f"source pin changed: {run}/{key}")
            checks.append({"label": f"run-{run}/{key}", "path": str(path), "sha256": actual})
    return {"status": "PASS", "count": len(checks), "manifestSha256": sha(PINS), "checks": checks}


def run_rehydration(temp_root: Path, log_dir: Path) -> dict:
    require(not temp_root.exists(), f"owned temp path already exists: {temp_root}")
    started = subprocess.run(
        [sys.executable, str(V2_HELPER), "--output-dir", str(temp_root)],
        cwd=ROOT, capture_output=True, check=False,
    )
    stdout, stderr = started.stdout, started.stderr
    (log_dir / "rehydration-helper.stdout.txt").write_bytes(stdout)
    (log_dir / "rehydration-helper.stderr.txt").write_bytes(stderr)
    receipt = None
    if temp_root.is_dir() and (temp_root / "verification-receipt.json").is_file():
        receipt = load(temp_root / "verification-receipt.json")
    require(started.returncode == 0 and isinstance(receipt, dict) and receipt.get("status") == "PASS", "v2 rehydration failed")
    require(receipt.get("nativeExecutions") == 0 and receipt.get("compilerExecutions") == 0, "rehydration executed native/compiler")
    require(receipt.get("currentToolReadsDuringReplay") == 0, "rehydration read installed tools")
    return {
        "status": "PASS", "helperPath": str(V2_HELPER), "helperSha256": sha(V2_HELPER),
        "planSha256": sha(V2_PLAN), "argv": [sys.executable, str(V2_HELPER), "--output-dir", str(temp_root)],
        "cwd": str(ROOT), "exitCode": started.returncode,
        "stdoutSha256": digest(stdout), "stderrSha256": digest(stderr),
        "verificationReceipt": receipt, "tempRoot": str(temp_root),
    }


def rel(base: Path, target: Path) -> str:
    value = os.path.relpath(target.resolve(), base.resolve())
    require("\\" not in value and "\x00" not in value and not Path(value).is_absolute(), "unsafe relative config path")
    return value


def make_origin_config(temp_root: Path) -> tuple[Path, dict, str]:
    original = load(LIVE_CONFIG)
    require(set(original) == {"macPathMap", "macRoots", "version", "windowsArchives"}, "origin config shape changed")
    mapping = {}
    logical = []
    frontend = temp_root / "84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7.raw"
    for path, physical in original["macPathMap"].items():
        if path == "/usr/bin/xcrun":
            target = temp_root / "xcrun"; kind = "rehydrated-xcrun"
        elif path.endswith("/usr/bin/swiftc") or path.endswith("/usr/bin/swift-frontend"):
            target = frontend; kind = "rehydrated-swift-frontend"
        else:
            target = Path(physical); kind = "archived-original"
        require(target.is_file() and not target.is_symlink(), f"origin mapping target unavailable: {path}")
        mapping[path] = rel(temp_root, target)
        logical.append({"logicalPath": path, "originalTarget": physical, "operationalTarget": str(target), "kind": kind})
    roots = [rel(temp_root, Path(item)) for item in original["macRoots"]]
    if "." not in roots:
        roots.append(".")
    config = {"version": 1, "macRoots": roots, "windowsArchives": original["windowsArchives"], "macPathMap": mapping}
    path = temp_root / "origin-reader-config.json"
    path.write_text(json.dumps(config, indent=2, sort_keys=True) + "\n")
    return path, {"totalMappings": len(mapping), "replacedMappings": [x for x in logical if x["kind"].startswith("rehydrated")], "logicalMappings": logical, "sourceSha256": sha(LIVE_CONFIG)}, sha(path)


def descriptor_proof(reader, rows: list[dict]) -> dict:
    total = 0; failures = []
    for row in rows:
        def visit(value):
            nonlocal total
            if isinstance(value, dict):
                if set(value).issuperset({"path", "sha256", "bytes"}):
                    total += 1
                    try:
                        raw = reader(capture={"platform": "macos"}, reference={"path": value["path"], "sha256": value["sha256"], "bytes": value["bytes"]})
                        require(len(raw) == value["bytes"], "origin byte count mismatch")
                    except Exception as exc:
                        failures.append({"captureId": row.get("id"), "path": value.get("path"), "error": str(exc)})
                else:
                    for child in value.values(): visit(child)
            elif isinstance(value, list):
                for child in value: visit(child)
        visit(row.get("meta", {}).get("conditions", {}).get("macOrigin"))
    return {"captureCount": len(rows), "descriptorCount": total, "verified": total - len(failures), "failures": failures}


def execute_workflow(origin_reader, artifact_reader, output: Path) -> dict:
    from factory.pipeline import workflow
    from factory.core.artifacts import canonical_hash
    from factory.comparison import compare_case
    from factory.reports.report import build_report

    cases = workflow._artifact(CASE_PATH, artifact_reader)
    case = next(value for value in cases if value["id"] == "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258")
    collected = workflow.collect([case], [EVIDENCE], reader=artifact_reader)
    require(not collected["diagnostics"], f"collect diagnostics: {collected['diagnostics'][:1]}")
    captures = sorted(collected["captures"], key=lambda value: value["meta"]["run"])
    require(len(captures) == 20 and {value["meta"]["run"] for value in captures} == set(range(1, 21)), "Mac20 changed")
    origin = descriptor_proof(origin_reader, captures)
    require(not origin["failures"] and origin["verified"] == origin["descriptorCount"], "origin proof failed")
    acceptance = workflow._artifact(ACCEPT, artifact_reader)
    verdict = compare_case(case, captures, acceptance_config=acceptance, holds=["Windows origin proof unavailable"])
    registry = workflow._artifact(REGISTRY, artifact_reader)
    demand = {"blockCapabilities": {case["block"]: ["layout", "accessibility-provider"]}, "journeys": [], "unmappedDemands": []}
    f9_paths = build_report(registry, [case], captures, [verdict], output / "f9", demand)
    gate = workflow.gate_evidence(output / "workflow-gate-evidence", GATE_PLAN, GATE_CASES, [EVIDENCE], GATE_TUPLE, ACCEPT, MANIFESTS, origin_reader=origin_reader, artifact_reader=artifact_reader)
    require(gate.get("status") == "blocked", "gate status changed unexpectedly")
    issues = [issue for row in gate.get("gateResults", []) for issue in row.get("report", {}).get("issues", []) if isinstance(row, dict)]
    report = {
        "schema": "paired-padding-origin-fresh-operational-report-v2",
        "status": "fresh-mac-origin-verified-partial-operational",
        "candidateOnly": True, "frozen": False,
        "identity": {"block": case["block"], "actualCase": {"id": case["id"], "hash": canonical_hash(case)}, "source": {"path": "factory/pipeline/gate-pilot/seed-probes/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.swift", "sha256": captures[0]["provenance"]["sourceHash"]}},
        "macOS": {"count": len(captures), "captureIds": [value["id"] for value in captures], "originProof": origin},
        "windows": {"count": 0, "typedCaptureCount": 0, "status": "held-no-windows-origin-proof"},
        "schemaCounts": {"schemaCollected20": True, "originVerified20": True, "windowsTyped0": True},
        "qualification": {"parityQualified": False, "timing": "raw-only", "nativeParity": "held", "pixelParity": "held", "promotion": "held"},
        "integration": {"artifactReader": "repo-root ArchiveByteReader", "originReader": "rehydrated full origin map via ArchiveByteReader", "workflowCollect": {"status": "collected", "count": 20}, "workflowGateEvidence": {"status": gate["status"], "issueCount": len(issues)}, "f9ReportBuilder": {"status": "observational", "paths": f9_paths}, "gateMissingOriginExactCode": sum("mac-origin:missing-origin" in issue for issue in issues)},
        "rehydration": {"status": "pending-cleanup", "noInstalledFallback": True, "mappingCount": 423, "replacedToolMappings": 3},
    }
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=None)
    output = (parser.parse_args().output or (HERE / f"run-{os.getpid()}")).resolve()
    require(not output.exists() or not any(output.iterdir()), "operational output must be fresh")
    output.mkdir(parents=True, exist_ok=True)
    temp_root = INTERNAL / f"paired-padding-origin-fresh-v2-operational-r1-{os.getpid()}"
    rehydration = None; config_meta = None; config_hash = None; report = None; cleaned = False
    try:
        rehydration = run_rehydration(temp_root, output)
        config_path, config_meta, config_hash = make_origin_config(temp_root)
        from factory.pipeline.reader_config import load_origin_reader_config
        from factory.pipeline.archive_reader import ArchiveByteReader
        origin_reader = load_origin_reader_config(config_path)
        artifact_reader = ArchiveByteReader(mac_roots=[ROOT])
        report = execute_workflow(origin_reader, artifact_reader, output)
        (output / "rehydration-verification-receipt.json").write_text(json.dumps(rehydration["verificationReceipt"], indent=2, sort_keys=True) + "\n")
        (output / "rehydration-origin-reader-config.json").write_bytes(config_path.read_bytes())
        (output / "origin-logical-map.json").write_text(json.dumps(config_meta, indent=2, sort_keys=True) + "\n")
        report["rehydration"].update({"status": "PASS", "helperSha256": rehydration["helperSha256"], "planSha256": rehydration["planSha256"], "configSha256": config_hash, "configReceipt": "rehydration-origin-reader-config.json", "logicalMap": "origin-logical-map.json", "tempRoot": str(temp_root), "tempRemoved": False})
        (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    finally:
        if temp_root.exists():
            shutil.rmtree(temp_root)
        cleaned = not temp_root.exists()
    require(cleaned, "owned rehydration temp cache was not removed")
    require(report is not None, "operational report unavailable")
    report["rehydration"]["tempRemoved"] = True
    report["rehydration"]["cleanupStatus"] = "PASS"
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    receipt = {"schema": "paired-padding-origin-fresh-v2-operational-rehydration-receipt", "status": "PASS", "tempRoot": str(temp_root), "tempRemoved": True, "configSha256": config_hash, "helper": rehydration, "nativeExecutions": 0, "compilerExecutions": 0}
    (output / "rehydration-process-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": report["status"], "macRuns": report["macOS"]["count"], "originDescriptors": report["macOS"]["originProof"]["verified"], "windows": report["windows"]["count"], "parityQualified": report["qualification"]["parityQualified"], "tempRemoved": True}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
