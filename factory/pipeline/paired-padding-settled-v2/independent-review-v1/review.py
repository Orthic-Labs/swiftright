#!/usr/bin/env python3
"""Independent read-only audit of paired-padding-settled-v2."""
from __future__ import annotations
import ast, hashlib, json, subprocess, sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
V2 = HERE.parent
ROOT = HERE.parents[3]

def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()

def j(p: Path):
    return json.loads(p.read_text(encoding="utf-8-sig"))

def need(ok: bool, msg: str):
    if not ok: raise AssertionError(msg)

def raw_path(kind: str, run: int, name: str) -> Path:
    if kind == "mac":
        d = ROOT / "factory/native/macos/evidence/20261010-gate-seeded/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258" / f"run-{run:03d}"
        return d / {"externalAX":"external-ax.raw.json", "capture":"capture.json", "clock":"clock.json", "instrumented":"instrumented.raw.json", "plain":"plain.raw.json"}[name]
    d = ROOT / "factory/native/windows/padding-settled-capture-v4/actual-repeat-r1" / f"native-{run:02d}"
    return d / {"observation":"../observation.json", "uia":"native.uia.json", "pixels":"native.pixels.json", "captureOutcome":"capture-outcome.json", "hostStdout":"host.stdout.txt", "hostStderr":"host.stderr.txt"}[name]

def check_hash_refs(row, kind, run):
    for name, ref in row.get("raw", {}).items():
        need(isinstance(ref, str) and ref.startswith("sha256:"), f"{kind}{run}: malformed {name} ref")
        p = raw_path(kind, run, name)
        need(p.exists(), f"{kind}{run}: missing {name} archive")
        need("sha256:" + sha(p) == ref, f"{kind}{run}: {name} hash mismatch")

