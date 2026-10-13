"""Offline independent review of cleanup-rehydration-v2 & fresh Mac consumers."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import stat
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[6]
HERE = Path(__file__).resolve().parent
V2 = HERE.parent
FRESH = ROOT / "factory/oracle/mac/padding-origin-fresh-v1/actual"
EVIDENCE = FRESH / "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258"
PINS = ROOT / "factory/pipeline/paired-padding-origin-fresh-v1/source-pins.json"
LIVE_ORIGIN_CONFIG = EVIDENCE / "origin-reader-config.json"
V2_CACHE = Path("/Users/adrdsouza/Library/Caches/SwiftRightFactory/padding-origin-fresh-v1/cleanup-rehydration-v2-actual")
REVIEW_CACHE = Path("/Users/adrdsouza/Library/Caches/SwiftRightFactory/padding-origin-fresh-v1/cleanup-rehydration-v2-review-r1")
CASE_PATH = ROOT / "factory/pipeline/gate-pilot/seed-cases.json"
CFG = ROOT / "factory/pipeline/paired-padding-settled-v2/source-config.json"
ACCEPT = ROOT / "factory/pipeline/inputs/acceptance-candidate.json"
GATE_PLAN = ROOT / "factory/pipeline/gate-pilot/gate-results.json"
GATE_CASES = ROOT / "factory/pipeline/inputs/cases.json"
GATE_TUPLE = ROOT / "factory/pipeline/inputs/observed-tuple.json"
MANIFESTS = ROOT / "factory/pipeline/manifests"


def digest(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def sha(path: Path) -> str:
    return digest(path.read_bytes())


def load(path: Path):
    return json.loads(path.read_bytes().decode("utf-8"))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def source_pin_review() -> dict:
    pins = load(PINS)
    require(pins.get("schema") == "paired-padding-origin-fresh-source-pins-v1", "source pin schema changed")
    checks = []
    for key, relative in {
        "captureIndex": "capture-index.json",
        "verification": "verification.json",
    }.items():
        path = FRESH / relative
        checks.append((key, path, pins["files"][key]))
    for key, relative in {
        "rootRunPlan": "root-run-plan.json",
        "rootProcess": "root-process.json",
        "rootOwnedProcess": "root-owned-process.json",
    }.items():
        path = ROOT / "factory/oracle/mac/padding-origin-fresh-v1" / relative
        checks.append((key, path, pins["files"][key]))
    for key, relative in {
        "originReaderConfig": "origin-reader-config.json",
        "originArchiveManifest": "origin-archive-manifest.json",
        "summary": "summary.json",
        "originSummary": "origin-summary.json",
    }.items():
        path = EVIDENCE / relative
        checks.append((key, path, pins["files"][key]))
    for run, values in pins["runs"].items():
        for key, relative in {
            "capture.json": f"run-{int(run):03d}/capture.json",
            "clock.json": f"run-{int(run):03d}/clock.json",
            "external-ax.raw.json": f"run-{int(run):03d}/external-ax.raw.json",
        }.items():
            checks.append((f"run-{run}-{key}", EVIDENCE / relative, values[key]))
    results = []
    for label, path, expected in checks:
        actual = sha(path)
        require(actual == expected, f"source pin changed: {label}")
        results.append({"label": label, "path": str(path), "sha256": actual, "status": "PASS"})
    return {"status": "PASS", "count": len(results), "sourcePins": sha(PINS), "checks": results}


def helper_review() -> dict:
    plan = load(V2 / "rehydration-plan.json")
    receipt_path = V2 / "actual-replay-receipt.json"
    receipt = load(receipt_path)
    helper_path = V2 / "rehydrate.py"
    require(sha(helper_path) == plan["helper"]["sha256"], "v2 helper hash differs from plan")
    require(sha(V2 / "test_rehydrate.py") == plan["helper"]["controlsSha256"], "v2 control hash differs from plan")
    require(sha(receipt_path) == plan["actualReplay"]["processReceiptSha256"], "v2 receipt hash differs from plan")
    require(receipt.get("status") == "PASS" and receipt.get("exitCode") == 0, "v2 replay not successful")
    require(receipt.get("currentToolReadsDuringReplay") == 0, "v2 replay read current tools")
    require(receipt.get("nativeExecutions") == 0 and receipt.get("compilerExecutions") == 0, "v2 replay executed native/compiler")
    require(receipt.get("helperReceipt", {}).get("archiveManifestVersion") == "1", "manifest protocol drift")
    files = []
    for name, expected in plan["actualReplay"]["outputFiles"].items():
        path = V2_CACHE / name
        require(path.is_file() and not path.is_symlink(), f"v2 output missing: {name}")
        require(stat.S_IMODE(path.stat().st_mode) == 0o644, f"v2 output mode changed: {name}")
        require(len(path.read_bytes()) == expected["bytes"], f"v2 output size changed: {name}")
        require(sha(path) == expected["sha256"], f"v2 output hash changed: {name}")
        files.append({"name": name, "bytes": expected["bytes"], "sha256": expected["sha256"], "mode": "0644"})
    test = subprocess.run(
        [sys.executable, "-m", "unittest", "factory/oracle/mac/padding-origin-fresh-v1/cleanup-rehydration-v2/test_rehydrate.py"],
        cwd=ROOT, text=True, capture_output=True, check=False,
    )
    require(test.returncode == 0, "v2 controls failed on independent replay")
    return {
        "status": "PASS",
        "helperSha256": sha(helper_path),
        "receiptSha256": sha(receipt_path),
        "controls": {"declared": plan["helper"]["controlsPassed"], "independentExitCode": test.returncode},
        "outputCache": str(V2_CACHE), "outputFiles": files,
        "currentToolReads": receipt["currentToolReadsDuringReplay"],
        "nativeExecutions": receipt["nativeExecutions"], "compilerExecutions": receipt["compilerExecutions"],
    }


def relative_path(base: Path, target: Path) -> str:
    value = os.path.relpath(target.resolve(), base.resolve())
    require("\\" not in value and "\x00" not in value and not Path(value).is_absolute(), "unsafe generated config path")
    return value


def make_repoint_config() -> tuple[Path, str, dict]:
    original = load(LIVE_ORIGIN_CONFIG)
    require(set(original) == {"macPathMap", "macRoots", "version", "windowsArchives"}, "live config shape changed")
    REVIEW_CACHE.mkdir(parents=True, exist_ok=True)
    config_path = REVIEW_CACHE / "origin-reader-config-repoint-v1.json"
    mapping = {}
    replaced = []
    for logical, physical in original["macPathMap"].items():
        if logical == "/usr/bin/xcrun":
            target = V2_CACHE / "xcrun"
            replaced.append(logical)
        elif logical.endswith("/usr/bin/swiftc") or logical.endswith("/usr/bin/swift-frontend"):
            target = V2_CACHE / "84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7.raw"
            replaced.append(logical)
        else:
            target = Path(physical)
        require(target.is_file() and not target.is_symlink(), f"mapping target missing: {logical}")
        mapping[logical] = relative_path(config_path.parent, target)
    roots = [relative_path(config_path.parent, Path(root)) for root in original["macRoots"]]
    cache_root = relative_path(config_path.parent, V2_CACHE)
    if cache_root not in roots:
        roots.append(cache_root)
    config = {"version": 1, "macRoots": roots, "windowsArchives": original["windowsArchives"], "macPathMap": mapping}
    raw = (json.dumps(config, indent=2, sort_keys=True) + "\n").encode()
    config_path.write_bytes(raw)
    return config_path, digest(raw), {"totalMappings": len(mapping), "replacedMappings": sorted(replaced), "originalSha256": sha(LIVE_ORIGIN_CONFIG)}


def reader_mapping_review(config_path: Path, expected_hash: str) -> dict:
    from factory.pipeline.reader_config import load_origin_reader_config
    reader = load_origin_reader_config(config_path)
    references = {
        "/usr/bin/xcrun": (V2_CACHE / "xcrun", digest((V2_CACHE / "xcrun").read_bytes())),
        "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc": (V2_CACHE / "84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7.raw", "sha256:84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7"),
        "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend": (V2_CACHE / "84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7.raw", "sha256:84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7"),
    }
    checks = []
    for logical, (target, expected) in references.items():
        raw = reader(capture={"platform": "macos"}, reference={"path": logical, "sha256": expected, "bytes": target.stat().st_size})
        require(digest(raw) == expected and len(raw) == target.stat().st_size, f"repoint reader mismatch: {logical}")
        checks.append({"logicalPath": logical, "target": str(target), "bytes": len(raw), "sha256": digest(raw), "status": "PASS"})
    return {"status": "PASS", "configSha256": expected_hash, "checks": checks}


def origin_descriptors(reader, rows: list[dict]) -> dict:
    checks = 0
    failures = []
    for row in rows:
        def visit(value):
            nonlocal checks
            if isinstance(value, dict):
                if set(value).issuperset({"path", "sha256", "bytes"}):
                    checks += 1
                    try:
                        raw = reader(capture={"platform": "macos"}, reference={"path": value["path"], "sha256": value["sha256"], "bytes": value["bytes"]})
                        require(len(raw) == value["bytes"], "origin byte count mismatch")
                    except Exception as exc:
                        failures.append({"captureId": row.get("id"), "path": value.get("path"), "error": str(exc)})
                else:
                    for child in value.values():
                        visit(child)
            elif isinstance(value, list):
                for child in value:
                    visit(child)
        visit(row.get("meta", {}).get("conditions", {}).get("macOrigin"))
    return {"captureCount": len(rows), "descriptorCount": checks, "verified": checks - len(failures), "failures": failures}


def workflow_review(origin_reader, artifact_reader, output: Path) -> dict:
    from factory.pipeline import workflow
    from factory.core.artifacts import canonical_hash
    cases = workflow._artifact(CASE_PATH, artifact_reader)
    case = next(item for item in cases if item["id"] == "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258")
    collected = workflow.collect([case], [EVIDENCE], reader=artifact_reader)
    require(not collected["diagnostics"], f"fresh collection diagnostics: {collected['diagnostics'][:1]}")
    rows = sorted(collected["captures"], key=lambda item: item["meta"]["run"])
    require(len(rows) == 20 and {item["meta"]["run"] for item in rows} == set(range(1, 21)), "fresh Mac20 denominator changed")
    origins = origin_descriptors(origin_reader, rows)
    require(not origins["failures"] and origins["captureCount"] == 20 and origins["verified"] == origins["descriptorCount"], "fresh origin descriptors did not verify")
    gate_output = output / "workflow-gate-evidence"
    gate = workflow.gate_evidence(gate_output, GATE_PLAN, GATE_CASES, [EVIDENCE], GATE_TUPLE, ACCEPT, MANIFESTS, origin_reader=origin_reader, artifact_reader=artifact_reader)
    require(gate.get("status") == "blocked", "gate status unexpectedly changed")
    return {"collect": {"status": "PASS", "count": len(rows), "captureIds": [item["id"] for item in rows]},
            "origin": origins, "gate": {"status": gate["status"], "output": str(gate_output)}}


def controls(config_path: Path, config_hash: str, original: dict) -> dict:
    from factory.pipeline.reader_config import load_origin_reader_config
    results = {"missing-v2-target": "rejected", "wrong-tool-target": "rejected", "live-config-untouched": "rejected"}
    missing = REVIEW_CACHE / "missing-target-config.json"
    altered = {"version": 1, "macRoots": ["."], "windowsArchives": {}, "macPathMap": {"/usr/bin/xcrun": "missing"}}
    missing.write_text(json.dumps(altered))
    try:
        load_origin_reader_config(missing)
    except Exception:
        pass
    else:
        results["missing-v2-target"] = "accepted-BUG"
    wrong = REVIEW_CACHE / "wrong-tool-target-config.json"
    wrong_value = {"version": 1, "macRoots": [relative_path(wrong.parent, V2_CACHE)], "windowsArchives": {}, "macPathMap": {"/usr/bin/xcrun": relative_path(wrong.parent, V2_CACHE / "xcrun"), "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc": relative_path(wrong.parent, V2_CACHE / "xcrun")}}
    wrong.write_text(json.dumps(wrong_value))
    try:
        reader = load_origin_reader_config(wrong)
        reader(capture={"platform": "macos"}, reference={"path": "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc", "sha256": "sha256:84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7"})
    except Exception:
        pass
    else:
        results["wrong-tool-target"] = "accepted-BUG"
    results["live-config-untouched"] = "PASS" if sha(LIVE_ORIGIN_CONFIG) == original["originalSha256"] else "accepted-BUG"
    require(all(value in {"rejected", "PASS"} for value in results.values()), "mapping control accepted mutation")
    return results


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=HERE / "root-replay-r1")
    args = parser.parse_args()
    output = args.output.resolve()
    require(not output.exists() or not any(output.iterdir()), "review output must be fresh")
    output.mkdir(parents=True, exist_ok=True)
    source = source_pin_review()
    helper = helper_review()
    config_path, config_hash, mapping = make_repoint_config()
    mapping_review = reader_mapping_review(config_path, config_hash)
    from factory.pipeline.archive_reader import ArchiveByteReader
    artifact_reader = ArchiveByteReader(mac_roots=[ROOT, FRESH], mac_path_map={})
    workflow_result = workflow_review(mapping_reader(config_path), artifact_reader, output)
    control_result = controls(config_path, config_hash, mapping)
    report = {
        "schema": "cleanup-rehydration-v2-independent-review-v1",
        "status": "PASS_REHYDRATION_REPOINTED_MAC20_WORKFLOW",
        "candidateOnly": True,
        "sourcePins": source,
        "helper": helper,
        "repoint": {**mapping, "configPath": str(config_path), "configSha256": config_hash, "reader": mapping_review},
        "workflow": workflow_result,
        "controls": control_result,
        "nativeExecutions": 0,
        "compilerExecutions": 0,
        "cleanupBoundary": {"currentActualCache": str(FRESH / "mac-origin-tool-cache"), "v2Cache": str(V2_CACHE), "reviewConfigCache": str(REVIEW_CACHE), "owner": "root", "deletedByThisReview": False},
    }
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    (output / "review-config-reference.json").write_text(json.dumps({"path": str(config_path), "sha256": config_hash, "mapping": mapping}, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": report["status"], "sourcePins": source["count"], "originDescriptors": workflow_result["origin"]["verified"], "collect": workflow_result["collect"]["count"], "gate": workflow_result["gate"]["status"]}, sort_keys=True))
    return 0


def mapping_reader(config_path: Path):
    from factory.pipeline.reader_config import load_origin_reader_config
    return load_origin_reader_config(config_path)


if __name__ == "__main__":
    raise SystemExit(main())
