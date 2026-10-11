#!/usr/bin/env python3
"""Build & validate F9 paired stack/custom observation from frozen raw bytes."""
from __future__ import annotations
import copy, hashlib, json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "factory/pipeline/paired-stack-custom-observation-v1"
WIN = ROOT / "factory/native/windows/round1-stack-layout-native-v1"
MAC_STACK = ROOT / "factory/native/macos/evidence/20261010-primary-five-r3/swiftui.stack-overlay.recipe_case_aac89c30fbc61515"
MAC_CUSTOM = ROOT / "factory/native/macos/evidence/20261010-corrected-primary/swiftui.custom-layout.recipe_case_b30ed0b185e8cb29"
STACK = WIN / "actual-stack-overlay-r1"
CUSTOM = WIN / "actual-custom-layout-r1"

STACK_CASE = "sha256:6b612bc12777ef3f5e6447d435128a3f805f8f990ece4eab9a91d9dec36f9cd0"
STACK_SOURCE = "sha256:d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee"
CUSTOM_CASE = "sha256:fb33f02bd1f764e233bc356d2ceabb980203876ded9dd25e59c122d6dab1a39a"
CUSTOM_SOURCE = "sha256:77cced764631365ef220482cd31b522730fce73f05b5e1e03dd43a31f23e9a5b"

def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()

def load(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))

def inv(root: Path):
    files = []
    for p in sorted((x for x in root.rglob("*") if x.is_file()), key=lambda x: x.relative_to(root).as_posix()):
        files.append({"path": p.relative_to(root).as_posix(), "bytes": p.stat().st_size, "sha256": "sha256:" + sha(p)})
    blob = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return {"root": str(root.relative_to(ROOT)), "fileCount": len(files), "bytes": sum(x["bytes"] for x in files), "inventorySha256": "sha256:" + hashlib.sha256(blob).hexdigest(), "files": files}

def required_file(inv_data, rel):
    for f in inv_data["files"]:
        if f["path"] == rel:
            return f
    raise AssertionError(f"missing raw input {rel}")

def source_bindings(plan, attempt: Path):
    out = []
    for b in plan["sourceBindings"]:
        p = attempt / b["path"]
        if b["path"] == "witness.manifest.json":
            # witness manifest lives in immutable host package, not transferred attempt.
            out.append({"path": b["path"], "declaredSha256": b["sha256"], "present": False, "reason": "external host package input; declaration retained"})
        else:
            out.append({"path": b["path"], "declaredSha256": b["sha256"], "actualSha256": "sha256:" + sha(p), "bytes": p.stat().st_size})
    return out

def check_plan(attempt: Path, case_hash: str, source_hash: str):
    plan = load(attempt / "plan.json")
    obs = load(attempt / "observation.json")
    assert plan["case"]["hash"] == case_hash
    assert plan["sourceHash"] == source_hash
    assert obs["sourceHash"] == source_hash
    assert obs["rendererSha256"] == plan["rendererSha256"]
    assert obs["runtimeSourceTreeHash"] == plan["runtimeSourceTreeHash"]
    assert obs["runtimeSourceCommit"] == plan["runtimeSourceCommit"]
    assert obs["exitCode"] == 0 and obs["timedOut"] is False and obs["ownedExited"] is True
    return plan, obs

def archive_join(root: Path, expected_case: str, expected_source: str):
    summary_path = root / "summary.json"
    d = load(summary_path)
    assert d["case"]["hash"] == expected_case
    assert d["provenance"]["sourceHash"] == expected_source
    assert d["probeManifest"]["case"]["hash"] == expected_case
    assert d["probeManifest"]["sourceHash"] == expected_source
    assert len(d.get("runs", [])) == 20
    return {"summaryPath": str(summary_path.relative_to(ROOT)), "summarySha256": "sha256:" + sha(summary_path), "caseHash": expected_case, "sourceHash": expected_source, "runs": 20, "acceptance": d.get("acceptance"), "candidateOnly": d.get("candidateOnly"), "channels": d.get("channels"), "archiveInventoryRoot": str(root.relative_to(ROOT))}