def main() -> int:
    report_path, config_path, code_path = V2 / "report.json", V2 / "source-config.json", V2 / "report.py"
    report, config = j(report_path), j(config_path)
    need(report["schema"] == "paired-padding-settled-observational-report-v2", "schema")
    need(report["candidateOnly"] is True and report["status"] == "source-bound-observation-partial-no-retry", "candidate status")
    need(len(report["macOS"]["runs"]) == 20, "Mac raw attempts")
    win = report["windows"]
    need((win["expectedRuns"], win["attemptedRuns"], win["successfulRuns"], win["invalidHostRuns"], win["failedRuns"]) == (20,18,15,2,1), "Windows count tuple")
    need([x["run"] for x in win["invalidHostRows"]] == [3,16], "invalid host rows")
    need([x["run"] for x in win["failedRows"]] == [18], "deadline row")
    need(sorted([x["run"] for x in win["runs"]] + [x["run"] for x in win["invalidHostRows"]] + [x["run"] for x in win["failedRows"]]) == list(range(1,19)), "all 18 raw rows")
    need(win["completion"] == "partial-no-retry", "Windows completion")
    for row in report["macOS"]["runs"]: check_hash_refs(row, "mac", row["run"])
    for row in win["runs"] + win["invalidHostRows"] + win["failedRows"]: check_hash_refs(row, "win", row["run"])
    # Archive directory admission: exact native attempt set, with raw outcome/UI/pixels per attempt.
    wr = ROOT / "factory/native/windows/padding-settled-capture-v4/actual-repeat-r1"
    native = sorted(p.name for p in wr.glob("native-[0-9][0-9]") if p.is_dir())
    need(native == [f"native-{i:02d}" for i in range(1,19)], "Windows archive attempt dirs")
    for i in range(1,19):
        for n in ("capture-outcome.json", "native.uia.json", "native.pixels.json"):
            need((wr / f"native-{i:02d}" / n).exists(), f"Windows {i} missing {n}")
    # Identity pins.
    ident = report["identity"]
    for section in ("case", "source", "recipe", "witness"):
        need(ident[section] == config[section], f"identity {section}")
    need(config["mac"]["runs"] == 20 and config["windows"]["runs"] == 20, "config expected runs")
    need(config["peerReview"]["sha256"] == "sha256:679fb36be1b7ffdd34dfd8ef4cdca10441685a3a1279f2939aa88196f36c494c", "peer hash pin")
    peer = ROOT / config["peerReview"]["path"]
    need(sha(peer) == config["peerReview"]["sha256"].removeprefix("sha256:"), "peer bytes")
    pd = j(peer)
    need((pd["requestedRuns"], pd["startedRuns"], pd["priorHostErrorFreeRawCaptures"], pd["priorHostErrorRuns"], pd["failedRun"], pd["notStarted"]) == (20,18,15,[3,16],18,[19,20]), "peer counts")
    # Frozen report replay: producer reads only archived paths, writes only review-owned output.
    replay = HERE / "producer-replay.json"
    cmd = [sys.executable, str(code_path), "--windows-root", str(wr), "--output", str(replay)]
    proc = subprocess.run(cmd, cwd=ROOT, env={**__import__('os').environ, "PYTHONDONTWRITEBYTECODE":"1"}, capture_output=True, text=True)
    need(proc.returncode == 0, "producer replay failed: " + proc.stderr)
    need(replay.read_bytes() == report_path.read_bytes(), "producer replay differs from frozen report")
    # No parity/timing overclaim.
    need(report["claims"]["nativeParity"] == "held" and report["claims"]["pixelParity"] == "held" and report["claims"]["providerReadback"] == "held" and report["claims"]["promotion"] == "held", "held qualification claims")
    need(report["semantic"]["qualification"] == "not-claimed", "semantic qualification")
    need(report["timing"]["crossPlatformTimingComparison"] == "unavailable-different-clock-scopes" and report["claims"]["timing"] == "raw-only", "timing restriction")
    # F8/F9/production reader integration audit. This is intentionally a hold.
    source = code_path.read_text()
    tree = ast.parse(source)
    imports = [ast.unparse(n) for n in tree.body if isinstance(n, (ast.Import, ast.ImportFrom))]
    need(all(not x.startswith("from factory") and not x.startswith("import factory") for x in imports), "report unexpectedly imports factory production code")
    need("ArchiveByteReader" not in source and "origin_reader" not in source and "compare_case" not in source and "build_report" not in source, "report unexpectedly calls production integration")
    f8 = ROOT / "factory/comparison/comparator.py"
    f9 = ROOT / "factory/reports/report.py"
    reader = ROOT / "factory/pipeline/archive_reader.py"
    need(f8.exists() and f9.exists() and reader.exists(), "integration targets missing")
    old_v1 = ROOT / "factory/pipeline/paired-padding-settled-v1/report.json"
    need(sha(old_v1) == "1610c1b9ca1b9c2487f4b501ed0a4580e75359085780fc66ea078a6e2da54ec7", "v1 failed report changed")
    findings = [
        "Raw admission counts pass: Mac20; Windows18 attempted, 15 eligible, runs3/16 invalid-host, run18 deadline; 19/20 not started.",
        "No invented parity or timing comparison: native/pixel/provider parity held, semantic qualification not claimed, cross-platform timing unavailable.",
        "Integration hold: report.py uses ad hoc direct Path.read_bytes/json.loads and custom output; it does not use F8 comparator, F9 report builder, workflow gate/evidence, or ArchiveByteReader origin-reader callback.",
        "Production reader must consume explicit archive-bound references before F10 admission; current report cannot authorize gate qualification."
    ]
    result = {
        "schema":"paired-padding-settled-independent-review-v1",
        "status":"PASS_WITH_INTEGRATION_HOLD",
        "stage":{"v2ReportSha256":"sha256:"+sha(report_path),"v2CodeSha256":"sha256:"+sha(code_path),"v2ConfigSha256":"sha256:"+sha(config_path),"v1FailedReportSha256":"sha256:"+sha(old_v1)},
        "counts":{"macRawAttempts":20,"windowsExpected":20,"windowsRawAttempts":18,"windowsEligible":15,"windowsInvalidHost":[3,16],"windowsDeadline":[18],"windowsNotStarted":[19,20]},
        "checks":{"rawHashJoins":"pass","sourceCaseRecipeWitness":"pass","peerReviewCounts":"pass","producerReplayByteExact":"pass","heldClaims":"pass","v1Preserved":"pass"},
        "integration":{"f8ComparatorUsed":False,"f9ReportBuilderUsed":False,"workflowUsed":False,"productionArchiveByteReaderUsed":False,"mode":"ad-hoc-direct-file-reader","status":"hold","required":"wire explicit ArchiveByteReader/origin_reader through workflow & canonical F8/F9 joins before admission"},
        "findings":findings,
    }
    (HERE/"review.json").write_text(json.dumps(result, indent=2, sort_keys=True)+"\n")
    print(json.dumps({"status":result["status"],"counts":result["counts"],"replay":"byte-exact","integration":"hold"}, sort_keys=True))
    return 0

if __name__ == "__main__":
    try: raise SystemExit(main())
    except Exception as exc:
        print(f"REVIEW FAILED: {exc}", file=sys.stderr)
        raise SystemExit(1)
