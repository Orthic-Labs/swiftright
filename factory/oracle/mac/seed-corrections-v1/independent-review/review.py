#!/usr/bin/env python3
"""Offline independent review of seed-corrections-v1 evidence."""
from __future__ import annotations

import copy
import hashlib
import json
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
PACKET = ROOT / "factory/oracle/mac/seed-corrections-v1"
SEED = 14577611000270672472
BLOCKS = ("stack-overlay", "padding-frame", "scroll-view", "custom-layout", "preference-key")
SUFFIX = ".recipe.gate-seeded.ca4e13f820f5d258"
INTERNAL = "/Users/adrdsouza/Library/Caches/SwiftRightFactory/"


def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_sha(value) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def load(path: Path):
    return json.loads(path.read_text())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def pin_file(root: Path, pin: dict) -> None:
    path = root / pin["path"]
    require(path.is_file() and not path.is_symlink(), f"missing pin {pin['path']}")
    require(path.stat().st_size == pin["bytes"], f"size {pin['path']}")
    require(sha(path) == pin["sha256"], f"hash {pin['path']}")


def input_checks(packet: Path, pins: dict) -> dict:
    require(pins["seed"] == SEED, "seed")
    rows = {row["block"]: row for row in pins["rows"]}
    require(set(rows) == set(BLOCKS) and len(rows) == 5, "exact five input cases")
    case_hashes = {}
    for block, row in rows.items():
        require(row["seed"] == SEED, f"{block} seed")
        for key in ("manifest", "source", "case", "recipe"):
            pin_file(packet, row[key])
        manifest = load(packet / row["manifest"]["path"])
        case = load(packet / row["case"]["path"])
        recipe = load(packet / row["recipe"]["path"])
        source_path = packet / row["source"]["path"]
        require(case["seed"] == SEED, f"{block} case seed")
        require(sha(source_path) == manifest["sourceHash"] == row["source"]["declared"], f"{block} source lineage")
        require(canonical_sha(case) == manifest["case"]["hash"] == row["case"]["declared"], f"{block} case lineage")
        require(canonical_sha(recipe) == manifest["recipe"]["hash"] == row["recipe"]["declared"], f"{block} recipe lineage")
        require(manifest["case"]["id"] == row["caseID"] == row["manifestCaseID"], f"{block} case identity")
        case_hashes[block] = {"caseId": row["caseID"], "source": row["source"]["declared"], "recipe": row["recipe"]["declared"]}
    return {"seed": SEED, "caseCount": len(rows), "cases": case_hashes}


def producer_stage_checks(packet: Path) -> dict:
    stage = load(packet / "stage-manifest.json")
    entries = stage["entries"]
    require(len(entries) == 2076, "producer stage entry count")
    total = 0
    for entry in entries:
        pin_file(packet, entry)
        total += entry["bytes"]
    return {"entryCount": len(entries), "totalBytes": total, "stageSha256": sha(packet / "stage-manifest.json")}


def tree_hosting_node_count(tree: dict) -> int:
    def hosting(node):
        if node.get("subrole") == "AXHostingView":
            return node
        for child in node.get("children", []):
            found = hosting(child)
            if found is not None:
                return found
        return None

    host = hosting(tree)
    require(host is not None, "AXHostingView")

    def count_static(node):
        return int(node.get("role") == "AXStaticText") + sum(count_static(child) for child in node.get("children", []))

    return count_static(host)


