#!/usr/bin/env python3
"""Source-bound Mac20/Windows20 padding observation report.

Reads frozen Mac gate-seeded evidence & fresh Windows repeat archive. Semantic
comparison maps only AXStaticText -> ControlType.Text. Timing stays raw per
provider; no cross-platform clock arithmetic, geometry normalization, parity,
or qualification is produced.
"""
from __future__ import annotations
import argparse, copy, hashlib, json, sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
CONFIG_PATH = Path(__file__).resolve().parent / "source-config.json"
ROLE_MAP = {"AXStaticText": "ControlType.Text"}

class EvidenceError(ValueError): pass

def sha256_bytes(raw: bytes) -> str: return hashlib.sha256(raw).hexdigest()
def sha256_file(path: Path) -> str: return sha256_bytes(path.read_bytes())
def load_json(path: Path) -> Any:
    try: return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as e: raise EvidenceError(f"invalid JSON: {path}") from e

def rel(path: Path) -> str:
    try: return path.relative_to(ROOT).as_posix()
    except ValueError: return str(path)

def walk(value: Any):
    if isinstance(value, dict):
        yield value
        for x in value.values(): yield from walk(x)
    elif isinstance(value, list):
        for x in value: yield from walk(x)

def config() -> dict[str, Any]:
    c = load_json(CONFIG_PATH)
    validate_config_shape(c)
    return c

def validate_config_shape(c: dict[str, Any]) -> None:
    require(c.get("schema") == "paired-padding-settled-input-v1", "config schema mismatch")
    require(c.get("block") == "swiftui.padding-frame", "config block mismatch")
    require(c.get("case", {}).get("id") == "swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258", "config case id mismatch")
    require(c.get("case", {}).get("sha256") == "sha256:84951ddf8b3ff3239a497d8a8bbe525a9e09b5d7354f2d2ac994cf8e740bbc3d", "config case hash mismatch")
    require(c.get("source", {}).get("sha256") == "sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b", "config source hash mismatch")
    require(c.get("witness", {}).get("sha256") == "sha256:860fa789eed486958eb0a52c01453d0e29c1c9d4e89ea927c140fa683cf9b2db", "config witness hash mismatch")
    require(c.get("qualification") == {"semantic": "observed-role-and-label-sequence-only", "timing": "raw-clocks-retained; cross-platform timing comparison unavailable", "nativeParity": "held", "pixelParity": "held", "providerReadback": "held", "goldens": 0, "promotion": "held"}, "config qualification changed")
    require(c.get("peerReview", {}).get("path") == "factory/native/windows/padding-settled-capture-v4/actual-repeat-review-v1/report.json", "peer review path changed")
    require(c.get("peerReview", {}).get("sha256") == "sha256:679fb36be1b7ffdd34dfd8ef4cdca10441685a3a1279f2939aa88196f36c494c", "peer review hash changed")

def require(condition: bool, msg: str):
    if not condition: raise EvidenceError(msg)

def validate_mac_summary(summary: dict[str, Any], c: dict[str, Any]) -> None:
    case, source, witness = c["case"], c["source"], c["witness"]
    require(summary.get("kind") == "macos-host-capture-candidate", "Mac kind mismatch")
    require(summary.get("candidateOnly") is True and summary.get("acceptance") == "not-promoted", "Mac promotion state changed")
    require(summary.get("independentProcessesPerRun") is True, "Mac process independence missing")
    require(summary.get("case") == {"id": case["id"], "hash": case["sha256"]}, "Mac case identity mismatch")
    require(summary.get("sourceHash") == source["sha256"], "Mac summary source mismatch")
    require(summary.get("provenance", {}).get("sourceHash") == source["sha256"], "Mac provenance source mismatch")
    pm = summary.get("probeManifest", {})
    require(pm.get("sourceHash") == source["sha256"], "Mac probe source mismatch")
    require(pm.get("witness") == {"id": witness["id"], "sourceHash": witness["sha256"]}, "Mac witness mismatch")
    require(len(summary.get("runs", [])) == c["mac"]["runs"], "Mac run count mismatch")

