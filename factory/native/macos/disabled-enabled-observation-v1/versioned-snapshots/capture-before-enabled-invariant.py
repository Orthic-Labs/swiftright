from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
EVIDENCE = HERE / "evidence"
CACHE = Path("/Users/adrdsouza/Library/Caches/SwiftRightFactory/disabled-enabled-observation-v1")
CLIENT = CACHE / "ax-enabled-client"
HOST = Path("/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/swiftui.disabled.recipe_case_f113195a59446fc4/capture-host")
CASE_ID = "swiftui.disabled.recipe/case/f113195a59446fc4"
SOURCE = ROOT / "factory/pipeline/probes/swiftui.disabled.recipe_case_f113195a59446fc4.swift"
PROBE_MANIFEST = ROOT / "factory/pipeline/probes/swiftui.disabled.recipe_case_f113195a59446fc4.manifest.json"
CASE_FILE = ROOT / "factory/pipeline/cases/swiftui.disabled.recipe--case--f113195a59446fc4.json"
PRIOR_SUMMARY = ROOT / "factory/native/macos/evidence/20261010-primary-next-five/swiftui.disabled.recipe_case_f113195a59446fc4/summary.json"
PRIOR_RUNS = PRIOR_SUMMARY.parent
EXPECTED_SOURCE = "68eed62f6ef06ecec579a0e36cdc44a612a559a8329fe6dbd91a700c5d90c005"
EXPECTED_PROBE_MANIFEST = "5e155ed85464617856bff8796c548a4bca943b0a4e1176425a6f8f3e63a4b27e"
EXPECTED_CASE = "d6a88082e0818e46e4e1ea5e6d45af6edbce63c86fc6b847704c38ad3db9aa99"
EXPECTED_HOST = "d555759e14425b5c38751935ed54bc18836bbbd8703362f85e33661e99d0c7d6"
EXPECTED_CLIENT_SOURCE = "0ba89941a66465fdfd3f6c7f8b90d4bf049dcbb561a2d2cec846cace349eea51"
EXPECTED_CLIENT_BINARY = "a51b8b7838bef54847368084e6959d85cc5dd628a276fd9bbf1cf1536a5c5461"


class CaptureValidationError(ValueError):
    pass


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], timeout: int = 20) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=timeout, check=False)


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + "\n", encoding="utf-8")


def validate_raw_observation(raw: dict, owner: dict) -> dict:
    if raw.get("kind") != "fresh-external-ax-enabled-observation" or raw.get("status") != "OBSERVED":
        raise CaptureValidationError("AX observation was not observed")
    if raw.get("permissionRequests") is not False:
        raise CaptureValidationError("permission request flag is not false")
    for key, expected in (
        ("ownerPID", owner["pid"]), ("pid", owner["pid"]), ("ownerPath", str(HOST)),
        ("ownerBinarySha256", "sha256:" + EXPECTED_HOST), ("ownerStartedAt", owner["processStartFromPs"]),
        ("windowTitle", owner["windowTitle"]), ("caseId", CASE_ID), ("caseSha256", "sha256:" + EXPECTED_CASE),
        ("sourceSha256", "sha256:" + EXPECTED_SOURCE),
    ):
        if raw.get(key) != expected:
            raise CaptureValidationError(f"observation owner/source binding mismatch: {key}")
    buttons = []

    def walk(value):
        if isinstance(value, dict):
            if value.get("role") == "AXButton" and value.get("label") == "Continue":
                buttons.append(value)
            for child in value.values():
                walk(child)
        elif isinstance(value, list):
            for child in value:
                walk(child)

    walk(raw.get("steps", []))
    if len(buttons) != 1:
        raise CaptureValidationError("Continue AXButton is not unique")
    attribute = buttons[0].get("enabledAttribute")
    if not isinstance(attribute, dict) or attribute.get("attribute") != "AXEnabled" or attribute.get("axError") != 0 or attribute.get("status") != "observed-bool" or type(attribute.get("value")) is not bool:
        raise CaptureValidationError("AXEnabled was not returned as a raw boolean")
    return {"buttonCount": 1, "enabledAttribute": attribute}


