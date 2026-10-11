#!/usr/bin/env python3
"""Run bounded Mac20/Windows20 observation comparison through production readers."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import re
import sys
from pathlib import Path

MAX_JSON = 8 * 1024 * 1024
MAX_ARCHIVE_BYTES = 64 * 1024 * 1024
SHA = re.compile(r"^sha256:[0-9a-f]{64}$")


class Hold(ValueError):
    pass


def bounded_json(path: Path, label: str) -> dict:
    if path.is_symlink() or not path.is_file():
        raise Hold(f"{label} missing or symlink")
    if path.stat().st_size > MAX_JSON:
        raise Hold(f"{label} exceeds bounded JSON read")
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise Hold(f"{label} duplicate JSON key")
            result[key] = value
        return result
    try:
        value = json.loads(path.read_bytes().decode("utf-8-sig"), object_pairs_hook=pairs)
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise Hold(f"{label} invalid JSON") from exc
    if not isinstance(value, dict):
        raise Hold(f"{label} JSON object required")
    return value


def load_capture(raw: bytes, label: str) -> dict:
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise Hold(f"{label} duplicate JSON key")
            result[key] = value
        return result
    try:
        value = json.loads(raw.decode("utf-8-sig"), object_pairs_hook=pairs)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise Hold(f"{label} capture JSON invalid") from exc
    if not isinstance(value, dict):
        raise Hold(f"{label} capture object required")
    return value


def validate_pair_inputs(case: dict, normalized: dict, proof: dict, reader_report: dict,
                         mac_report: dict, source_plan: dict) -> dict:
    from factory.core.artifacts import canonical_hash

    if case.get("kind") != "case" or case.get("version") != "0.1":
        raise Hold("v0.1 case required")
    case_ref = {"id": case.get("id"), "hash": canonical_hash(case)}
    captures = normalized.get("captures")
    proofs = proof.get("captures")
    if normalized.get("typedStatus") != "normalized-observational" or normalized.get("qualified") is not False:
        raise Hold("normalized observational input required")
    if normalized.get("kind") != "factory-native-count20-r17-normalized-inputs-v12" or not isinstance(captures, list) or len(captures) != 20:
        raise Hold("normalized Windows20 input required")
    if proof.get("status") != "proofs-attached" or proof.get("count") != 20 or not isinstance(proofs, list) or len(proofs) != 20:
        raise Hold("adapter proof Count20 input required")
    for index, (capture, attached) in enumerate(zip(captures, proofs), 1):
        if not isinstance(capture, dict) or not isinstance(attached, dict) or capture.get("platform") != "windows" or capture.get("case") != case_ref or attached.get("platform") != "windows" or attached.get("case") != case_ref:
            raise Hold(f"run {index} Windows/case join missing")
        if capture.get("id") != attached.get("id") or (capture.get("images") or [{}])[0].get("id") != (attached.get("images") or [{}])[0].get("id"):
            raise Hold(f"run {index} adapter proof pair mismatch")
        proof_fields = attached.get("meta", {}).get("conditions", {}).get("windowsExitProof")
        if not isinstance(proof_fields, dict) or set(proof_fields.get("files", {})) != {"outcome", "observation", "owned", "close", "plan", "compile", "witness", "exe", "renderer", "runtimeReceipt", "runtimeTree", "stdout", "stderr"}:
            raise Hold(f"run {index} Windows proof roles missing")
        conditions = attached.get("meta", {}).get("conditions", {})
        role_files = proof_fields["files"]
        expected_source = capture.get("provenance", {}).get("sourceHash")
        expected_host = capture.get("meta", {}).get("host", {}).get("hash")
        expected_renderer = capture.get("tuple", {}).get("rendererHash")
        expected_receipt = role_files["observation"].get("hash")
        if conditions.get("actualSourceHash") != expected_source or conditions.get("actualSourceHash") != role_files["witness"].get("hash"):
            raise Hold(f"run {index} attached source identity mismatch")
        if conditions.get("actualHostExecutableHash") != expected_host or conditions.get("actualHostExecutableHash") != role_files["exe"].get("hash"):
            raise Hold(f"run {index} attached executable identity mismatch")
        if conditions.get("actualRendererHash") != expected_renderer or conditions.get("actualRendererHash") != role_files["renderer"].get("hash"):
            raise Hold(f"run {index} attached renderer identity mismatch")
        if conditions.get("rawReceiptHash") != expected_receipt:
            raise Hold(f"run {index} attached raw receipt identity mismatch")
        base_attached = copy.deepcopy(attached)
        base_conditions = base_attached.get("meta", {}).get("conditions", {})
        for added in ("actualHostExecutableHash", "actualRendererHash", "actualSourceHash", "rawReceiptHash", "windowsExitProof"):
            base_conditions.pop(added, None)
        # r3 normalized clock correlation predates attached raw-observation sealing;
        # accept only attached observation hash, then restore normalized base field.
        base_attached.get("meta", {}).get("clock", {})["correlationHash"] = capture.get("meta", {}).get("clock", {}).get("correlationHash")
        if base_attached != capture:
            raise Hold(f"run {index} normalized/attached capture drift")
    reader_status = reader_report.get("status")
    reader_rows = reader_report.get("rows")
    if reader_status not in {"reader-verified", "reader-observed-rejections"} or reader_report.get("count") != 20 or not isinstance(reader_rows, list) or len(reader_rows) != 20:
        raise Hold("trusted Windows reader observation Count20 required")
    if any(not isinstance(row, dict) or row.get("status") not in {"pass", "blocked"} for row in reader_rows):
        raise Hold("reader row status invalid")
    if reader_status == "reader-verified" and not all(row.get("status") == "pass" for row in reader_rows):
        raise Hold("reader-verified report contains blocked rows")
    if reader_status == "reader-observed-rejections" and not any(row.get("status") == "blocked" for row in reader_rows):
        raise Hold("reader-observed-rejections report lacks blocked rows")
    mac_rows = mac_report.get("macCaptures")
    if mac_report.get("kind") != "verdict" or mac_report.get("version") != "0.1" or mac_report.get("status") in {"qualified", "parity-passed", "golden-frozen", "pass"} or not isinstance(mac_rows, list) or len(mac_rows) != 20 or mac_report.get("case") != case_ref or mac_report.get("tuple") != case.get("tuple"):
        raise Hold("observed Mac20 comparator input required")
    provenance = mac_report.get("provenance")
    if not isinstance(provenance, dict) or provenance.get("producer") != "factory/comparison" or not isinstance(provenance.get("sourceHash"), str) or not SHA.fullmatch(provenance["sourceHash"]):
        raise Hold("Mac comparator provenance missing")
    if mac_report.get("windowsCaptures") not in ([], None):
        raise Hold("Mac comparator must not contain Windows captures")
    if any(not isinstance(row, dict) or not isinstance(row.get("id"), str) or not SHA.fullmatch(str(row.get("hash"))) for row in mac_rows):
        raise Hold("Mac comparator capture refs malformed")
    if not isinstance(source_plan.get("case"), dict):
        raise Hold("immutable source plan case missing")
    protected = []
    if source_plan["case"] != case_ref:
        protected.append("protected windows_exit_admission requires capture.case==plan.case; source plan retains legacy case while fresh capture uses adapter case")
    if protected and reader_status == "reader-verified":
        raise Hold("reader pass cannot accompany protected case mismatch")
    return {"caseRef": case_ref, "protectedIssues": protected, "captureCount": 20, "macCount": 20, "readerStatus": reader_status}


def load_mac_captures(mac_root: Path, mac_report: dict, case: dict, reader,
                      raw_manifest: dict) -> list[dict]:
    from factory.core.artifacts import canonical_hash

    entries = raw_manifest.get("files")
    if raw_manifest.get("kind") != "root-macos-factory-whole-archive-v1" or not isinstance(entries, list):
        raise Hold("Mac raw archive manifest required")
    manifest_files = {}
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            raise Hold("Mac raw archive manifest entry malformed")
        digest = entry.get("sha256")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise Hold("Mac raw archive manifest hash malformed")
        if type(entry.get("bytes")) is not int or entry["bytes"] < 0:
            raise Hold("Mac raw archive manifest byte count malformed")
        if entry["path"] in manifest_files:
            raise Hold("Mac raw archive manifest duplicate path")
        manifest_files[entry["path"]] = entry
    rows = mac_report["macCaptures"]
    captures = []
    for index, row in enumerate(rows, 1):
        if not isinstance(row, dict) or not isinstance(row.get("id"), str) or not SHA.fullmatch(str(row.get("hash"))):
            raise Hold(f"Mac run {index} comparator reference malformed")
        capture_path = mac_root / "evidence" / case["id"] / f"run-{index:03d}" / "capture.json"
        if capture_path.is_symlink() or not capture_path.is_file():
            raise Hold(f"Mac run {index} capture missing")
        try:
            relative = capture_path.relative_to(mac_root).as_posix()
        except ValueError as exc:
            raise Hold(f"Mac run {index} capture escapes archive root") from exc
        entry = manifest_files.get(relative)
        if entry is None:
            raise Hold(f"Mac run {index} raw manifest entry missing")
        raw = reader(capture={"platform": "macos"}, reference={
            "path": str(capture_path.resolve()),
            "sha256": "sha256:" + entry["sha256"],
            "bytes": entry["bytes"],
        })
        capture = load_capture(raw, f"Mac run {index}")
        if capture.get("id") != row["id"] or capture.get("platform") != "macos" or capture.get("meta", {}).get("run") != index:
            raise Hold(f"Mac run {index} capture identity mismatch")
        if canonical_hash(capture) != row["hash"]:
            raise Hold(f"Mac run {index} semantic hash differs from comparator reference")
        captures.append(capture)
    return captures


def run_pair(repo: Path, mac_root: Path, reader_archive: Path, case: dict, normalized: dict,
             proof: dict, reader_report: dict, mac_report: dict, source_plan: dict,
             raw_manifest: dict, acceptance: dict | None) -> dict:
    from factory.comparison import ComparisonError, compare_case
    from factory.core.artifacts import canonical_hash
    from factory.gate.windows_exit_admission import verify_windows_exit_admission
    from factory.pipeline.archive_reader import ArchiveByteReader

    meta = validate_pair_inputs(case, normalized, proof, reader_report, mac_report, source_plan)
    captures = proof["captures"]
    maps = {}
    for index, capture in enumerate(captures, 1):
        key = canonical_hash(capture).removeprefix("sha256:")
        archive = reader_archive / ("capture-" + key)
        if archive.is_symlink() or not archive.is_dir():
            raise Hold(f"run {index} trusted reader archive missing")
        maps[key] = archive
    reader = ArchiveByteReader(mac_roots=[mac_root], windows_archives=maps, max_bytes=MAX_ARCHIVE_BYTES)
    mac = load_mac_captures(mac_root, mac_report, case, reader, raw_manifest)
    reader_rows = []
    for capture in captures:
        result = verify_windows_exit_admission(capture, read_bytes=lambda path, c=capture: reader(capture=c, reference=path))
        reader_rows.append(result)
    expected_rows = reader_report["rows"]
    for index, (actual, expected) in enumerate(zip(reader_rows, expected_rows), 1):
        if actual.get("status") != expected.get("status"):
            raise Hold(f"run {index} reader status differs from recorded observation")
    try:
        verdict = compare_case(case, mac + captures, acceptance_config=acceptance or {}, holds=["parity/golden/freeze held", *meta["protectedIssues"]])
        comparison = {"status": "compared", "verdict": verdict}
    except (ComparisonError, ValueError, KeyError, TypeError) as exc:
        comparison = {"status": "blocked", "error": str(exc)}
    status = ("blocked-by-protected-production-gate" if meta["protectedIssues"] else
              "reader-observed-rejections" if meta["readerStatus"] != "reader-verified" else
              "paired-comparison-observed")
    return {
        "schema": "factory-native-count20-paired-comparison-v1",
        "status": status,
        "candidateOnly": True,
        "count": 20,
        "reader": {"implementation": "factory.pipeline.archive_reader.ArchiveByteReader", "status": meta["readerStatus"], "macCount": len(mac), "windowsCount": len(reader_rows), "windowsRows": reader_rows},
        "comparison": comparison,
        "protectedGate": {"status": "blocked" if meta["protectedIssues"] else "not-run", "issues": meta["protectedIssues"]},
        "comparisonEligible": bool(not meta["protectedIssues"] and meta["readerStatus"] == "reader-verified" and comparison.get("status") == "compared"),
        "parity": {"status": "held", "goldens": 0, "promotion": "held"},
        "effects": {"nativeActions": 0, "compilerActions": 0, "remoteActions": 0, "lockActions": 0, "sourceMutations": 0},
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    for name in ("repo", "mac-root", "reader-archive", "case", "normalized", "adapter-proof", "reader-report", "mac-report", "source-plan", "output"):
        ap.add_argument("--" + name, required=True, type=Path)
    ap.add_argument("--mac-manifest", type=Path)
    ap.add_argument("--acceptance-config", type=Path)
    args = ap.parse_args()
    if args.output.exists() or args.output.is_symlink():
        raise SystemExit("HOLD: output must be fresh")
    try:
        repo = args.repo.resolve()
        case = bounded_json(args.case, "case")
        normalized = bounded_json(args.normalized, "normalized")
        proof = bounded_json(args.adapter_proof, "adapter proof")
        reader_report = bounded_json(args.reader_report, "reader report")
        mac_report = bounded_json(args.mac_report, "Mac comparator")
        source_plan = bounded_json(args.source_plan, "source plan")
        manifest_path = args.mac_manifest or (args.mac_root / "raw-archive-manifest.json")
        raw_manifest = bounded_json(manifest_path, "Mac raw archive manifest")
        acceptance = bounded_json(args.acceptance_config, "acceptance config") if args.acceptance_config else {}
        report = run_pair(repo, args.mac_root.resolve(), args.reader_archive.resolve(), case, normalized, proof, reader_report, mac_report, source_plan, raw_manifest, acceptance)
    except Exception as exc:
        raise SystemExit("HOLD: " + str(exc)) from exc
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "count": report["count"], "comparison": report["comparison"]["status"], "nativeActions": 0, "lockActions": 0}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