def make_report():
    splan, sobs = check_plan(STACK, STACK_CASE, STACK_SOURCE)
    cplan, cobs = check_plan(CUSTOM, CUSTOM_CASE, CUSTOM_SOURCE)
    sinv, cinv = inv(STACK), inv(CUSTOM)
    stack_stdout = (STACK / "native-01/host.stdout.txt").read_text(errors="replace")
    assert "FACTORY_RENDER_ERROR" in stack_stdout and "Overlay" in stack_stdout
    assert not (STACK / "native-observation.json").exists()
    assert not (STACK / "native-01/native.uia.json").exists()
    n = load(CUSTOM / "native-observation.json")
    px = load(CUSTOM / "native-01/native.pixels.json")
    ui = load(CUSTOM / "native-01/native.uia.json")
    assert n["case"]["hash"] == CUSTOM_CASE and n["sourceHash"] == CUSTOM_SOURCE
    assert n["compileReceiptHash"] == sha(CUSTOM / "observation.json")
    assert n["exitCode"] == 0 and n["hostValid"] is True and n["nativeParity"] == "hold"
    proc = load(CUSTOM / "native-01/owned-process.json")
    launch = load(CUSTOM / "native-01/launch-observation.json")
    assert px["hwnd"] == launch["ownedWindow"] and px["pid"] == proc["pid"] and px["width"] == 800 and px["height"] == 600 and px["dpi"] == 240
    assert px["printWindowRepeatStable"] is True and px["screenRepeatStable"] is True and px["methodsEqual"] is False
    assert ui.get("children") == []
    custom_png = required_file(cinv, "native-01/native.printwindow.png")
    custom_png_repeat = required_file(cinv, "native-01/native.printwindow.repeat.png")
    assert custom_png["sha256"] == custom_png_repeat["sha256"]
    stack_archive = archive_join(MAC_STACK, STACK_CASE, STACK_SOURCE)
    custom_archive = archive_join(MAC_CUSTOM, CUSTOM_CASE, CUSTOM_SOURCE)
    report = {
      "kind": "f9-paired-stack-custom-observation-v1",
      "version": 1,
      "candidateOnly": True,
      "goldens": 0,
      "qualification": "held",
      "parity": "unavailable",
      "inputs": {"windowsAttempts": [sinv, cinv], "macArchives": [stack_archive, custom_archive]},
      "observations": [
        {
          "id": "windows-stack-overlay-r1", "recipe": "swiftui.stack-overlay.recipe", "host": "windows",
          "case": splan["case"], "sourceHash": splan["sourceHash"], "status": "probe-failure",
          "failureClass": "unsupportedOverlay", "rawDispatchStatus": load(STACK / "dispatch.json")["status"],
          "rawTaskResult": load(STACK / "task-result.json"), "rendererError": "FACTORY_RENDER_ERROR ... Overlay",
          "channels": {"printWindow": "unavailable", "uia": "unavailable", "screen": "unavailable", "shape": "unavailable", "layout": "unavailable"},
          "nativeUnits": {"shape": "unavailable", "layout": "unavailable", "reason": "renderer failed before native capture"},
          "archiveJoin": {"status": "exact-case-source-join", "summary": stack_archive["summaryPath"], "runs": 20},
          "comparison": "no native DIFF: Windows probe failed before capture; Mac candidate channels are separate",
          "rawInputRoots": [sinv["root"], stack_archive["archiveInventoryRoot"]]
        },
        {
          "id": "windows-custom-layout-r1", "recipe": "swiftui.custom-layout.recipe", "host": "windows",
          "case": cplan["case"], "sourceHash": cplan["sourceHash"], "status": "observed-partial",
          "rawDispatchStatus": load(CUSTOM / "dispatch.json")["status"], "rawTaskResult": load(CUSTOM / "task-result.json"),
          "capture": {"method": n["captureMethod"], "hwnd": px["hwnd"], "pid": px["pid"], "width": px["width"], "height": px["height"], "dpi": px["dpi"], "printWindowPngSha256": custom_png["sha256"], "repeatPngSha256": custom_png_repeat["sha256"], "screenPngSha256": required_file(cinv, "native-01/native.screen.png")["sha256"], "screenRepeatSha256": required_file(cinv, "native-01/native.screen.repeat.png")["sha256"], "printWindowRepeatStable": px["printWindowRepeatStable"], "screenRepeatStable": px["screenRepeatStable"], "methodsEqual": px["methodsEqual"]},
          "uia": {"rootControlType": ui.get("controlType"), "children": len(ui.get("children", [])), "semanticFields": "unavailable"},
          "channels": {"printWindow": "observed-once-plus-repeat", "uia": "root-only-empty-children", "screen": "observed-once-plus-repeat", "shape": "unavailable", "layout": "unavailable", "role": "unavailable", "label": "unavailable", "enabled": "raw-root-only-not-semantic"},
          "nativeUnits": {"shape": "unavailable", "layout": "unavailable", "reason": "native packet has pixels/viewport only; no provider geometry"},
          "archiveJoin": {"status": "exact-case-source-join", "summary": custom_archive["summaryPath"], "runs": 20},
          "comparison": "no native DIFF: Mac custom archive has separate candidate channels & no shared qualified semantics",
          "rawInputRoots": [cinv["root"], custom_archive["archiveInventoryRoot"]]
        }
      ],
      "controls": {"required": ["mismatched-source-rejected", "mismatched-case-rejected", "missing-raw-rejected", "forged-status-rejected"], "runner": "build_report.py --fault-controls"}
    }
    return report

