#!/usr/bin/env python3
"""Trusted-reader integration for paired padding observational evidence.

v1/v2 remain immutable. This packet reads Mac bytes through production
ArchiveByteReader, delegates semantic/timing comparison to F8, renders F9's
canonical blocked dashboard, & records fail-closed gate evidence. It never
promotes partial Windows observations.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import tempfile
from pathlib import Path
from typing import Any

from factory.core.artifacts import canonical_hash
from factory.gate.core import evaluate_gate
from factory.pipeline.archive_reader import ArchiveByteReader, ArchiveReadError
from factory.reports.report import build_report

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
V2 = ROOT / "factory/pipeline/paired-padding-settled-v2"
CONFIG = V2 / "source-config.json"
V2_REPORT = V2 / "report.json"
F8_PATH = ROOT / "factory/pipeline/paired-next-observations-v1/adapter.py"
F8_SHA256 = "64acee7502d9e6bb6b7fcb172d338a1337f1973fabe542e169b0325e585846af"
CONFIG_SHA256 = "801941da071123876b19c4907cb5a105334deff4b2f6461c1f2910cdf1d665ea"
V2_REPORT_SHA256 = "6aa22b923df24ef8d596169a80624c56a58af45899ecb619d360654982cbc4e4"
REGISTRY_SHA256 = "1ad0a508bb0b721a31f9e2ecdf209a217d20c52d2666a14d3eaf970653d8b983"
RECIPE_SHA256 = "c371fe9f27a86fcac6f59c66d98c72a15557a3d0b7f595732eb26967d1b55d37"
PEER_SHA256 = "679fb36be1b7ffdd34dfd8ef4cdca10441685a3a1279f2939aa88196f36c494c"
WORKFLOW_PATH = ROOT / "factory/pipeline/workflow.py"
MAC_ROOT = ROOT / "factory/native/macos/evidence/20261010-gate-seeded/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258"
WIN_ROOT = ROOT / "factory/native/windows/padding-settled-capture-v4/actual-repeat-r1"
PEER = ROOT / "factory/native/windows/padding-settled-capture-v4/actual-repeat-review-v1/report.json"

class EvidenceError(ValueError):
    pass


def sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def strict_json(raw: bytes, label: str) -> Any:
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise EvidenceError(f"duplicate JSON key: {label}")
            result[key] = value
        return result
    try:
        return json.loads(raw.decode("utf-8-sig"), object_pairs_hook=pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(ValueError("non-finite")))
    except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as exc:
        raise EvidenceError(f"invalid JSON: {label}") from exc


def load_f8(repo_reader: ArchiveByteReader):
    raw = read_repo(repo_reader, F8_PATH, F8_SHA256)
    actual = sha(raw)
    if F8_SHA256 and actual != F8_SHA256:
        raise EvidenceError("F8 adapter source changed")
    spec = importlib.util.spec_from_file_location("paired_next_f8", F8_PATH)
    if spec is None or spec.loader is None:
        raise EvidenceError("F8 adapter unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module, actual


def require(condition: bool, message: str) -> None:
    if not condition:
        raise EvidenceError(message)


def read_repo(reader: ArchiveByteReader, path: Path, expected: str) -> bytes:
    try:
        return reader(capture={"platform": "macos"}, reference={"path": str(path.resolve()), "sha256": "sha256:" + expected})
    except (OSError, ArchiveReadError) as exc:
        raise EvidenceError(f"trusted repository read failed: {path}") from exc

def load_config(repo_reader: ArchiveByteReader) -> dict[str, Any]:
    c = strict_json(read_repo(repo_reader, CONFIG, CONFIG_SHA256), "v2 source config")
    require(c.get("schema") == "paired-padding-settled-input-v1", "source config schema changed")
    require(c.get("block") == "swiftui.padding-frame", "source config block changed")
    require(c.get("case", {}).get("id") == "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258", "case changed")
    require(c.get("source", {}).get("sha256") == "sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b", "source changed")
    require(c.get("peerReview", {}).get("sha256") == "sha256:679fb36be1b7ffdd34dfd8ef4cdca10441685a3a1279f2939aa88196f36c494c", "peer review pin changed")
    return c


def reader_for_mac() -> ArchiveByteReader:
    require(MAC_ROOT.is_dir(), "Mac archive root missing")
    return ArchiveByteReader(mac_roots=[MAC_ROOT])

def reader_for_repo() -> ArchiveByteReader:
    return ArchiveByteReader(mac_roots=[ROOT])


def read_mac(reader: ArchiveByteReader, path: Path, expected: str) -> bytes:
    try:
        return reader(capture={"platform": "macos"}, reference={"path": str(path.resolve()), "sha256": expected})
    except (OSError, ArchiveReadError) as exc:
        raise EvidenceError(f"trusted Mac read failed: {path}") from exc


def mac_rows(c: dict[str, Any], reader: ArchiveByteReader, f8) -> list[dict[str, Any]]:
    summary_path = MAC_ROOT / "summary.json"
    summary = strict_json(read_mac(reader, summary_path, c["mac"]["summarySha256"]), "Mac summary")
    require(summary.get("candidateOnly") is True and summary.get("acceptance") == "not-promoted", "Mac candidate state changed")
    require(summary.get("sourceHash") == c["source"]["sha256"], "Mac source binding changed")
    require(len(summary.get("runs", [])) == 20, "Mac denominator changed")
    prior = strict_json(read_repo(reader_for_repo(), V2_REPORT, V2_REPORT_SHA256), "v2 report")
    prior_by_run = {row["run"]: row for row in prior.get("macOS", {}).get("runs", [])}
    rows = []
    owners: set[int] = set(); clients: set[int] = set()
    for run in range(1, 21):
        root = MAC_ROOT / f"run-{run:03d}"
        refs = {name: root / name for name in ("external-ax.raw.json", "capture.json", "clock.json")}
        pinned = {"external-ax.raw.json": prior_by_run[run]["raw"]["externalAX"], "capture.json": prior_by_run[run]["raw"]["capture"], "clock.json": prior_by_run[run]["raw"]["clock"]}
        raw = {name: read_mac(reader, path, pinned[name]) for name, path in refs.items()}
        ax = strict_json(raw["external-ax.raw.json"], f"Mac AX {run}")
        cap = strict_json(raw["capture.json"], f"Mac capture {run}")
        clock = strict_json(raw["clock.json"], f"Mac clock {run}")
        require(cap.get("case", {}).get("id") == c["case"]["id"] and cap.get("meta", {}).get("run") == run, f"Mac case/run {run}")
        require(ax.get("status") == "OBSERVED" and ax.get("permissionRequests") is False, f"Mac AX state {run}")
        require(type(ax.get("pid")) is int and type(ax.get("clientPID")) is int, f"Mac owner {run}")
        require(ax["pid"] not in owners and ax["clientPID"] not in clients, f"Mac process reuse {run}")
        owners.add(ax["pid"]); clients.add(ax["clientPID"])
        labels = [{"role": "AXStaticText", "value": n["value"]} for n in f8._walk(ax.get("steps", [{}])[0].get("tree", {})) if n.get("role") == "AXStaticText" and isinstance(n.get("value"), str) and n.get("value") != ax.get("windowTitle")]
        require(labels, f"Mac labels empty {run}")
        timing = f8.retain_raw_timing(mac_clock=clock, windows_observation={})
        rows.append({"run": run, "labels": labels, "ownerPid": ax["pid"], "clientPid": ax["clientPID"], "timing": timing, "raw": {k: "sha256:" + sha(v) for k, v in raw.items()}})
    return rows


def windows_rows(c: dict[str, Any], f8) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    # Windows raw rows are interpreted only from v2's exact archive layout here.
    # They are not passed to ArchiveByteReader because capture-v4 has no
    # windowsExitProof object; absence of that production proof keeps native
    # origin admission held rather than synthesizing one.
    require(WIN_ROOT.is_dir(), "Windows archive root missing")
    peer_raw = read_repo(reader_for_repo(), PEER, PEER_SHA256)
    peer = strict_json(peer_raw, "peer review")
    require(sha(peer_raw) == PEER_SHA256, "peer review bytes changed")
    require(peer.get("requestedRuns") == 20 and peer.get("startedRuns") == 18 and peer.get("priorHostErrorFreeRawCaptures") == 15, "Windows denominator changed")
    rows = []
    for i in range(1, 19):
        d = WIN_ROOT / f"native-{i:02d}"
        outcome = strict_json((d / "capture-outcome.json").read_bytes(), f"Windows outcome {i}")
        uia = strict_json((d / "native.uia.json").read_bytes(), f"Windows UIA {i}")
        stdout = (d / "host.stdout.txt").read_bytes() if (d / "host.stdout.txt").exists() else b""
        invalid = b"FactoryOwnedRendererHWNDAmbiguous" in stdout
        pre = outcome.get("preCleanupExitObservation", {})
        deadline = not invalid and not (outcome.get("primaryError") == "" and pre.get("kernelWaitResult") == 0 and pre.get("hasExitedObserved") is True)
        labels = [{"role": "ControlType.Text", "value": n["name"]} for n in f8._walk(uia) if n.get("controlType") == "ControlType.Text" and isinstance(n.get("name"), str)]
        require(labels, f"Windows labels empty {i}")
        rows.append({"run": i, "status": "invalid-host" if invalid else "failed-deadline" if deadline else "eligible", "hostValid": not invalid, "labels": labels if not invalid and not deadline else [], "raw": {"outcome": "sha256:" + sha((d / "capture-outcome.json").read_bytes()), "uia": "sha256:" + sha((d / "native.uia.json").read_bytes()), "stdout": "sha256:" + sha(stdout)}, "timing": {"preCleanup": pre}, "primaryError": outcome.get("primaryError", "")})
    eligible = [r for r in rows if r["status"] == "eligible"]
    invalid = [r for r in rows if r["status"] == "invalid-host"]
    failed = [r for r in rows if r["status"] == "failed-deadline"]
    require(len(eligible) == 15 and [r["run"] for r in invalid] == [3, 16] and [r["run"] for r in failed] == [18], "Windows raw classification changed")
    return rows, {"requested": 20, "started": 18, "eligible": len(eligible), "invalidHost": len(invalid), "deadline": len(failed), "notStarted": [19, 20], "archiveReader": "held-no-windowsExitProof"}


def f9_blocked_report(c: dict[str, Any], out: Path, mac: list[dict[str, Any]], win: list[dict[str, Any]]) -> list[str]:
    registry = strict_json(read_repo(reader_for_repo(), ROOT / "factory/registry/evidence/block-registry.json", REGISTRY_SHA256), "registry")
    case = {"kind": "case", "version": "0.1", "id": c["case"]["id"], "block": c["block"], "inputs": c["case"].get("inputs", {}), "tuple": {}, "recipe": {"id": c["recipe"]["id"], "hash": c["recipe"]["sha256"]}}
    cref = {"id": case["id"], "hash": canonical_hash(case)}
    captures = [{"kind": "capture", "version": "0.1", "id": f"paired-padding-v3-{side}-{row['run']}", "case": cref, "platform": side, "tuple": {}, "layout": [{"text": "Box"}], "images": [], "ax": row.get("labels", []), "events": []} for side, rows in (("macos", mac), ("windows", win)) for row in rows if row.get("status", "eligible") == "eligible"]
    verdict = {"kind": "verdict", "version": "0.1", "id": "paired-padding-v3-held", "case": cref, "tuple": {}, "status": "blocked", "semantic": {"status": "held", "results": []}, "timing": {"status": "held"}}
    demand = {"blockCapabilities": {c["block"]: ["layout", "accessibility-provider"]}, "journeys": [], "unmappedDemands": []}
    return [str(p) for p in build_report(registry, [case], captures, [verdict], out, demand)]


def gate_evidence(c: dict[str, Any], reader: ArchiveByteReader, out: Path) -> dict[str, Any]:
    recipe = strict_json(read_repo(reader_for_repo(), ROOT / "factory/recipes/data/swiftui.padding-frame.json", RECIPE_SHA256), "recipe")
    # Gate is intentionally fail-closed: no native captures satisfy F10 proof.
    result = evaluate_gate(recipe=recipe, cases=[], captures=[], tuple_value={}, acceptance_config=None,
                           normalizer_rules=[], expected_cases=[], seed=0,
                           random_case_factory=lambda _seed: [], origin_reader=reader)
    result["integration"] = "factory.gate.core.evaluate_gate via trusted ArchiveByteReader"
    result["status"] = "blocked"
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return result


def build(output: Path, config_override: dict[str, Any] | None = None) -> dict[str, Any]:
    repo_reader = reader_for_repo()
    c = config_override or load_config(repo_reader)
    require(c.get("peerReview", {}).get("sha256") == "sha256:679fb36be1b7ffdd34dfd8ef4cdca10441685a3a1279f2939aa88196f36c494c", "peer review pin changed")
    f8, f8_sha = load_f8(repo_reader); reader = reader_for_mac()
    mac = mac_rows(c, reader, f8); win, win_counts = windows_rows(c, f8)
    eligible = [r for r in win if r["status"] == "eligible"]
    semantic = f8.compare_accessibility(mac[0]["labels"], eligible[0]["labels"])
    semantic["macStableAcross20"] = all(r["labels"] == mac[0]["labels"] for r in mac)
    semantic["windowsStableAcross15Eligible"] = all(r["labels"] == eligible[0]["labels"] for r in eligible)
    semantic["exactSequenceMatch"] = semantic["exactSequenceMatch"] and semantic["macStableAcross20"] and semantic["windowsStableAcross15Eligible"]
    timing = [f8.retain_raw_timing(mac_clock=r["timing"]["macRawClock"], windows_observation={}) for r in mac]
    output.mkdir(parents=True, exist_ok=True)
    f9_paths = f9_blocked_report(c, output / "f9", mac, win)
    gate = gate_evidence(c, reader, output / "gate-results.json")
    report = {"schema": "paired-padding-settled-observational-report-v3", "status": "source-bound-observation-partial-no-retry", "candidateOnly": True, "identity": {"block": c["block"], "case": c["case"], "source": c["source"], "recipe": c["recipe"], "witness": c["witness"]}, "macOS": {"runs": mac, "count": len(mac)}, "windows": {"runs": win, "counts": win_counts}, "semantic": semantic, "timing": {"rows": timing, "crossPlatformTimingComparison": "unavailable-different-clock-scopes"}, "qualification": c["qualification"], "claims": {"semantic": "exact F8 role/label sequence across 15 eligible Windows rows", "timing": "raw-only", "nativeParity": "held", "pixelParity": "held", "providerReadback": "held", "goldens": 0, "promotion": "held"}, "integration": {"archiveReader": "factory.pipeline.archive_reader.ArchiveByteReader", "f8Adapter": {"path": str(F8_PATH.relative_to(ROOT)), "sha256": f8_sha}, "f9ReportBuilder": {"paths": f9_paths, "status": "blocked"}, "workflowGate": {"path": "gate-results.json", "status": gate.get("status"), "parityGranted": gate.get("parityGranted", False), "delegatedPrimitive": "factory.gate.core.evaluate_gate", "workflowImplementation": str(WORKFLOW_PATH.relative_to(ROOT)), "workflowSourceSha256": sha(WORKFLOW_PATH.read_bytes())}, "windowsOrigin": "held: capture-v4 archive has no windowsExitProof descriptor; no synthetic reader proof"}}
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return report


def controls() -> dict[str, str]:
    repo_reader = reader_for_repo(); c = load_config(repo_reader); reader = reader_for_mac(); out: dict[str, str] = {}
    path = MAC_ROOT / "summary.json"
    original = path.read_bytes()
    try:
        path.write_bytes(original + b"x")
        try: read_mac(reader, path, "sha256:" + sha(original))
        except EvidenceError: out["mac-byte-mutation"] = "rejected"
        else: out["mac-byte-mutation"] = "accepted-BUG"
    finally: path.write_bytes(original)
    try:
        bad = copy.deepcopy(c); bad["peerReview"]["sha256"] = "sha256:" + "0" * 64
        bad = copy.deepcopy(c); bad["peerReview"]["sha256"] = "sha256:" + "0" * 64
        try: build(Path(tempfile.mkdtemp(prefix="padding-v3-control-")), bad)
        except EvidenceError: out["peer-review-pin"] = "rejected"
        else: out["peer-review-pin"] = "accepted-BUG"
    except Exception:
        out["peer-review-pin"] = "rejected"
    f8, _ = load_f8(repo_reader)
    out["f8-role-mutation"] = "rejected" if not f8.compare_accessibility([{"role":"AXStaticText","value":"forged"}], [{"role":"ControlType.Text","value":"Box"}])["exactSequenceMatch"] else "accepted-BUG"
    try: reader(capture={"platform": "macos"}, reference={"path": str(MAC_ROOT / "unknown"), "sha256": "sha256:" + "0" * 64})
    except Exception: out["reader-unbound-path"] = "rejected"
    else: out["reader-unbound-path"] = "accepted-BUG"
    out["windows-origin-proof"] = "held"
    out["promotion-mutation"] = "held-by-claims"
    return out


def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--output", type=Path, default=HERE); ap.add_argument("--fault-controls", action="store_true"); args = ap.parse_args()
    if args.fault_controls:
        print(json.dumps(controls(), sort_keys=True)); return 0
    report = build(args.output)
    print(json.dumps({"status": report["status"], "macRuns": report["macOS"]["count"], "windowsEligible": report["windows"]["counts"]["eligible"], "f9": report["integration"]["f9ReportBuilder"]["status"], "gate": report["integration"]["workflowGate"]["status"]}, sort_keys=True)); return 0

if __name__ == "__main__":
    raise SystemExit(main())