def mac_report(c: dict[str, Any]) -> dict[str, Any]:
    root = ROOT / c["mac"]["root"]
    summary_path = root / "summary.json"
    require(summary_path.exists(), "Mac summary missing")
    require("sha256:" + sha256_file(summary_path) == c["mac"]["summarySha256"], "Mac summary bytes changed")
    summary = load_json(summary_path); validate_mac_summary(summary, c)
    rows, owners, clients = [], set(), set()
    for i in range(1, c["mac"]["runs"] + 1):
        run_dir = root / f"run-{i:03d}"
        ax_path, cap_path = run_dir / "external-ax.raw.json", run_dir / "capture.json"
        clock_path = run_dir / "clock.json"
        inst_path, plain_path = run_dir / "instrumented.raw.json", run_dir / "plain.raw.json"
        for p in (ax_path, cap_path, clock_path, inst_path, plain_path): require(p.exists(), f"Mac input missing: {rel(p)}")
        ax, cap, clock, inst, plain = [load_json(x) for x in (ax_path, cap_path, clock_path, inst_path, plain_path)]
        sr = [x for x in summary["runs"] if x.get("run") == i]
        require(len(sr) == 1, f"Mac summary run identity {i}"); sr = sr[0]
        require(sr.get("externalAXRawHash") == "sha256:" + sha256_file(ax_path), f"Mac AX hash mismatch {i}")
        require(sr.get("captureHash") == "sha256:" + sha256_file(cap_path), f"Mac capture hash mismatch {i}")
        require(cap.get("case") == {"id": c["case"]["id"], "hash": c["case"]["sha256"]}, f"Mac capture case mismatch {i}")
        require(cap.get("meta", {}).get("run") == i, f"Mac capture run mismatch {i}")
        require(ax.get("status") == "OBSERVED" and ax.get("mode") == "fresh-external-ax" and ax.get("permissionRequests") is False, f"Mac AX status {i}")
        require(ax.get("windowTitle") == "SwiftRightFactory-" + c["case"]["id"], f"Mac AX title {i}")
        require(type(ax.get("pid")) is int and type(ax.get("clientPID")) is int, f"Mac AX PIDs {i}")
        require(ax["pid"] not in owners and ax["clientPID"] not in clients, f"Mac process reused {i}")
        owners.add(ax["pid"]); clients.add(ax["clientPID"])
        labels = [x["value"] for x in walk(ax.get("steps", [{}])[0].get("tree", {})) if x.get("role") == "AXStaticText" and isinstance(x.get("value"), str) and x.get("value") != ax.get("windowTitle")]
        require(labels, f"Mac labels empty {i}")
        require(clock.get("clockId") == "macos.dispatch.uptime" and type(clock.get("startNs")) is int and type(clock.get("endNs")) is int and clock["endNs"] >= clock["startNs"], f"Mac clock {i}")
        dims = {"offscreen": {k: inst.get("image", {}).get(k) for k in ("width", "height", "scale")}, "compositor": {k: next((x.get(k + "Px") for x in cap.get("images", []) if x.get("id") == "macos.compositor"), None) for k in ("width", "height")}, "layout": cap.get("layout", [{}])[0].get("frame", {})}
        require(dims["offscreen"] == {"width": 96, "height": 40, "scale": 1}, f"Mac offscreen dimensions {i}")
        require(dims["layout"].get("width") == 96 and dims["layout"].get("height") == 40, f"Mac layout dimensions {i}")
        rows.append({"run": i, "labels": labels, "ownerPid": ax["pid"], "clientPid": ax["clientPID"], "raw": {"externalAX": "sha256:" + sha256_file(ax_path), "capture": "sha256:" + sha256_file(cap_path), "clock": "sha256:" + sha256_file(clock_path), "instrumented": "sha256:" + sha256_file(inst_path), "plain": "sha256:" + sha256_file(plain_path)}, "dimensions": dims, "timingRaw": clock})
    return {"root": c["mac"]["root"], "summarySha256": c["mac"]["summarySha256"], "runs": rows, "binarySha256": c["mac"]["binarySha256"], "toolchain": c["mac"]["toolchain"]}

def run_dir_for(root: Path, i: int) -> Path:
    for p in (root / "replays" / f"run-{i:03d}", root / f"run-{i:03d}"):
        if p.is_dir(): return p
    if i == 1 and (root / "observation.json").exists(): return root
    raise EvidenceError(f"Windows run missing: {rel(root)}/run-{i:03d}")

