"""Operational v3 report with independent frozen-input guard."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import os
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
PINS = ROOT / "factory/pipeline/paired-padding-origin-fresh-v1/source-pins.json"
SOURCE_PINS_SHA256 = "sha256:d2e7de287486da665f104120d9067395a6436aab2f14d39187b113fcdfb22aad"
LIVE_CONFIG = ROOT / "factory/oracle/mac/padding-origin-fresh-v1/actual/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258/origin-reader-config.json"
V2_PLAN = ROOT / "factory/oracle/mac/padding-origin-fresh-v1/cleanup-rehydration-v2/rehydration-plan.json"
V2_HELPER = ROOT / "factory/oracle/mac/padding-origin-fresh-v1/cleanup-rehydration-v2/rehydrate.py"
V2_PLAN_SHA256 = "sha256:1d5334affee4c5214a25177d3865d643536ae9d28462a03add8c6068f865311a"
V2_MODULE = ROOT / "factory/pipeline/paired-padding-origin-fresh-v2-operational-v1/report.py"
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


def frozen_source_guard(path: Path = PINS) -> dict:
    """Bind source pin manifest & every fresh run before workflow collection."""
    require(sha(path) == SOURCE_PINS_SHA256, "frozen source-pin manifest hash differs")
    pins = load(path)
    require(pins.get("schema") == "paired-padding-origin-fresh-source-pins-v1", "source pin schema differs")
    fixed = {
        "captureIndex": ROOT / "factory/oracle/mac/padding-origin-fresh-v1/actual/capture-index.json",
        "verification": ROOT / "factory/oracle/mac/padding-origin-fresh-v1/actual/verification.json",
        "rootRunPlan": ROOT / "factory/oracle/mac/padding-origin-fresh-v1/root-run-plan.json",
        "rootProcess": ROOT / "factory/oracle/mac/padding-origin-fresh-v1/root-process.json",
        "rootOwnedProcess": ROOT / "factory/oracle/mac/padding-origin-fresh-v1/root-owned-process.json",
        "originReaderConfig": LIVE_CONFIG,
        "originArchiveManifest": LIVE_CONFIG.parent / "origin-archive-manifest.json",
        "summary": LIVE_CONFIG.parent / "summary.json",
        "originSummary": LIVE_CONFIG.parent / "origin-summary.json",
    }
    checks = []
    for key, target in fixed.items():
        actual = sha(target); require(actual == pins["files"][key], f"frozen source changed: {key}")
        checks.append({"label": key, "sha256": actual})
    for run, values in pins["runs"].items():
        for name, relative in {
            "capture.json": f"run-{int(run):03d}/capture.json",
            "clock.json": f"run-{int(run):03d}/clock.json",
            "external-ax.raw.json": f"run-{int(run):03d}/external-ax.raw.json",
        }.items():
            target = LIVE_CONFIG.parent / relative; actual = sha(target)
            require(actual == values[name], f"frozen run changed: {run}/{name}")
            checks.append({"label": f"run-{run}/{name}", "sha256": actual})
    return {"status": "PASS", "manifestSha256": SOURCE_PINS_SHA256, "count": len(checks), "checks": checks}


def load_v2_module():
    spec = importlib.util.spec_from_file_location("paired_padding_v2_operational", V2_MODULE)
    require(spec is not None and spec.loader is not None, "v2 operational source unavailable")
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module


def controls(base, temp_root: Path, source_guard: dict) -> dict:
    result = {}
    with tempfile.TemporaryDirectory(prefix="paired-padding-v3-source-control-") as directory:
        altered = Path(directory) / "source-pins.json"
        value = load(PINS); value["schema"] = "tampered"
        altered.write_text(json.dumps(value))
        try: frozen_source_guard(altered)
        except Exception: result["source-pin-manifest-fault"] = "rejected"
        else: result["source-pin-manifest-fault"] = "accepted-BUG"
    with tempfile.TemporaryDirectory(prefix="paired-padding-v3-run-control-") as directory:
        altered = Path(directory) / "source-pins.json"
        value = load(PINS); value["runs"]["001"]["capture.json"] = "sha256:" + "0" * 64
        altered.write_text(json.dumps(value))
        try: frozen_source_guard(altered)
        except Exception: result["frozen-run-fault"] = "rejected"
        else: result["frozen-run-fault"] = "accepted-BUG"
    with tempfile.TemporaryDirectory(prefix="paired-padding-v3-tool-control-") as directory:
        wrong = Path(directory) / "xcrun"; wrong.write_bytes((temp_root / "xcrun").read_bytes() + b"wrong-byte"); wrong.chmod(0o644)
        from factory.pipeline.archive_reader import ArchiveByteReader
        reader = ArchiveByteReader(mac_roots=[Path(directory)], mac_path_map={"/usr/bin/xcrun": wrong})
        try:
            reader(capture={"platform": "macos"}, reference={"path": "/usr/bin/xcrun", "sha256": "sha256:bbe7671518a3905f9d3fce54312fbc77c2876b0d62aca74a0688fa869d31a8a9"})
        except Exception: result["tool-cache-wrong-byte-fault"] = "rejected"
        else: result["tool-cache-wrong-byte-fault"] = "accepted-BUG"
    require(all(value == "rejected" for value in result.values()), "frozen-input control accepted mutation")
    return result


def main() -> int:
    import argparse
    parser = argparse.ArgumentParser(); parser.add_argument("--output", type=Path, default=None)
    output = (parser.parse_args().output or (HERE / f"run-{os.getpid()}")).resolve()
    require(not output.exists() or not any(output.iterdir()), "v3 output must be fresh")
    output.mkdir(parents=True, exist_ok=True)
    base = load_v2_module()
    source_guard = frozen_source_guard()
    plan = load(V2_PLAN)
    require(sha(V2_PLAN) == V2_PLAN_SHA256 and sha(V2_HELPER) == plan["helper"]["sha256"], "v2 source pins changed")
    temp_root = INTERNAL / f"paired-padding-origin-fresh-v3-operational-r1-{os.getpid()}"
    report = None; rehydration = None; config_meta = None; config_hash = None
    try:
        rehydration = base.run_rehydration(temp_root, output)
        config_path, config_meta, config_hash = base.make_origin_config(temp_root)
        from factory.pipeline.reader_config import load_origin_reader_config
        from factory.pipeline.archive_reader import ArchiveByteReader
        origin_reader = load_origin_reader_config(config_path)
        artifact_reader = ArchiveByteReader(mac_roots=[ROOT])
        report = base.execute_workflow(origin_reader, artifact_reader, output)
        report["schema"] = "paired-padding-origin-fresh-operational-report-v3"
        report["frozenInputGuard"] = source_guard
        report["controls"] = controls(base, temp_root, source_guard)
        report["rehydration"].update({"status": "PASS", "helperSha256": rehydration["helperSha256"], "planSha256": rehydration["planSha256"], "configSha256": config_hash, "configReceipt": "rehydration-origin-reader-config.json", "logicalMap": "origin-logical-map.json", "tempRoot": str(temp_root), "tempRemoved": False})
        (output / "rehydration-verification-receipt.json").write_text(json.dumps(rehydration["verificationReceipt"], indent=2, sort_keys=True) + "\n")
        (output / "rehydration-origin-reader-config.json").write_bytes(config_path.read_bytes())
        (output / "origin-logical-map.json").write_text(json.dumps(config_meta, indent=2, sort_keys=True) + "\n")
    finally:
        if temp_root.exists(): shutil.rmtree(temp_root)
    require(report is not None and not temp_root.exists(), "v3 operational temp cleanup failed")
    report["rehydration"]["tempRemoved"] = True; report["rehydration"]["cleanupStatus"] = "PASS"
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    receipt = {"schema": "paired-padding-origin-fresh-v3-rehydration-receipt", "status": "PASS", "tempRoot": str(temp_root), "tempRemoved": True, "configSha256": config_hash, "helper": rehydration, "nativeExecutions": 0, "compilerExecutions": 0}
    (output / "rehydration-process-receipt.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status": report["status"], "frozenSourcePins": source_guard["count"], "macRuns": report["macOS"]["count"], "originDescriptors": report["macOS"]["originProof"]["verified"], "windows": report["windows"]["count"], "parityQualified": report["qualification"]["parityQualified"], "tempRemoved": True}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
