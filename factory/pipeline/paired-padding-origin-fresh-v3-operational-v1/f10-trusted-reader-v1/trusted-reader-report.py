#!/usr/bin/env python3
"""Read actual Mac20 + typed Windows20 origins through production reader.

This packet records raw reader/admission evidence only. It never grants
semantic parity, timing qualification, golden status, or promotion.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[4]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from factory.gate.windows_exit_admission import verify_windows_exit_admission
from factory.pipeline.archive_reader import ArchiveByteReader

HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")
CAPTURE_HASH = re.compile(r"[0-9a-f]{64}\Z")


class InputError(ValueError):
    pass


def digest(raw: bytes) -> str:
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def file_digest(path: Path) -> str:
    return digest(path.read_bytes())


def parse_json(path: Path, label: str) -> Any:
    def pairs(items):
        out = {}
        for key, value in items:
            if key in out:
                raise InputError(f"duplicate JSON key: {label}")
            out[key] = value
        return out

    try:
        return json.loads(path.read_bytes().decode("utf-8-sig"), object_pairs_hook=pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(InputError(f"nonfinite JSON: {label}")))
    except (UnicodeDecodeError, json.JSONDecodeError, OSError) as exc:
        raise InputError(f"invalid JSON: {label}") from exc


def require(condition: bool, message: str) -> None:
    if not condition:
        raise InputError(message)


def relative_path(base: Path, value: Any, label: str, *, directory: bool = False) -> Path:
    require(isinstance(value, str) and value and "\\" not in value and ":" not in value and "\x00" not in value,
            f"{label} must be safe config-relative path")
    candidate = Path(value)
    require(not candidate.is_absolute(), f"{label} must be config-relative")
    target = (base / candidate).resolve(strict=True)
    require(target.is_dir() if directory else target.is_file(), f"{label} target unavailable")
    return target


def load_inputs(path: Path) -> tuple[dict, Path, Path, ArchiveByteReader]:
    path = path.expanduser().resolve(strict=True)
    value = parse_json(path, "input manifest")
    expected = {"version", "expectedWindows", "macReport", "windowsCaptures",
                "macRoots", "macPathMap", "windowsArchives"}
    require(isinstance(value, dict) and set(value) == expected, "input manifest fields changed")
    require(type(value["version"]) is int and value["version"] == 1, "input manifest version")
    require(type(value["expectedWindows"]) is int and value["expectedWindows"] == 20,
            "F10 packet requires expectedWindows=20")
    base = path.parent
    mac_report = relative_path(base, value["macReport"], "macReport")
    windows_captures = relative_path(base, value["windowsCaptures"], "windowsCaptures")
    roots_value = value["macRoots"]
    require(isinstance(roots_value, list) and all(isinstance(x, str) for x in roots_value),
            "macRoots must be path array")
    mac_roots = [relative_path(base, item, "macRoots item", directory=True) for item in roots_value]
    path_map_value = value["macPathMap"]
    require(isinstance(path_map_value, dict), "macPathMap must be object")
    mac_path_map = {}
    for logical, physical in path_map_value.items():
        require(isinstance(logical, str) and logical.startswith("/") and ".." not in Path(logical).parts,
                "macPathMap key must be normalized absolute path")
        mac_path_map[logical] = relative_path(base, physical, f"macPathMap:{logical}")
    archive_value = value["windowsArchives"]
    require(isinstance(archive_value, dict), "windowsArchives must be object")
    archives = {}
    for capture_hash, location in archive_value.items():
        require(isinstance(capture_hash, str) and CAPTURE_HASH.fullmatch(capture_hash),
                "windowsArchives key must be lowercase capture hash")
        archives[capture_hash] = relative_path(base, location, f"windowsArchives:{capture_hash}", directory=True)
    require(archives, "windowsArchives must not be empty")
    try:
        reader = ArchiveByteReader(mac_roots=mac_roots, windows_archives=archives,
                                   mac_path_map=mac_path_map)
    except (ValueError, OSError) as exc:
        raise InputError(f"archive reader setup failed: {exc}") from exc
    return value, mac_report, windows_captures, reader


def mac_proof(report: dict, path: Path) -> dict:
    mac = report.get("macOS")
    require(isinstance(mac, dict) and mac.get("count") == 20, "Mac20 report count required")
    ids = mac.get("captureIds")
    require(isinstance(ids, list) and len(ids) == 20 and len(set(ids)) == 20,
            "Mac20 capture IDs required")
    proof = mac.get("originProof")
    require(isinstance(proof, dict) and proof.get("captureCount") == 20 and
            proof.get("descriptorCount") == 180 and proof.get("verified") == 180 and
            proof.get("failures") == [], "Mac20 origin proof incomplete")
    return {"path": str(path), "sha256": file_digest(path), "count": 20,
            "captureIdsSha256": digest(json.dumps(ids, separators=(",", ":")).encode())}


def windows_rows(payload: Any, manifest: dict, reader: ArchiveByteReader) -> list[dict]:
    if isinstance(payload, dict):
        require(payload.get("typedStatus") == "normalized-observational",
                "Windows adapter typedStatus must be normalized-observational")
        captures = payload.get("captures")
    else:
        captures = payload
    require(isinstance(captures, list) and len(captures) == manifest["expectedWindows"],
            "exact typed Windows20 capture list required")
    capture_hashes = []
    rows = []
    for capture in captures:
        require(isinstance(capture, dict) and capture.get("platform") == "windows",
                "typed Windows capture required")
        conditions = capture.get("meta", {}).get("conditions", {})
        require(isinstance(conditions, dict) and isinstance(conditions.get("windowsExitProof"), dict),
                "windowsExitProof required on every typed capture")
        capture_hash = __import__("factory.core.artifacts", fromlist=["canonical_hash"]).canonical_hash(capture).removeprefix("sha256:")
        capture_hashes.append(capture_hash)
        result = verify_windows_exit_admission(
            capture,
            read_bytes=lambda reference, current=capture: reader(capture=current, reference=reference),
        )
        rows.append({"run": capture.get("meta", {}).get("run"), "captureHash": capture_hash,
                     "status": result.get("status"), "issues": result.get("issues", []),
                     "evidenceHash": result.get("evidenceHash"),
                     "rawInputs": result.get("evidence", {}).get("rawInputs", {})})
        require(result.get("status") == "pass", f"Windows exit admission blocked for {capture_hash}")
    require(len(set(capture_hashes)) == 20, "Windows capture hashes must be unique")
    configured = set(manifest["windowsArchives"])
    require(configured == set(capture_hashes), "windowsArchives must exactly join typed capture hashes")
    runs = [row["run"] for row in rows]
    require(runs == list(range(1, 21)), "typed Windows runs must be exactly 1..20")
    return rows


def build(input_path: Path, output: Path) -> dict:
    manifest, mac_path, windows_path, reader = load_inputs(input_path)
    mac_report = parse_json(mac_path, "Mac report")
    windows_payload = parse_json(windows_path, "typed Windows captures")
    mac = mac_proof(mac_report, mac_path)
    rows = windows_rows(windows_payload, manifest, reader)
    report = {
        "schema": "paired-padding-f10-trusted-reader-observation-v1",
        "status": "source-bound-observation-complete",
        "candidateOnly": True,
        "inputs": {"manifest": {"path": str(input_path.resolve()), "sha256": file_digest(input_path)},
                   "macReport": mac, "windowsCaptures": {"path": str(windows_path), "sha256": file_digest(windows_path)}},
        "macOS": mac,
        "windows": {"typedCaptureCount": len(rows), "readerVerified": len(rows), "rows": rows},
        "comparison": {"status": "held-observation-only", "semantic": "held", "timing": "raw-only",
                        "nativeParity": "held", "pixelParity": "held", "goldens": 0, "promotion": "held"},
        "effects": {"nativeWindowActions": 0, "compilerActions": 0, "remoteActions": 0,
                    "lockActions": 0, "sourceMutations": 0},
    }
    require(not output.exists(), "output must be fresh")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    try:
        report = build(args.input, args.output)
    except (InputError, ValueError, OSError, KeyError, TypeError) as exc:
        print(json.dumps({"status": "blocked", "error": str(exc)}, sort_keys=True))
        return 2
    print(json.dumps({"status": report["status"], "macRuns": report["macOS"]["count"],
                      "windowsReaderVerified": report["windows"]["readerVerified"],
                      "nativeParity": report["comparison"]["nativeParity"]}, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