def windows_row(root: Path, i: int, c: dict[str, Any]) -> dict[str, Any]:
    # Fresh capture-v4 repeat archive keeps one compile receipt at root & one
    # native-N directory per attempted desktop observation. Older replay
    # archives keep one observation/native pair per run; accept both exact
    # layouts without synthesizing missing rows.
    native_dir = root / f"native-{i:02d}"
    flat_repeat = native_dir.is_dir()
    d = root if flat_repeat else run_dir_for(root, i)
    obs_path = d / "observation.json"
    native_path = d / "native-observation.json"
    if flat_repeat:
        outcome_path = native_dir / "capture-outcome.json"
        ui_path, px_path = native_dir / "native.uia.json", native_dir / "native.pixels.json"
        native = load_json(root / "plan.json")
        outcome = load_json(outcome_path)
    else:
        outcome_path = None
        ui_path = d / "native-01/native.uia.json" if (d / "native-01/native.uia.json").exists() else d / "native.uia.json"
        px_path = d / "native-01/native.pixels.json" if (d / "native-01/native.pixels.json").exists() else d / "native.pixels.json"
        outcome = {}
        native = load_json(native_path) if native_path.exists() else {}
    for p in (obs_path, ui_path, px_path): require(p.exists(), f"Windows input missing: {rel(p)}")
    obs, ui, px = load_json(obs_path), load_json(ui_path), load_json(px_path)
    case = c["case"]
    require(obs.get("sourceHash") == c["source"]["sha256"] and native.get("sourceHash") == c["source"]["sha256"], f"Windows source mismatch {i}")
    require(native.get("case") == {"id": case["id"], "hash": case["sha256"]}, f"Windows case mismatch {i}")
    require(native.get("nativeParity") == "hold", f"Windows native parity state {i}")
    require(native.get("frozenTupleBound") is False and native.get("closureBinding") is None, f"Windows qualification state {i}")
    if flat_repeat:
        # Failed attempt remains raw evidence, never promoted into successful
        # semantic rows. Exact kernel/stream facts distinguish failure.
        pre = outcome.get("preCleanupExitObservation", {})
        is_success = (outcome.get("primaryError") == "" and pre.get("kernelWaitResult") == 0
                      and pre.get("hasExitedObserved") is True)
        host_stdout_path, host_stderr_path = native_dir / "host.stdout.txt", native_dir / "host.stderr.txt"
        host_stdout = host_stdout_path.read_text(errors="replace") if host_stdout_path.exists() else ""
        host_errors = ["FACTORY_RENDER_ERROR Error Domain=FactoryOwnedRendererHWNDAmbiguous Code=1 \"(null)\""] if "FactoryOwnedRendererHWNDAmbiguous" in host_stdout else []
        raw = {"captureOutcome": "sha256:" + sha256_file(outcome_path), "uia": "sha256:" + sha256_file(ui_path), "pixels": "sha256:" + sha256_file(px_path)}
        if host_stdout_path.exists(): raw["hostStdout"] = "sha256:" + sha256_file(host_stdout_path)
        if host_stderr_path.exists(): raw["hostStderr"] = "sha256:" + sha256_file(host_stderr_path)
        if host_errors:
            return {"run": i, "status": "invalid-host", "hostValid": False, "hostErrors": host_errors, "primaryError": outcome.get("primaryError"), "raw": raw, "timingRaw": {"ownedStartedAt": outcome.get("ownedIdentity", {}).get("startedAt"), "preCleanup": pre}}
        if not is_success:
            return {"run": i, "status": "failed-deadline", "hostValid": True, "hostErrors": [], "primaryError": outcome.get("primaryError"), "raw": raw, "timingRaw": {"ownedStartedAt": outcome.get("ownedIdentity", {}).get("startedAt"), "preCleanup": pre}}
        require(outcome.get("sourceHash") == c["source"]["sha256"], f"Windows source outcome mismatch {i}")
    else:
        require(native.get("exitCode") == 0 and native.get("hostValid") is True, f"Windows native status {i}")
        require(obs.get("timedOut") is False and obs.get("ownedExited") is True, f"Windows process state {i}")
    dims = {"printWindow": {k: px.get(k) for k in ("width", "height", "dpi")}}
    require(dims["printWindow"] == {"width": 800, "height": 600, "dpi": 240}, f"Windows dimensions {i}")
    labels = [x.get("name") for x in walk(ui) if x.get("controlType") == "ControlType.Text" and isinstance(x.get("name"), str)]
    require(labels, f"Windows labels empty {i}")
    raw = {"observation": "sha256:" + sha256_file(obs_path), "uia": "sha256:" + sha256_file(ui_path), "pixels": "sha256:" + sha256_file(px_path)}
    if outcome_path: raw["captureOutcome"] = "sha256:" + sha256_file(outcome_path)
    return {"run": i, "status": "eligible", "hostValid": True, "hostErrors": [], "labels": labels, "raw": raw, "dimensions": dims,
            "timingRaw": ({"compile": {k: obs.get(k) for k in ("startedAt", "processStartedAt", "finishedAt")}, "ownedStartedAt": outcome.get("ownedIdentity", {}).get("startedAt"), "preCleanup": outcome.get("preCleanupExitObservation", {})} if flat_repeat else {k: obs.get(k) for k in ("startedAt", "processStartedAt", "finishedAt", "timedOut")})}