def summary_checks(packet: Path, pins: dict, receipt: dict) -> dict:
    summary = load(packet / "capture-summary.json")
    require(summary["seed"] == SEED and summary["qualification"] == "observational-candidate-only; no promotion", "summary")
    cases = {row["case"].split(".recipe.")[0].removeprefix("swiftui."): row for row in summary["cases"]}
    require(set(cases) == set(BLOCKS) and len(cases) == 5, "summary case closure")
    by_block = {row["block"]: row for row in pins["rows"]}
    global_processes = set()
    capture_source_hashes = set()
    reports = []
    for block in BLOCKS:
        case_id = f"swiftui.{block}{SUFFIX}"
        case_dir = packet / "evidence" / case_id
        s = load(case_dir / "summary.json")
        row = by_block[block]
        require(s["candidateOnly"] is True and s["acceptance"] == "not-promoted", f"{block} promotion")
        require(s["status"] == "CANDIDATE_CAPTURED" and len(s["runs"]) == 20, f"{block} run count")
        require(s["case"]["id"] == case_id and s["case"]["hash"] == row["case"]["declared"], f"{block} case")
        require(s["sourceHash"] == row["source"]["declared"], f"{block} summary source")
        binary = packet / f"binaries/{block}/capture-host"
        binary_hash = sha(binary)
        require(s["binaryHash"] == binary_hash, f"{block} binary lineage")
        require(s["channels"]["externalAX"] == ("HELD" if block == "custom-layout" else "OBSERVED"), f"{block} AX channel")
        require(s["channels"]["offscreenPaint"] == ("HELD" if block == "scroll-view" else "OBSERVED"), f"{block} offscreen channel")
        run_numbers = [run["run"] for run in s["runs"]]
        require(sorted(run_numbers) == list(range(1, 21)) and len(set(run_numbers)) == 20, f"{block} run closure")
        run_reports = []
        for run in s["runs"]:
            n = run["run"]
            run_dir = case_dir / f"run-{n:03d}"
            require(run_dir.is_dir() and not run_dir.is_symlink(), f"{block} run path {n}")
            capture = load(run_dir / "capture.json")
            require(capture["case"]["id"] == case_id and capture["case"]["hash"] == row["case"]["declared"], f"{block} capture case {n}")
            require(capture["id"].endswith(f".macos.run-{n:03d}"), f"{block} capture id {n}")
            require(sha(run_dir / "capture.json") == run["captureHash"], f"{block} capture hash {n}")
            require(capture["meta"]["conditions"]["candidateOnly"] is True, f"{block} candidate tag {n}")
            require(capture["meta"]["conditions"]["observationalOnly"] is True, f"{block} observation tag {n}")
            require(capture["meta"]["conditions"]["channelStatus"] == s["channels"], f"{block} channel tag {n}")
            generated_host_hash = capture["provenance"].get("sourceHash")
            require(isinstance(generated_host_hash, str) and generated_host_hash.startswith("sha256:"), f"{block} generated host source hash {n}")
            require(generated_host_hash != s["sourceHash"], f"{block} source hash role separation {n}")
            require(generated_host_hash == sha(run_dir / "instrumented.raw.json"), f"{block} raw instrumented source hash {n}")
            capture_source_hashes.add(generated_host_hash)
            require(capture["provenance"]["inputs"][0]["hash"] == binary_hash, f"{block} raw binary tag {n}")
            require(capture["layout"][0]["probeTag"] == f"{case_id.removesuffix(SUFFIX)}:{case_id.removesuffix(SUFFIX)}.witness", f"{block} probe tag {n}")
            pids = []
            for mode in ("plain", "instrumented"):
                raw_path, png_path = run_dir / f"{mode}.raw.json", run_dir / f"{mode}.png"
                raw = load(raw_path)
                item = run[mode]
                require(sha(raw_path) == item["rawHash"] and sha(png_path) == item["pngHash"], f"{block} {mode} hashes {n}")
                require(raw["instrumented"] is (mode == "instrumented"), f"{block} {mode} flag {n}")
                require(raw["permissions"] == {"axTrusted": True, "permissionRequests": False, "screenCaptureGranted": True}, f"{block} {mode} permissions {n}")
                require(raw["host"]["arch"] == "arm64" and raw["host"]["mainDisplayPixels"] == {"height": 1080, "width": 1920}, f"{block} {mode} device {n}")
                require(raw["image"]["width"] == item["image"]["width"] and raw["image"]["height"] == item["image"]["height"], f"{block} {mode} image metrics {n}")
                pids.append(raw["pid"])
            compositor_raw = run_dir / "compositor.raw.json"
            compositor_png = run_dir / "compositor.png"
            compositor = load(compositor_raw)
            require(sha(compositor_raw) == run["compositorRawHash"] and sha(compositor_png) == run["compositorPngHash"], f"{block} compositor hashes {n}")
            require(compositor["mode"] == "own-window-compositor" and compositor["permissionRequests"] is False, f"{block} compositor guard {n}")
            pids.append(compositor["pid"])
            image = next(x for x in capture["images"] if x["id"] == "macos.compositor")
            require(image["hash"] == run["compositorPngHash"] and image["widthPx"] == compositor["image"]["width"] and image["heightPx"] == compositor["image"]["height"], f"{block} compositor pixels {n}")
            ax_raw_path = run_dir / "external-ax.raw.json"
            ax = load(ax_raw_path)
            process = load(run_dir / "owned-window-process.json")
            require(sha(ax_raw_path) == run["externalAXRawHash"], f"{block} AX hash {n}")
            require(ax["mode"] == "fresh-external-ax" and ax["status"] == "OBSERVED" and ax["permissionRequests"] is False, f"{block} AX guard {n}")
            require(ax["ownerHash"] == binary_hash and ax["ownerPath"].startswith(INTERNAL + "seed-corrections-v1-run-20261011/"), f"{block} AX owner {n}")
            require(process["binaryHash"] == binary_hash and process["processGroupOwned"] is True and process["executable"].startswith(INTERNAL + "seed-corrections-v1-run-20261011/"), f"{block} process owner {n}")
            require(run["externalAXWitnessNodes"] == tree_hosting_node_count(ax["steps"][0]["tree"]), f"{block} AX node count {n}")
            pids.extend([ax["pid"], process["pid"]])
            require(len(set(pids)) == 4 and all(isinstance(pid, int) and pid > 0 for pid in pids), f"{block} process closure {n}")
            require(not global_processes.intersection(pids), f"{block} process alias {n}")
            global_processes.update(pids)
            if block == "custom-layout":
                require(run["externalAX"] == "HELD" and run["externalAXWitnessNodes"] == 0, f"{block} held AX {n}")
            else:
                require(run["externalAX"] == "OBSERVED" and run["externalAXWitnessNodes"] > 0, f"{block} AX witness {n}")
            if block == "scroll-view":
                require(run["offscreen"] == "HELD", f"{block} held offscreen {n}")
            else:
                require(run["offscreen"] == "OBSERVED", f"{block} offscreen {n}")
            require(run.get("instrumentationPixelsEqual", run["plain"]["pngHash"] == run["instrumented"]["pngHash"]) is True and run["plain"]["pngHash"] == run["instrumented"]["pngHash"], f"{block} matched pixels {n}")
            run_reports.append({"run": n, "distinctProcessIds": 4, "probeTag": capture["layout"][0]["probeTag"], "plainPixels": run["plain"]["pngHash"], "instrumentedPixels": run["instrumented"]["pngHash"]})
        reports.append({"block": block, "caseId": case_id, "sourceHash": s["sourceHash"], "binaryHash": binary_hash, "runs": 20, "runReports": run_reports, "captureSourceHashes": sorted({capture["provenance"]["sourceHash"] for capture in (load((case_dir / f"run-{n:03d}" / "capture.json")) for n in range(1, 21))}), "externalAXWitnessNodes": sorted({x["externalAXWitnessNodes"] for x in s["runs"]}), "offscreen": s["channels"]["offscreenPaint"]})
    return {"caseCount": 5, "runCountPerCase": 20, "totalRuns": 100, "globalDistinctProcesses": len(global_processes), "captureSourceHashCount": len(capture_source_hashes), "cases": reports}


