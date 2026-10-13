"""Read-only review of v4 index bindings to immutable actual-v2 evidence."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
V2 = ROOT.parent / "seed-origin-actual-v2"
OUT = Path(__file__).resolve().parent

def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()

def load(path: Path):
    return json.loads(path.read_text())

def safe_ref(value: str) -> Path:
    p = Path(value)
    if p.is_absolute():
        raise ValueError("absolute reference")
    q = (ROOT / p).resolve()
    if not q.is_relative_to(ROOT.parent.resolve()):
        raise ValueError(f"reference escapes v4/v2 roots: {value}")
    return q

def local_ref(value: str) -> Path:
    p = Path(value)
    if p.is_absolute() or ".." in p.parts:
        raise ValueError(f"non-local reference: {value}")
    q = (ROOT / p).resolve()
    if not q.is_relative_to(ROOT.resolve()):
        raise ValueError(f"reference escapes v4 root: {value}")
    return q

def check(condition: bool, failures: list[str], code: str) -> None:
    if not condition:
        failures.append(code)

def run() -> dict[str, object]:
    failures: list[str] = []
    idx = load(ROOT / "admission-index-v4.json")
    stage = load(ROOT / "stage-manifest-v4.json")
    check(idx.get("candidateOnly") is True, failures, "index-candidateOnly")
    check(idx.get("pathBase") == "factory/oracle/mac/seed-origin-actual-v4", failures, "index-pathBase")
    check(idx.get("decision") == "BLOCKED_ARCHIVE_HISTORY_ONLY", failures, "index-decision")
    check(stage.get("candidateOnly") is True, failures, "stage-candidateOnly")
    check(stage.get("decision") == idx.get("decision"), failures, "stage-decision")

    # Stage manifest is checked independently of its producer verifier.
    for row in stage.get("files", []):
        p = ROOT / str(row.get("path", ""))
        check(p.is_file(), failures, f"stage-missing:{row.get('path')}")
        if p.is_file():
            check(p.stat().st_size == row.get("bytes"), failures, f"stage-bytes:{row.get('path')}")
            check(sha(p).removeprefix("sha256:") == row.get("sha256"), failures, f"stage-sha:{row.get('path')}")
    listed = {str(row.get("path")) for row in stage.get("files", [])}
    check(listed == {"README.md", "admission-index-v4.json", "fault-controls-v4.json", "freeze_stage_v4.py", "path-controls-v4.json", "path_controls_v4.py", "test_v4.py", "verify_v4.py"}, failures, "stage-file-set")

    # All cross-stage references are relative, pinned, and resolve to v2 bytes.
    for field in ("captureCommand", "captureIndex", "immutableArchiveMap", "immutableStageManifest"):
        ref = idx.get(field)
        check(isinstance(ref, str) and ".." in Path(ref).parts, failures, f"index-ref-shape:{field}")
        if isinstance(ref, str):
            try:
                p = safe_ref(ref)
                check(p.is_file(), failures, f"index-ref-missing:{field}")
                pin = idx.get(field + "Sha256")
                check(isinstance(pin, str) and sha(p) == pin, failures, f"index-ref-sha:{field}")
            except ValueError:
                failures.append(f"index-ref-invalid:{field}")
    check(idx.get("immutableArchiveMap") == "../seed-origin-actual-v2/archive-map.json", failures, "map-ref")
    check(idx.get("immutableStageManifest") == "../seed-origin-actual-v2/stage-manifest.json", failures, "stage-ref")

    # Capture index/command are immutable v2 roots and retain candidate/no-permission policy.
    command = load(safe_ref(idx["captureCommand"]))
    capture_index = load(safe_ref(idx["captureIndex"]))
    check(command.get("candidateOnly") is True, failures, "command-candidateOnly")
    check(command.get("permissionRequests") is False, failures, "command-permissions")
    check(command.get("caseRoot") == "factory/oracle/mac/seed-origin-v8/inputs", failures, "command-caseRoot")
    check(len(capture_index.get("results", [])) == 5, failures, "capture-index-cases")

    # Immutable map is byte-checked, while known stale historical row remains explicit.
    archive_map = load(safe_ref(idx["immutableArchiveMap"]))
    map_bad: list[str] = []
    stale: list[dict[str, object]] = []
    expected_stale = "sha256:202cd05db010a4329708a73167b9971ace22009702d3678d4db2d897435bf892"
    for row in archive_map.get("files", []):
        p = V2 / str(row.get("path", ""))
        actual = sha(p) if p.is_file() else None
        if row.get("path") == "fault-controls.json":
            if row.get("bytes") != 1153 or row.get("sha256") != expected_stale:
                map_bad.append("fault-controls.json:expected-row-changed")
            stale.append({"path": row.get("path"), "bytes": row.get("bytes"), "expectedSha256": row.get("sha256"), "actualSha256": actual})
            check(actual == "sha256:233714ad190f266a54ea0946bb41fd14c8b7b4a308f5a6c1a829cffabc4a1095", failures, "stale-row-actual")
        else:
            if not p.is_file() or p.stat().st_size != row.get("bytes") or actual != row.get("sha256"):
                map_bad.append(str(row.get("path")))
    check(len(archive_map.get("files", [])) == 2134, failures, "archive-map-cardinality")
    check(len(stale) == 1, failures, "stale-row-cardinality")

    case_rows: list[dict[str, object]] = []
    summary_names = {str(row.get("case")): row for row in idx.get("cases", [])}
    check(set(summary_names) == {"swiftui.disabled.recipe.gate-seeded.ca4e13f820f5d258", "swiftui.image.recipe.gate-seeded.ca4e13f820f5d258", "swiftui.shapes.fill-stroke.recipe.gate-seeded.ca4e13f820f5d258", "swiftui.text.bundled-font.recipe.gate-seeded.ca4e13f820f5d258", "swiftui.toggle.recipe.gate-seeded.ca4e13f820f5d258"}, failures, "case-set")
    check(len(idx.get("cases", [])) == 5, failures, "case-index-cardinality")
    input_hashes = {}
    for row in archive_map.get("files", []):
        path = str(row.get("path", ""))
        if path.startswith("archive/inputs/") and path.endswith(".json"):
            input_hashes[Path(path).stem] = row.get("sha256")
    for case, row in summary_names.items():
        case_failures: list[str] = []
        try:
            summary_path = safe_ref(str(row["summaryPath"]))
        except Exception as exc:
            case_failures.append(f"summary-ref:{exc}")
            case_rows.append({"case": case, "runs": 0, "failures": case_failures})
            continue
        check(summary_path == V2 / case / "summary.json", failures, f"summary-location:{case}")
        check(sha(summary_path) == row.get("summarySha256"), failures, f"summary-index-sha:{case}")
        if not summary_path.is_file():
            case_rows.append({"case": case, "runs": 0, "failures": case_failures + ["summary-missing"]})
            continue
        summary = load(summary_path)
        archive_dir = V2 / "archive" / case
        input_path = V2 / "archive" / "inputs" / f"{case}.json"
        witness = archive_dir / "source/Witness.swift"
        adapter = archive_dir / "source/CaptureHost.swift"
        binary = archive_dir / "binary/capture-host"
        expected_case = {"id": case, "hash": sha(input_path)}
        if summary.get("case") != expected_case: case_failures.append("case-join")
        if summary.get("candidateOnly") is not True or summary.get("status") != "CANDIDATE_CAPTURED": case_failures.append("candidate-policy")
        if summary.get("sourceHash") != sha(witness): case_failures.append("witness-join")
        if summary.get("binaryHash") != sha(binary): case_failures.append("binary-join")
        if summary.get("compiledAdapterHash") != sha(adapter): case_failures.append("adapter-join")
        receipt_path = V2 / case / "compiler-receipt.json"
        receipt = summary.get("compilerReceipt")
        if not isinstance(receipt, dict) or not receipt_path.is_file() or load(receipt_path) != receipt:
            case_failures.append("receipt-embedded-join")
        else:
            compiler = receipt.get("compiler", {}); resolver = receipt.get("resolver", {})
            if receipt.get("status") != "SUCCESS" or receipt.get("sourceDrift") is not False: case_failures.append("receipt-status")
            if compiler.get("exitCode") != 0 or compiler.get("timedOut") is not False or compiler.get("ownedProcessGroup") is not True: case_failures.append("compiler-process")
            if resolver.get("exitCode") != 0 or resolver.get("ownedProcessGroup") is not True: case_failures.append("resolver-process")
            if compiler.get("sourceBefore") != compiler.get("sourceAfter") or compiler.get("realToolBefore") != compiler.get("realToolAfter") or compiler.get("realToolDrift") is not False: case_failures.append("source-tool-drift")
            if compiler.get("sourceBefore", {}).get("Witness.swift", {}).get("sha256") != sha(witness) or compiler.get("sourceBefore", {}).get("CaptureHost.swift", {}).get("sha256") != sha(adapter): case_failures.append("receipt-source-join")
            if compiler.get("outputBinary", {}).get("sha256") != sha(binary): case_failures.append("receipt-binary-join")
            for proc in (resolver, compiler):
                for key in ("stdoutPath", "stderrPath"):
                    p = Path(proc.get(key, ""))
                    if not p.is_file() or sha(p) != proc.get(key.replace("Path", "Hash")): case_failures.append("stream-join")
        runs = summary.get("runs")
        if not isinstance(runs, list) or len(runs) != 20: case_failures.append("run-cardinality")
        if isinstance(runs, list):
            for number, run in enumerate(runs, 1):
                if not isinstance(run, dict) or run.get("run") != number: case_failures.append(f"run-shape:{number}"); continue
                run_dir = V2 / case / f"run-{number:03d}"
                capture = run_dir / "capture.json"
                if not capture.is_file() or sha(capture) != run.get("captureHash"): case_failures.append(f"capture-join:{number}"); continue
                cap = load(capture)
                if cap.get("case") != expected_case or cap.get("platform") != "macos" or cap.get("meta", {}).get("conditions", {}).get("candidateOnly") is not True: case_failures.append(f"capture-meta:{number}")
                for key, raw_name, png_name in (("plain", "plain.raw.json", "plain.png"), ("instrumented", "instrumented.raw.json", "instrumented.png"), ("compositor", "compositor.raw.json", "compositor.png")):
                    raw = run_dir / raw_name; png = run_dir / png_name
                    if not raw.is_file() or not png.is_file(): case_failures.append(f"image-files:{number}:{key}"); continue
                    image_id = "macos." + key
                    image = next((x for x in cap.get("images", []) if isinstance(x, dict) and x.get("id") == image_id), None)
                    if not isinstance(image, dict) or image.get("hash") != sha(png): case_failures.append(f"image-join:{number}:{key}")
                    raw_obj = load(raw)
                    if key != "compositor" and raw_obj.get("permissions", {}).get("permissionRequests") is not False: case_failures.append(f"permission:{number}:{key}")
                ax = run_dir / "external-ax.raw.json"
                if not ax.is_file() or load(ax).get("permissionRequests") is not False: case_failures.append(f"ax:{number}")
        case_rows.append({"case": case, "runs": len(runs) if isinstance(runs, list) else 0, "failures": case_failures})

    controls = load(ROOT / "fault-controls-v4.json")
    path_controls = load(ROOT / "path-controls-v4.json")
    check(sha(ROOT / "fault-controls-v4.json") == idx.get("faultControlsSha256"), failures, "fault-controls-pin")
    check(sha(ROOT / "path-controls-v4.json") == idx.get("pathControlsSha256"), failures, "path-controls-pin")
    check(len(controls.get("controls", [])) == 7 and all(c.get("acceptedBaseline") is True and c.get("rejected") is True for c in controls.get("controls", [])), failures, "fault-controls")
    check(len(path_controls.get("controls", [])) == 2 and all(c.get("acceptedBaseline") is True and c.get("rejected") is True for c in path_controls.get("controls", [])), failures, "path-controls")
    failures.extend(f"{case}:{code}" for row in case_rows for case in [row["case"]] for code in row["failures"])
    total_runs = sum(int(row["runs"]) for row in case_rows)
    return {"kind": "seed-origin-actual-v4-independent-review", "version": "1", "candidateOnly": True, "cases": len(case_rows), "runs": total_runs, "rows": case_rows, "archiveMapRows": len(archive_map.get("files", [])), "archiveMapIntegrityFailures": map_bad, "staleHistoricalRows": stale, "failures": failures, "nativeCompilerRemoteRuns": 0, "freshIndexBinding": "PASS" if not failures else "BLOCKED", "decision": "BLOCKED_ARCHIVE_HISTORY_ONLY" if not failures and stale else "BLOCKED", "notes": ["v4 explicit pathBase binds five summaries to immutable v2 bytes", "v2 historical fault-controls map row remains stale and is preserved; fresh v4 controls are separate", "no recapture, compiler, native, remote, parity, or promotion performed"], "sourcePins": {"v4Index": sha(ROOT / "admission-index-v4.json"), "v4Stage": sha(ROOT / "stage-manifest-v4.json"), "v4FaultControls": sha(ROOT / "fault-controls-v4.json"), "v4PathControls": sha(ROOT / "path-controls-v4.json"), "v2ArchiveMap": sha(V2 / "archive-map.json"), "v2Stage": sha(V2 / "stage-manifest.json")}}

if __name__ == "__main__":
    report = run()
    (OUT / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, indent=2, sort_keys=True))
    raise SystemExit(0 if report["freshIndexBinding"] == "PASS" else 1)