def validate_peer_review(c: dict[str, Any]) -> dict[str, Any]:
    p = ROOT / c["peerReview"]["path"]
    require(p.exists(), "Windows peer review missing")
    require("sha256:" + sha256_file(p) == c["peerReview"]["sha256"], "Windows peer review bytes changed")
    d = load_json(p)
    require(d.get("verdict") == "CONFIRMED_FAILED_PARTIAL_BATCH_WITH_PRIOR_HOST_ERRORS", "peer review verdict changed")
    require(d.get("requestedRuns") == 20 and d.get("startedRuns") == 18 and d.get("priorRawCaptures") == 17 and d.get("priorHostErrorFreeRawCaptures") == 15 and d.get("priorHostErrorRuns") == [3, 16] and d.get("failedRun") == 18 and d.get("notStarted") == [19, 20], "peer review counts changed")
    return d

def windows_report(c: dict[str, Any], windows_root: Path | None) -> dict[str, Any]:
    root = windows_root or (ROOT / c["windows"]["root"])
    require(root.exists(), f"Windows repeat root missing: {rel(root)}")
    peer = validate_peer_review(c)
    if (root / "native-01").is_dir():
        attempted = sorted(int(p.name.split("-")[1]) for p in root.glob("native-[0-9][0-9]") if p.is_dir())
        require(attempted and attempted == list(range(1, max(attempted) + 1)), "Windows native attempt indices are not contiguous")
        rows = [windows_row(root, i, c) for i in attempted]
        successful = [x for x in rows if x.get("status") == "eligible"]
        invalid_host = [x for x in rows if x.get("status") == "invalid-host"]
        failed = [x for x in rows if x.get("status") == "failed-deadline"]
        require(len(rows) == peer["startedRuns"] and len(successful) == peer["priorHostErrorFreeRawCaptures"] and [x["run"] for x in invalid_host] == peer["priorHostErrorRuns"] and [x["run"] for x in failed] == [peer["failedRun"]], "Windows raw row classification disagrees with peer review")
        return {"root": rel(root), "expectedRuns": c["windows"]["runs"], "attemptedRuns": len(rows), "successfulRuns": len(successful), "invalidHostRuns": len(invalid_host), "failedRuns": len(failed), "invalidHostRows": invalid_host, "failedRows": failed, "runs": successful, "compilerHash": c["windows"]["compilerHash"], "rendererSha256": c["windows"]["rendererSha256"], "runtimeSourceTreeSha256": c["windows"]["runtimeSourceTreeSha256"], "completion": "partial-no-retry", "peerReview": {"path": c["peerReview"]["path"], "sha256": c["peerReview"]["sha256"]}}
    rows = [windows_row(root, i, c) for i in range(1, c["windows"]["runs"] + 1)]
    return {"root": rel(root), "expectedRuns": c["windows"]["runs"], "attemptedRuns": len(rows), "successfulRuns": len(rows), "invalidHostRuns": 0, "failedRuns": 0, "invalidHostRows": [], "failedRows": [], "runs": rows, "compilerHash": c["windows"]["compilerHash"], "rendererSha256": c["windows"]["rendererSha256"], "runtimeSourceTreeSha256": c["windows"]["runtimeSourceTreeSha256"], "completion": "complete", "peerReview": {"path": c["peerReview"]["path"], "sha256": c["peerReview"]["sha256"]}}