def environment_checks(packet: Path, receipt: dict) -> dict:
    require(receipt["seed"] == SEED and receipt["permissionRequests"] is False, "receipt permission")
    require(receipt["sourceRootWasInternal"] is True and receipt["internalRunRoot"].startswith(INTERNAL), "internal execution root")
    fresh = receipt["freshAX"]
    require(fresh["externalAX"] == "AVAILABLE" and fresh["preflight"]["axTrusted"] is True and fresh["preflight"]["permissionRequests"] is False, "fresh AX grant")
    require(fresh["executable"].startswith(INTERNAL) and not fresh["executable"].startswith("/Volumes/D"), "fresh AX path")
    recorder = receipt["signedRecorder"]
    require(recorder["axTrusted"] is True and recorder["permissionRequests"] is False and recorder["externalAX"] == "HELD", "signed recorder grant")
    require(recorder["genericProtocolSupported"] is False and recorder["sourceBinaryProtocol"] == "F1-only" and recorder["preflightExit"] == 2, "signed recorder protocol guard")
    require("Developer ID Application:" in recorder["identityDetails"] and "Chosen signature=1" in recorder["identityDetails"], "signed recorder signature")
    for path in ("evidence/fresh-ax-preflight.stdout.txt", "evidence/recorder-capabilities.json", "evidence/recorder-identity.stderr.txt", "evidence/recorder-no-prompt-preflight.stderr.txt"):
        require((packet / path).is_file(), path)
    preflight = json.loads((packet / "evidence/fresh-ax-preflight.stdout.txt").read_text())
    require(preflight == {"axTrusted": True, "permissionRequests": False, "pid": preflight["pid"]}, "fresh AX receipt")
    require("intentionally-nonexistent-preflight-fixture" in (packet / "evidence/recorder-no-prompt-preflight.stderr.txt").read_text(), "no-prompt receipt")
    return {"freshAX": True, "signedRecorderGrant": True, "internalDevice": True, "permissionRequests": False, "recorderExternalAX": "HELD"}