def validate(report):
    assert report["kind"] == "f9-paired-stack-custom-observation-v1" and report["goldens"] == 0 and report["qualification"] == "held"
    assert len(report["observations"]) == 2
    for root_data in report["inputs"]["windowsAttempts"]:
        root = ROOT / root_data["root"]
        fresh = inv(root)
        assert fresh["inventorySha256"] == root_data["inventorySha256"] and fresh["fileCount"] == root_data["fileCount"]
        assert fresh["files"] == root_data["files"]
    by_id = {x["id"]: x for x in report["observations"]}
    s, c = by_id["windows-stack-overlay-r1"], by_id["windows-custom-layout-r1"]
    assert s["case"]["hash"] == STACK_CASE and s["sourceHash"] == STACK_SOURCE and s["status"] == "probe-failure" and s["failureClass"] == "unsupportedOverlay"
    assert c["case"]["hash"] == CUSTOM_CASE and c["sourceHash"] == CUSTOM_SOURCE and c["status"] == "observed-partial"
    assert c["capture"]["printWindowPngSha256"] == c["capture"]["repeatPngSha256"]
    assert c["channels"]["shape"] == "unavailable" and c["channels"]["layout"] == "unavailable"
    for x in report["inputs"]["macArchives"]:
        p = ROOT / x["summaryPath"]
        assert "sha256:" + sha(p) == x["summarySha256"] and x["runs"] == 20
    return True

def run_controls(report):
    assert validate(report)
    outcomes = {}
    for name, mutate in {
      "mismatched-source": lambda r: r["observations"][1].__setitem__("sourceHash", "sha256:" + "0" * 64),
      "mismatched-case": lambda r: r["observations"][1]["case"].__setitem__("hash", "sha256:" + "1" * 64),
      "missing-raw": lambda r: r["inputs"]["windowsAttempts"][1]["files"].pop(),
      "forged-status": lambda r: r["observations"][1].__setitem__("status", "native-diff"),
    }.items():
        q = copy.deepcopy(report); mutate(q)
        try: validate(q)
        except (AssertionError, KeyError): outcomes[name] = "rejected"
        else: outcomes[name] = "accepted-BUG"
    assert all(v == "rejected" for v in outcomes.values()), outcomes
    return outcomes

def main():
    report = make_report(); validate(report)
    if "--fault-controls" in sys.argv:
        print(json.dumps({"baseline": "accepted", "controls": run_controls(report)}, indent=2)); return
    (OUT / "raw-pins.json").write_text(json.dumps({"kind":"f9-raw-input-pins-v1","windows":report["inputs"]["windowsAttempts"],"macSummaries":report["inputs"]["macArchives"],"macArchives":[inv(MAC_STACK), inv(MAC_CUSTOM)]}, indent=2, sort_keys=True) + "\n")
    (OUT / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"status":"ok","goldens":0,"windowsRoots":[x["inventorySha256"] for x in report["inputs"]["windowsAttempts"]],"macSummaries":[x["summarySha256"] for x in report["inputs"]["macArchives"]]}, indent=2))

if __name__ == "__main__": main()