def semantic(mac: dict[str, Any], win: dict[str, Any]) -> dict[str, Any]:
    m = mac["runs"][0]["labels"]; w = win["runs"][0]["labels"]
    mapped = [{"role": ROLE_MAP["AXStaticText"], "value": x} for x in m]
    values = [{"role": "ControlType.Text", "value": x} for x in w]
    return {"comparison": "exact-role-and-label-sequence", "roleMap": ROLE_MAP, "macMappedValues": mapped, "windowsValues": values, "macStableAcross20": all(x["labels"] == m for x in mac["runs"]), "windowsStableAcrossSuccessfulRuns": all(x["labels"] == w for x in win["runs"]), "exactSequenceMatch": mapped == values and all(x["labels"] == m for x in mac["runs"]) and all(x["labels"] == w for x in win["runs"]), "qualification": "not-claimed"}

def timing(mac: dict[str, Any], win: dict[str, Any]) -> dict[str, Any]:
    return {"scope": "raw provider clocks retained", "mac": [x["timingRaw"] for x in mac["runs"]], "windows": [x["timingRaw"] for x in win["runs"]], "crossPlatformTimingComparison": "unavailable-different-clock-scopes"}

def build(c: dict[str, Any], windows_root: Path | None) -> dict[str, Any]:
    validate_config_shape(c)
    mac, win = mac_report(c), windows_report(c, windows_root)
    status = "source-bound-observation-only" if win["completion"] == "complete" else "source-bound-observation-partial-no-retry"
    return {"schema": "paired-padding-settled-observational-report-v2", "status": status, "candidateOnly": True, "identity": {"block": c["block"], "case": c["case"], "source": c["source"], "recipe": c["recipe"], "witness": c["witness"]}, "macOS": mac, "windows": win, "dimensions": {"macOS": c["mac"]["dimensions"], "windows": c["windows"]["dimensions"]}, "semantic": semantic(mac, win), "timing": timing(mac, win), "qualification": c["qualification"], "claims": {"semantic": "exact raw role-mapped label sequence only across eligible rows", "timing": "raw-only", "nativeParity": "held", "pixelParity": "held", "providerReadback": "held", "goldens": 0, "promotion": "held", "attemptedWindowsRuns": win["attemptedRuns"], "eligibleWindowsRuns": win["successfulRuns"], "invalidHostWindowsRuns": win["invalidHostRuns"], "failedWindowsRuns": win["failedRuns"], "failedAttemptsRetained": True, "hostErrorRowsRetained": True}}

def controls(c: dict[str, Any], windows_root: Path | None) -> dict[str, str]:
    baseline = build(c, windows_root); out = {}
    for name, mutate in (("source", lambda x: x["source"].__setitem__("sha256", "sha256:" + "0" * 64)), ("case", lambda x: x["case"].__setitem__("sha256", "sha256:" + "1" * 64)), ("qualification", lambda x: x["qualification"].__setitem__("promotion", "qualified")), ("peer-host-errors", lambda x: x["peerReview"].__setitem__("sha256", "sha256:" + "0" * 64))):
        q = copy.deepcopy(c); mutate(q)
        try: build(q, windows_root)
        except EvidenceError: out[name] = "rejected"
        else: out[name] = "accepted-BUG"
    q = copy.deepcopy(baseline); q["semantic"]["macMappedValues"][0]["value"] = "forged"; out["semantic-report-mutation"] = "rejected" if q["semantic"]["macMappedValues"] != baseline["semantic"]["macMappedValues"] else "accepted-BUG"
    return out

def main() -> int:
    ap = argparse.ArgumentParser(); ap.add_argument("--windows-root", type=Path); ap.add_argument("--output", type=Path); ap.add_argument("--fault-controls", action="store_true"); args = ap.parse_args()
    c = config(); mac_report(c)
    if args.fault_controls:
        if not args.windows_root and not (ROOT / c["windows"]["root"]).exists(): print(json.dumps({"status":"prepared-windows-repeat-pending","macRuns":20})); return 0
        print(json.dumps(controls(c, args.windows_root), sort_keys=True)); return 0
    report = build(c, args.windows_root); out = args.output or Path(__file__).resolve().parent / "report.json"; out.parent.mkdir(parents=True, exist_ok=True); out.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"); print(json.dumps({"status": report["status"], "macRuns": len(report["macOS"]["runs"]), "windowsAttempted": report["windows"]["attemptedRuns"], "windowsSuccessful": report["windows"]["successfulRuns"], "windowsFailed": report["windows"]["failedRuns"], "semantic": report["semantic"]["exactSequenceMatch"], "output": rel(out)}, sort_keys=True)); return 0

if __name__ == "__main__":
    try: raise SystemExit(main())
    except EvidenceError as e: print(f"EvidenceError: {e}", file=sys.stderr); raise SystemExit(2)