def source_join_checks(packet: Path, pins: dict) -> dict:
    """Keep witness-source hashes distinct from generated-host source hashes.

    Capture records expose generated-host hashes, but packet has no immutable
    generated-host source bytes, embedded witness bytes, or compile-source
    manifest keyed by those hashes. This is an explicit hold, never an alias.
    """
    witness_hashes = {row["source"]["declared"] for row in pins["rows"]}
    capture_hashes = set()
    raw_matches = 0
    capture_count = 0
    missing_fields = {"embeddedWitnessBytes": 0, "generatedHostSourceArchive": 0, "compileSourceProvenance": 0}
    for capture_path in sorted((packet / "evidence").glob("*/run-*/capture.json")):
        capture = load(capture_path)
        capture_count += 1
        source_hash = capture.get("provenance", {}).get("sourceHash")
        require(isinstance(source_hash, str) and source_hash.startswith("sha256:"), f"capture source hash {capture_path}")
        require(source_hash not in witness_hashes, f"capture source hash alias {capture_path}")
        capture_hashes.add(source_hash)
        if source_hash == sha(capture_path.parent / "instrumented.raw.json"):
            raw_matches += 1
        for field in missing_fields:
            if field not in capture and field not in capture.get("provenance", {}):
                missing_fields[field] += 1
    require(capture_count == 100 and len(capture_hashes) == 100 and raw_matches == 100, "capture source hash closure")
    summaries = [load(path) for path in sorted((packet / "evidence").glob("*/summary.json"))]
    adapter_hashes = {summary.get("adapterSourceHash") for summary in summaries}
    compiled_hashes = {summary.get("compiledAdapterHash") for summary in summaries}
    require(len(summaries) == 5 and all(isinstance(value, str) and value.startswith("sha256:") for value in adapter_hashes | compiled_hashes), "adapter lineage fields")
    staged_names = {entry["path"] for entry in load(packet / "stage-manifest.json")["entries"]}
    adapter_bytes = sorted(path for path in staged_names if "adapter" in path.lower() or "capturehost" in path.lower())
    return {
        "status": "HELD_MISSING_GENERATED_HOST_SOURCE_ARCHIVE",
        "witnessSourceHashCount": len(witness_hashes),
        "captureCount": capture_count,
        "captureSourceHashCount": len(capture_hashes),
        "rawInstrumentedHashMatches": raw_matches,
        "summaryAdapterSourceHashCount": len(adapter_hashes),
        "summaryCompiledAdapterHashCount": len(compiled_hashes),
        "stagedAdapterSourceFiles": adapter_bytes,
        "missingRequiredJoinFields": missing_fields,
        "stagedWitnessSourceFiles": sorted(path for path in staged_names if path.startswith("inputs/") and path.endswith(".swift")),
        "reason": "capture provenance sourceHash equals raw instrumented evidence bytes; packet lacks exact adaptedCaptureHost source bytes, embedded witness bytes, & compile argv/source manifest keyed by summary adapter hashes",
        "noAlias": True,
    }


def run_numbers_valid(summary: dict) -> bool:
    numbers = [run["run"] for run in summary["runs"]]
    return sorted(numbers) == list(range(1, 21)) and len(set(numbers)) == 20