def main() -> int:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    if sha(SOURCE) != EXPECTED_SOURCE or sha(PROBE_MANIFEST) != EXPECTED_PROBE_MANIFEST or sha(CASE_FILE) != EXPECTED_CASE:
        raise SystemExit("source/probe/case pin mismatch; no capture launched")
    probe = json.loads(PROBE_MANIFEST.read_text())
    if probe["sourceHash"] != "sha256:" + EXPECTED_SOURCE or probe["case"]["id"] != CASE_ID or probe["case"]["hash"] != "sha256:" + EXPECTED_CASE:
        raise SystemExit("probe manifest identity mismatch; no capture launched")
    summary = json.loads(PRIOR_SUMMARY.read_text())
    if summary["sourceHash"] != "sha256:" + EXPECTED_SOURCE or summary["case"] != probe["case"]:
        raise SystemExit("prior capture summary does not bind same source/case")
    adapter = Path(summary["executionRoot"]) / "CaptureHost.swift"
    if "sha256:" + sha(adapter) != summary["compiledAdapterHash"] or sha(HOST) != EXPECTED_HOST or summary["binaryHash"] != "sha256:" + EXPECTED_HOST:
        raise SystemExit("existing host binary/source provenance mismatch; no capture launched")
    old = []
    for index in range(1, 21):
        row = json.loads((PRIOR_RUNS / f"run-{index:03d}/owned-window-process.json").read_text())
        if row.get("binaryHash") != "sha256:" + EXPECTED_HOST or row.get("executable") != str(HOST):
            raise SystemExit(f"prior run {index} uses a different host binary")
        old.append(row)
    source_on_cache = CACHE / "AXEnabledClient.swift"
    if sha(HERE / "AXEnabledClient.swift") != EXPECTED_CLIENT_SOURCE or sha(source_on_cache) != EXPECTED_CLIENT_SOURCE or sha(CLIENT) != EXPECTED_CLIENT_BINARY:
        raise SystemExit("AX client source/binary pin mismatch; no capture launched")
    preflight = run([str(CLIENT), "--preflight"])
    (EVIDENCE / "preflight-run.stdout.txt").write_text(preflight.stdout, encoding="utf-8")
    (EVIDENCE / "preflight-run.stderr.txt").write_text(preflight.stderr, encoding="utf-8")
    if preflight.returncode != 0:
        raise SystemExit("AX client preflight failed; no capture launched")
    preflight_value = json.loads(preflight.stdout)
    if preflight_value.get("axTrusted") is not True or preflight_value.get("permissionRequests") is not False:
        write_json(EVIDENCE / "preflight-result.json", preflight_value)
        raise SystemExit("AX trust not available without prompt; no capture launched")
    write_json(EVIDENCE / "preflight-result.json", preflight_value)

    results = []
    for index in range(1, 21):
        run_id = f"run-{index:03d}"
        out = EVIDENCE / run_id
        out.mkdir(exist_ok=False)
        title = "SwiftRightFactory-" + CASE_ID
        events = out / "owned-window-events.jsonl"
        log_path = out / "owned-window.stdout.txt"
        started_at = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        with log_path.open("w", encoding="utf-8") as log:
            process = subprocess.Popen(
                [str(HOST), "--window", "--case", CASE_ID, "--scheme", "light", "--events", str(events)],
                stdin=subprocess.PIPE, stdout=log, stderr=subprocess.STDOUT, text=True, start_new_session=True,
            )
            ps = run(["/bin/ps", "-o", "lstart=", "-p", str(process.pid)])
            process_started = ps.stdout.strip() if ps.returncode == 0 else "unavailable"
            owner = {
                "pid": process.pid, "executable": str(HOST), "binarySha256": EXPECTED_HOST,
                "startedAtLaunchUtc": started_at, "processStartFromPs": process_started,
                "windowTitle": title, "caseId": CASE_ID, "caseSha256": EXPECTED_CASE,
                "sourceSha256": EXPECTED_SOURCE, "probeManifestSha256": EXPECTED_PROBE_MANIFEST,
                "unchangedPriorCaptureHost": True,
            }
            write_json(out / "owner-process.json", owner)
            ax_command = [
                str(CLIENT), "--pid", str(process.pid), "--owner-path", str(HOST), "--owner-hash", "sha256:" + EXPECTED_HOST,
                "--owner-started-at", process_started, "--window-title", title,
                "--case-id", CASE_ID, "--case-hash", "sha256:" + EXPECTED_CASE, "--source-hash", "sha256:" + EXPECTED_SOURCE,
            ]
            ax = run(ax_command, timeout=15)
            (out / "external-ax.stdout.txt").write_text(ax.stdout, encoding="utf-8")
            (out / "external-ax.stderr.txt").write_text(ax.stderr, encoding="utf-8")
            try:
                raw = json.loads(ax.stdout)
            except json.JSONDecodeError:
                raw = {"status": "INVALID_JSON", "stdout": ax.stdout}
            write_json(out / "external-ax.raw.json", raw)
            write_json(out / "ax-invocation.json", {
                "command": ax_command, "exitCode": ax.returncode, "clientPid": raw.get("clientPID"),
                "ownerPid": process.pid, "ownerStartedAt": process_started,
                "clientSha256": EXPECTED_CLIENT_BINARY, "clientSourceSha256": EXPECTED_CLIENT_SOURCE,
                "caseId": CASE_ID, "caseSha256": EXPECTED_CASE, "sourceSha256": EXPECTED_SOURCE,
                "noInputInvoked": True, "permissionRequests": False,
            })
            try:
                process.communicate(input='{"step":"quit"}\n', timeout=3)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=3)
            exit_code = process.returncode
        validated = None
        try:
            validated = validate_raw_observation(raw, owner)
        except CaptureValidationError:
            pass
        result = {
            "run": index, "status": raw.get("status"), "buttonCount": validated["buttonCount"] if validated else 0,
            "enabledAttribute": validated["enabledAttribute"] if validated else None,
            "ownerPid": process.pid, "ownerProcessStart": process_started,
            "ownerExitCode": exit_code, "rawPath": str((out / "external-ax.raw.json").relative_to(ROOT)),
            "rawSha256": sha(out / "external-ax.raw.json"),
        }
        write_json(out / "result.json", result)
        results.append(result)

    expected_enabled = {"attribute": "AXEnabled", "axError": 0, "status": "observed-bool", "value": True}
    report = {
        "kind": "disabled-enabled-ax-observation-v1", "status": "observed" if all(
            r["status"] == "OBSERVED" and r["buttonCount"] == 1 and r["enabledAttribute"] == expected_enabled
            for r in results
        ) else "partial-or-held",
        "caseId": CASE_ID, "caseSha256": EXPECTED_CASE, "sourceSha256": EXPECTED_SOURCE,
        "probeManifestSha256": EXPECTED_PROBE_MANIFEST, "originalCaptureSummary": str(PRIOR_SUMMARY.relative_to(ROOT)),
        "originalCaptureSummarySha256": sha(PRIOR_SUMMARY), "originalRunCount": len(old),
        "existingCaptureHostPath": str(HOST), "existingCaptureHostSha256": EXPECTED_HOST,
        "AXClientSourceSha256": EXPECTED_CLIENT_SOURCE, "AXClientBinarySha256": EXPECTED_CLIENT_BINARY,
        "preflight": preflight_value, "newObservationCount": len(results),
        "observedEnabledTrueCount": sum(r["enabledAttribute"] == expected_enabled for r in results),
        "noInputInvoked": True, "permissionRequests": False, "results": results,
    }
    write_json(EVIDENCE / "report.json", report)
    print(json.dumps({"status": report["status"], "newObservationCount": report["newObservationCount"],
                      "observedEnabledTrueCount": report["observedEnabledTrueCount"]}, sort_keys=True))
    return 0 if report["status"] == "observed" else 2


if __name__ == "__main__":
    sys.exit(main())
