from __future__ import annotations

import hashlib
import json
from pathlib import Path

from capture import (
    CACHE, CASE_FILE, CASE_ID, EVIDENCE, EXPECTED_CASE, EXPECTED_CLIENT_BINARY, EXPECTED_CLIENT_SOURCE,
    EXPECTED_HOST, EXPECTED_PROBE_MANIFEST, EXPECTED_SOURCE, HOST, PRIOR_RUNS, PRIOR_SUMMARY,
    PROBE_MANIFEST, ROOT, SOURCE, validate_raw_observation,
)

HERE = Path(__file__).resolve().parent


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ref(path: Path, role: str) -> dict:
    return {"role": role, "path": str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),
            "bytes": path.stat().st_size, "sha256": sha(path)}


def write(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    if sha(SOURCE) != EXPECTED_SOURCE or sha(PROBE_MANIFEST) != EXPECTED_PROBE_MANIFEST or sha(CASE_FILE) != EXPECTED_CASE:
        raise SystemExit("pinned source/case/probe changed")
    if sha(HOST) != EXPECTED_HOST:
        raise SystemExit("existing internal host executable changed")
    summary = json.loads(PRIOR_SUMMARY.read_text())
    if summary["sourceHash"] != "sha256:" + EXPECTED_SOURCE or summary["case"]["hash"] != "sha256:" + EXPECTED_CASE or summary["binaryHash"] != "sha256:" + EXPECTED_HOST:
        raise SystemExit("prior capture summary identity mismatch")
    if sha(CACHE / "AXEnabledClient.swift") != EXPECTED_CLIENT_SOURCE or sha(CACHE / "ax-enabled-client") != EXPECTED_CLIENT_BINARY:
        raise SystemExit("internal AX client source/binary changed")
    preflight = json.loads((EVIDENCE / "preflight-result.json").read_text())
    if preflight.get("axTrusted") is not True or preflight.get("permissionRequests") is not False:
        raise SystemExit("no-prompt AX preflight did not pass")

    references = [
        ref(SOURCE, "generated-case-source"), ref(PROBE_MANIFEST, "generated-probe-manifest"),
        ref(CASE_FILE, "f9-case"), ref(PRIOR_SUMMARY, "prior-20-run-capture-summary"),
        ref(HERE / "AXEnabledClient.swift", "ax-client-source"),
        ref(EVIDENCE / "preflight-result.json", "ax-no-prompt-preflight"),
        ref(EVIDENCE / "preflight-run.stdout.txt", "ax-preflight-stdout"),
        ref(EVIDENCE / "preflight-run.stderr.txt", "ax-preflight-stderr"),
        ref(EVIDENCE / "build.stdout.txt", "ax-client-build-stdout"),
        ref(EVIDENCE / "build.stderr.txt", "ax-client-build-stderr"),
        ref(EVIDENCE / "swiftc-path.txt", "swift-compiler-path"),
        ref(EVIDENCE / "swiftc-version.txt", "swift-compiler-version"),
        ref(EVIDENCE / "xcode-version.txt", "xcode-version"),
        ref(EVIDENCE / "sw-vers.txt", "macos-version"),
        ref(EVIDENCE / "client-codesign.stderr.txt", "ax-client-code-identity"),
        ref(EVIDENCE / "binaries.txt", "binary-file-identities"),
    ]
    for index in range(1, 21):
        old_dir = PRIOR_RUNS / f"run-{index:03d}"
        old_owner_path = old_dir / "owned-window-process.json"
        old_owner = json.loads(old_owner_path.read_text())
        if old_owner.get("binaryHash") != "sha256:" + EXPECTED_HOST or old_owner.get("executable") != str(HOST):
            raise SystemExit(f"prior owner receipt {index} differs")
        references.append(ref(old_owner_path, f"prior-run-{index:03d}-owner-receipt"))

    report = json.loads((EVIDENCE / "report.json").read_text())
    new_runs = []
    for index in range(1, 21):
        run_dir = EVIDENCE / f"run-{index:03d}"
        raw_path = run_dir / "external-ax.raw.json"
        owner_path = run_dir / "owner-process.json"
        raw = json.loads(raw_path.read_text())
        owner = json.loads(owner_path.read_text())
        validated = validate_raw_observation(raw, owner)
        result_path = run_dir / "result.json"
        result = json.loads(result_path.read_text())
        if result["run"] != index or result["rawSha256"] != sha(raw_path) or result["enabledAttribute"] != validated["enabledAttribute"]:
            raise SystemExit(f"run {index} result does not match raw capture")
        file_refs = []
        for name in ("owner-process.json", "owned-window-events.jsonl", "owned-window.stdout.txt",
                     "external-ax.stdout.txt", "external-ax.stderr.txt", "external-ax.raw.json",
                     "ax-invocation.json", "result.json"):
            file_refs.append(ref(run_dir / name, f"run-{index:03d}-{name}"))
        new_runs.append({
            "run": index, "pid": owner["pid"], "startedAt": owner["processStartFromPs"],
            "windowTitle": owner["windowTitle"], "status": raw["status"],
            "AXEnabled": validated["enabledAttribute"], "files": file_refs,
        })
    if len({row["pid"] for row in new_runs}) != 20:
        raise SystemExit("new run owner PIDs are not unique")
    report["priorRunOwnerReceipts"] = [
        {"path": row["path"], "sha256": row["sha256"], "bytes": row["bytes"]}
        for row in references if row["role"].startswith("prior-run-")
    ]
    write(EVIDENCE / "report.json", report)
    input_manifest = {
        "kind": "disabled-enabled-ax-observation-input-manifest", "version": 1,
        "caseId": CASE_ID, "caseSha256": EXPECTED_CASE, "sourceSha256": EXPECTED_SOURCE,
        "probeManifestSha256": EXPECTED_PROBE_MANIFEST,
        "priorHostBinary": {"path": str(HOST), "sha256": EXPECTED_HOST},
        "axClient": {"sourcePath": str(HERE / "AXEnabledClient.swift"), "sourceSha256": EXPECTED_CLIENT_SOURCE,
                     "internalBinaryPath": str(CACHE / "ax-enabled-client"), "binarySha256": EXPECTED_CLIENT_BINARY,
                     "preflight": preflight},
        "permissionRequests": False, "inputReferences": references, "priorRunCount": 20,
        "newRunCount": 20, "newRuns": new_runs,
    }
    write(EVIDENCE / "input-manifest.json", input_manifest)
    files = []
    for path in sorted(HERE.rglob("*")):
        if not path.is_file() or path.name in {"stage-manifest.json", "SHA256SUMS"} or "__pycache__" in path.parts:
            continue
        files.append({"path": str(path.relative_to(ROOT)), "bytes": path.stat().st_size, "sha256": sha(path)})
    stage = {"kind": "disabled-enabled-ax-observation-stage-manifest", "version": 1,
             "status": report["status"], "files": files}
    write(EVIDENCE / "stage-manifest.json", stage)
    lines = []
    for path in sorted(HERE.rglob("*")):
        if not path.is_file() or path.name == "SHA256SUMS" or "__pycache__" in path.parts:
            continue
        lines.append(f"{sha(path)}  {path.relative_to(ROOT)}")
    (EVIDENCE / "SHA256SUMS").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"status": report["status"], "inputRefs": len(references),
                      "newRuns": len(new_runs), "stageFiles": len(files)}, sort_keys=True))


if __name__ == "__main__":
    main()