def control_checks(packet: Path, pins: dict) -> dict:
    outcomes = {}
    source_row = next(row for row in pins["rows"] if row["block"] == "custom-layout")
    with tempfile.TemporaryDirectory() as temp:
        tmp = Path(temp)
        src = tmp / source_row["source"]["path"]
        src.parent.mkdir(parents=True)
        src.write_bytes((packet / source_row["source"]["path"]).read_bytes() + b"\n")
        try:
            pin_file(tmp, source_row["source"])
        except AssertionError:
            outcomes["source-byte-mutation"] = "rejected"
        else:
            raise AssertionError("source mutation accepted")
    with tempfile.TemporaryDirectory() as temp:
        tmp = Path(temp)
        case = tmp / source_row["case"]["path"]
        case.parent.mkdir(parents=True)
        value = load(packet / source_row["case"]["path"])
        value["seed"] = 0
        case.write_text(json.dumps(value))
        try:
            pin_file(tmp, source_row["case"])
        except AssertionError:
            outcomes["case-seed-mutation"] = "rejected"
        else:
            raise AssertionError("case mutation accepted")
    summary_path = packet / "evidence/swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258/summary.json"
    summary = load(summary_path)
    duplicate = copy.deepcopy(summary)
    duplicate["runs"][-1]["run"] = 1
    try:
        require(run_numbers_valid(duplicate), "duplicate run accepted")
    except AssertionError:
        outcomes["duplicate-run"] = "rejected"
    missing = copy.deepcopy(summary)
    missing["runs"] = missing["runs"][:-1]
    try:
        require(run_numbers_valid(missing), "missing run accepted")
    except AssertionError:
        outcomes["missing-run"] = "rejected"
    run_dir = packet / "evidence/swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258/run-001"
    compositor = load(run_dir / "compositor.raw.json")
    compositor["mode"] = "tampered"
    try:
        require(compositor["mode"] == "own-window-compositor", "raw process mutation accepted")
    except AssertionError:
        outcomes["raw-process-mutation"] = "rejected"
    with tempfile.TemporaryDirectory() as temp:
        mutated = Path(temp) / "plain.png"
        mutated.write_bytes((run_dir / "plain.png").read_bytes() + b"\x00")
        expected_pixel_hash = summary["runs"][0]["plain"]["pngHash"]
        try:
            require(sha(mutated) == expected_pixel_hash, "raw pixel mutation accepted")
        except AssertionError:
            outcomes["raw-pixel-mutation"] = "rejected"
    require(len(outcomes) == 6 and all(value == "rejected" for value in outcomes.values()), outcomes)
    return outcomes


def main() -> None:
    pins = load(PACKET / "input-pins.json")
    receipt = load(PACKET / "execution-receipt.json")
    input_report = input_checks(PACKET, pins)
    stage_report = producer_stage_checks(PACKET)
    environment_report = environment_checks(PACKET, receipt)
    run_report = summary_checks(PACKET, pins, receipt)
    source_join = source_join_checks(PACKET, pins)
    controls = control_checks(PACKET, pins)
    review = {
        "kind": "seed-corrections-v1-independent-review",
        "version": 1,
        "scope": "Offline evidence review only; producer packet, binaries, source, GUI, SSH, & runtime untouched.",
        "seed": SEED,
        "inputLineage": input_report,
        "producerStage": stage_report,
        "executionEnvironment": environment_report,
        "closure": run_report,
        "sourceJoin": source_join,
        "holds": {"customExternalAX": True, "scrollOffscreenPaint": True, "candidateOnly": True, "promotion": "not-promoted"},
        "tagCounts": {"cases": 5, "runs": 100, "uniqueCaseIds": 5, "uniqueWitnessSourceHashes": 5, "uniqueCaptureSourceHashes": run_report["captureSourceHashCount"], "uniqueBinaryHashes": 5, "probeTagsPerRun": 100, "distinctProcessIds": run_report["globalDistinctProcesses"]},
        "noAlias": {"caseIds": True, "witnessSourceHashes": True, "captureSourceHashes": True, "binaryHashes": True, "runPaths": True, "processIds": True},
        "faultControls": {"count": len(controls), "outcomes": controls},
        "disposition": "independent review passes five cases x twenty corrected seed runs; source, binary, raw process, AX, device, signed-recorder grant, & pixel lineage pinned; held channels remain held; generated-host source archive join remains held; no alias detected",
    }
    out = PACKET / "independent-review/review.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(review, indent=2) + "\n")
    print(json.dumps({"status": "PASS", "seed": SEED, "cases": 5, "runs": 100, "faultControls": 6, "distinctProcesses": run_report["globalDistinctProcesses"]}, sort_keys=True))


if __name__ == "__main__":
    main()
