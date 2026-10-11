#!/usr/bin/env python3
"""Independent raw-evidence review for F9 paired-five actual v2."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
STAGE = ROOT / "factory/pipeline/paired-five-observations-actual-v2"
WIN = ROOT / "factory/native/windows"
MAC = ROOT / "factory/native/macos/evidence"
V5 = WIN / "round1-native-v5"
V6 = WIN / "round1-native-v6/repeat-preference-key-r1"
PREFERENCE_REVIEW = WIN / "round1-native-v6/independent-review/actual-preference20-review-v1.json"
ROLE_MAP = {"AXStaticText": "ControlType.Text"}
SUCCESS = "captured-single-observational-uia-printwindow"
CASES = {
    "stack": {
        "case_id": "swiftui.stack-overlay.recipe/case/aac89c30fbc61515",
        "case": "sha256:6b612bc12777ef3f5e6447d435128a3f805f8f990ece4eab9a91d9dec36f9cd0",
        "source": "sha256:d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee",
        "windows": V5 / "repeat-stack-overlay-r1",
        "mac": MAC / "20261010-primary-five-r3/swiftui.stack-overlay.recipe_case_aac89c30fbc61515",
        "exe": "83aae7bde8ef2b7d36a4bb6667cd0da2f2dbd5d60b0b4fe3b7970b33ea941870",
    },
    "custom": {
        "case_id": "swiftui.custom-layout.recipe/case/b30ed0b185e8cb29",
        "case": "sha256:fb33f02bd1f764e233bc356d2ceabb980203876ded9dd25e59c122d6dab1a39a",
        "source": "sha256:77cced764631365ef220482cd31b522730fce73f05b5e1e03dd43a31f23e9a5b",
        "windows": V5 / "repeat-custom-layout-r1",
        "mac": MAC / "20261010-corrected-primary/swiftui.custom-layout.recipe_case_b30ed0b185e8cb29",
        "exe": "b1a58d5827fceb3dcd225c46a5c1963862386a62b09d5cf949abd83dec7c44c6",
    },
    "padding": {
        "case_id": "swiftui.padding-frame.recipe/case/8805e6d0729b052d",
        "case": "sha256:58a7c081166141df0b496c4b9ccd0043731d03048993f27842b171387d5c4d5b",
        "source": "sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b",
        "windows": V5 / "repeat-padding-frame-r1",
        "mac": MAC / "20261010-primary-next-five/swiftui.padding-frame.recipe_case_8805e6d0729b052d",
        "exe": "6ba84c2e99d46bab646d4fd588e3351816118a7c9e53322a75c03371be2fa49c",
    },
    "scroll": {
        "case_id": "swiftui.scroll-view.recipe/case/6716afb4fb55269b",
        "case": "sha256:56c2625f63e7e633c18ea0cdfca37545748f1d098622391e3c270be07895dc98",
        "source": "sha256:cd6615468e11e0137c6e1c9ada25c0cdf2f5a0f4c33668ec63161674b743a2c4",
        "windows": V5 / "repeat-scroll-view-r1",
        "mac": MAC / "20261010-primary-next-five/swiftui.scroll-view.recipe_case_6716afb4fb55269b",
        "exe": "8be63237c595406036e3869500e7c298781d810b1d78b6eb3ab0242218e7d752",
    },
    "preference": {
        "case_id": "swiftui.preference-key.recipe/case/66b6b44aaff817d6",
        "case": "sha256:b2292465cf5f9857b92345a973fc413611365606aec12c9dc435f14ed62bc96d",
        "source": "sha256:e104e949a6e0f8c6e9e41a6d2d7815a112a40e19d5919b82d2074fd7f5bf9c1f",
        "windows": V6,
        "mac": MAC / "20261010-corrected-primary/swiftui.preference-key.recipe_case_66b6b44aaff817d6",
        "exe": "665846f7c9be47a7d6050e85cd762c660a305e642a58259371b9a2e3de97f6b1",
    },
}


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for b in iter(lambda: f.read(1024 * 1024), b""):
            h.update(b)
    return h.hexdigest()


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def inv(root: Path):
    files = []
    for p in sorted((x for x in root.rglob("*") if x.is_file()), key=lambda x: x.relative_to(root).as_posix()):
        files.append({"path": p.relative_to(root).as_posix(), "bytes": p.stat().st_size, "sha256": "sha256:" + sha(p)})
    raw = json.dumps(files, sort_keys=True, separators=(",", ":")).encode()
    return {"root": root.relative_to(ROOT).as_posix(), "exists": root.exists(), "fileCount": len(files), "bytes": sum(x["bytes"] for x in files), "inventorySha256": "sha256:" + hashlib.sha256(raw).hexdigest(), "files": files}


def walk(value):
    if isinstance(value, dict):
        yield value
        for child in value.values():
            yield from walk(child)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child)


def mac_labels(raw):
    steps = raw.get("steps")
    if not isinstance(steps, list) or not steps:
        return []
    tree = steps[0].get("tree", {})
    return [n["value"] for n in walk(tree) if n.get("role") == "AXStaticText" and isinstance(n.get("value"), str) and n.get("value") != raw.get("windowTitle")]


def windows_labels(ui):
    return [n["name"] for n in walk(ui) if n.get("controlType") == "ControlType.Text" and isinstance(n.get("name"), str)]


def check_stage():
    stage = read(STAGE / "stage-manifest.json")
    assert stage["kind"] == "f9-paired-five-observations-actual-v2-stage" and stage["fileCount"] == 4
    for row in stage["files"]:
        p = STAGE / row["path"]
        assert p.stat().st_size == row["bytes"] and "sha256:" + sha(p) == row["sha256"]
    return stage


def verify(report, pins, *, actual=True):
    assert report["kind"] == "f9-paired-five-observations-actual-v2" and report["version"] == 1
    assert report["candidateOnly"] is True and report["caseCount"] == 5
    assert report["claims"]["windows20Cases"] == ["stack", "custom", "padding", "scroll", "preference"]
    assert report["claims"]["preferenceWindowsUsableRuns"] == 20 and report["claims"]["preferenceV5FailureRetained"] is True
    assert report["claims"]["nativeParity"] == report["claims"]["qualifiedPaint"] == report["claims"]["focus"] == report["claims"]["occlusion"] == report["claims"]["qualification"] == "held"
    assert report["claims"]["goldens"] == 0 and report["claims"]["timing"] == "raw-only"
    assert report["rawTiming"]["scope"] == "retained per-run timestamps & Mac clock JSON hashes; no timing claim"
    assert report["accessibility"]["roleMap"] == ROLE_MAP
    assert report["accessibility"]["adapter"] == "independently reviewed exact AXStaticText to ControlType.Text role mapping"

    expected_roots = {c["windows"].relative_to(ROOT).as_posix() for c in CASES.values()}
    expected_roots |= {c["mac"].relative_to(ROOT).as_posix() for c in CASES.values()}
    expected_roots.add((V5 / "repeat-preference-key-r1").relative_to(ROOT).as_posix())
    pin_roots = {r["root"]: r for r in pins["roots"]}
    assert set(pin_roots) == expected_roots and len(pin_roots) == 11
    assert report["rawPins"]["roots"] == pins["roots"]
    for key, case in CASES.items():
        c = report["cases"][key]
        win_root, mac_root = case["windows"], case["mac"]
        w, m = c["windows"], c["mac20"]
        assert w["path"] == win_root.relative_to(ROOT).as_posix()
        assert m["path"] == mac_root.relative_to(ROOT).as_posix()
        assert w["caseId"] == m["caseId"] == case["case_id"]
        assert w["caseHash"] == m["caseHash"] == case["case"]
        assert w["sourceHash"] == m["sourceHash"] == case["source"]
        assert w["exeHash"] == case["exe"] and w["compileReceiptHash"]
        assert w["requested"] == w["attempted"] == w["successfulObservations"] == 20
        assert w["nativeParity"] == "held" and w["status"] == "completed-20-observational"
        assert len(w["rows"]) == len(m["runs"]) == 20
        assert w["rawInventory"] == pin_roots[str(w["path"])]
        assert m["rawInventory"] == pin_roots[str(m["path"])]
        if actual:
            assert inv(win_root) == w["rawInventory"]
            assert inv(mac_root) == m["rawInventory"]

        batch = read(win_root / "batch.json")
        assert batch["requested"] == batch["attempted"] == 20 and batch["retry"] is False
        assert batch["exeHash"] == case["exe"] and batch["compileReceiptHash"] == w["compileReceiptHash"]
        assert len(batch["rows"]) == 20 and {r["index"] for r in batch["rows"]} == set(range(1, 21))
        for row, summary in zip(sorted(batch["rows"], key=lambda x: x["index"]), w["rows"]):
            run = win_root / "replays" / f"run-{row['index']:03d}"
            witness = run / "Sources/FactoryProbe/Witness.swift"
            assert row["run"] == summary["run"] == f"run-{row['index']:03d}" and row["status"] == SUCCESS
            assert summary["valid"] is True and summary["sourceHash"] == case["source"] and summary["caseHash"] == case["case"]
            assert summary["exeHash"] == case["exe"] and summary["compileReceiptHash"] == w["compileReceiptHash"]
            assert "sha256:" + sha(witness) == case["source"]
            plan, obs, native = [read(run / fn) for fn in ("plan.json", "observation.json", "native-observation.json")]
            dispatch, config, result = [read(run / fn) for fn in ("dispatch.json", "config.json", "task-result.json")]
            ui = read(run / "native-01/native.uia.json")
            px = read(run / "native-01/native.pixels.json")
            cap = read(run / "native-01/capture-outcome.json")
            assert plan["case"]["id"] == case["case_id"] and plan["case"]["hash"] == case["case"] and plan["sourceHash"] == case["source"]
            assert obs["sourceHash"] == native["sourceHash"] == cap["sourceHash"] == case["source"]
            assert native["case"]["id"] == case["case_id"] and native["case"]["hash"] == case["case"]
            assert obs["exeSha256"] == native["exeSha256"] == config["exeHash"] == cap["exeHash"] == case["exe"]
            assert config["compileReceiptHash"] == cap["compileReceiptHash"] == w["compileReceiptHash"]
            assert dispatch["status"] == result["status"] == SUCCESS and native["hostValid"] is True and native["exitCode"] == 0
            assert px["width"] == 800 and px["height"] == 600 and px["dpi"] == 240
            labels = windows_labels(ui)
            assert labels == summary["uiaLabels"] and summary["uiaSha256"] == "sha256:" + sha(run / "native-01/native.uia.json")
            assert summary["nativeObservationSha256"] == "sha256:" + sha(run / "native-observation.json")

        summary = read(mac_root / "summary.json")
        assert summary["case"] == {"id": case["case_id"], "hash": case["case"]}
        assert summary["sourceHash"] == summary["provenance"]["sourceHash"] == summary["probeManifest"]["sourceHash"] == case["source"]
        assert summary["candidateOnly"] is True and summary["acceptance"] == "not-promoted"
        assert m["summarySha256"] == "sha256:" + sha(mac_root / "summary.json")
        assert len(summary["runs"]) == 20
        mac_rows = {r["run"]: r for r in m["runs"]}
        for i, macrow in enumerate(summary["runs"], 1):
            assert macrow["run"] == i
            rd = mac_root / f"run-{i:03d}"
            ax = read(rd / "external-ax.raw.json")
            capture = read(rd / "capture.json")
            owned = read(rd / "owned-window-process.json")
            row = mac_rows[i]
            assert capture["case"]["id"] == case["case_id"] and capture["case"]["hash"] == case["case"]
            assert macrow["externalAXRawHash"] == row["rawAXSha256"] == "sha256:" + sha(rd / "external-ax.raw.json")
            assert macrow["captureHash"] == row["captureSha256"] == "sha256:" + sha(rd / "capture.json")
            assert row["externalAXStatus"] == macrow["externalAX"]
            if key == "custom":
                assert ax["status"] == "OBSERVED" and macrow["externalAX"] == "HELD"
                assert mac_labels(ax) == []
            else:
                assert ax["status"] == macrow["externalAX"] == "OBSERVED"
            assert ax["ownerHash"] == owned["binaryHash"] == summary["binaryHash"]
            assert ax["ownerPath"] == owned["executable"] and owned["pid"] == ax["pid"]
            assert row["ownerPid"] == ax["pid"] and row["clientPid"] == ax["clientPID"]
            assert row["labels"] == mac_labels(ax)

    # Exact AX-to-UIA text sequences are observations only.
    comparisons = report["accessibility"]["comparisons"]
    for key in ("stack", "padding", "scroll", "preference"):
        c = report["cases"][key]
        win_seq = c["windows"]["rows"][0]["uiaLabels"]
        mac_seq = c["mac20"]["runs"][0]["labels"]
        assert all(r["uiaLabels"] == win_seq for r in c["windows"]["rows"])
        assert all(r["labels"] == mac_seq for r in c["mac20"]["runs"])
        compare = comparisons[key]
        mapped_mac = [{"role": "ControlType.Text", "value": v} for v in mac_seq]
        mapped_win = [{"role": "ControlType.Text", "value": v} for v in win_seq]
        assert compare["roleMap"] == ROLE_MAP and compare["windowsValues"] == mapped_win
        assert compare["macMappedValues"] == mapped_mac and compare["exactSequenceMatch"] is (win_seq == mac_seq)
        assert compare["qualification"] == "not-claimed"
    custom = comparisons["custom"]
    assert custom["windowsValues"] == [] and custom["macExternalAX"] == "held"
    assert custom["exactSequenceMatch"] is False and custom["qualification"] == "not-claimed"
    assert all(r["uiaLabels"] == [] and r["uiaChildren"] == 0 for r in report["cases"]["custom"]["windows"]["rows"])

    # Preference v6 is the only usable Windows 20-run preference source; failed v5 attempt stays separate.
    pref = report["cases"]["preference"]
    assert pref["windows"]["path"] == V6.relative_to(ROOT).as_posix()
    fail = pref["v5Failure"]
    fail_root = V5 / "repeat-preference-key-r1"
    fail_batch = read(fail_root / "batch.json")
    assert fail["path"] == fail_root.relative_to(ROOT).as_posix()
    assert fail["status"] == fail_batch["status"] == "hold-batch-error"
    assert fail["requested"] == fail_batch["requested"] == 20 and fail["attempted"] == fail_batch["attempted"] == 1
    assert fail["successfulObservations"] == 0 and fail["retry"] is False and fail["rawInventory"] == pin_roots[fail["path"]]
    assert inv(fail_root) == fail["rawInventory"]
    assert fail["rawInventory"]["fileCount"] == 25
    for receipt in report["reviewReceipts"].values():
        receipt_path = ROOT / receipt["path"]
        assert receipt_path.is_file() and receipt["sha256"] == "sha256:" + sha(receipt_path)
        source_receipt = read(receipt_path)
        assert receipt["status"] in (source_receipt.get("status"), source_receipt.get("decision"))
    assert report["reviewReceipts"]["preference20"]["sha256"] == "sha256:" + sha(PREFERENCE_REVIEW)
    assert report["reviewReceipts"]["preference20"]["status"] == "v6-preference20-source-bound-observations-clear"
    return True


def fault_controls(report, pins):
    mutations = {
        "source": lambda x: x["cases"]["stack"]["windows"].__setitem__("sourceHash", "sha256:" + "0" * 64),
        "case": lambda x: x["cases"]["padding"]["windows"].__setitem__("caseHash", "sha256:" + "1" * 64),
        "exe": lambda x: x["cases"]["scroll"]["windows"].__setitem__("exeHash", "0" * 64),
        "sequence": lambda x: x["accessibility"]["comparisons"]["preference"]["windowsValues"].__setitem__(0, {"role": "ControlType.Text", "value": "forged"}),
        "custom": lambda x: x["accessibility"]["comparisons"]["custom"].__setitem__("macExternalAX", "observed"),
        "preference-v5": lambda x: x["cases"]["preference"]["v5Failure"].__setitem__("attempted", 20),
        "raw-pin": lambda x: x["cases"]["custom"]["windows"]["rawInventory"]["files"].pop(),
        "qualification": lambda x: x["claims"].__setitem__("qualification", "qualified"),
    }
    rejected = {}
    for name, mutate in mutations.items():
        altered = copy.deepcopy(report)
        mutate(altered)
        try:
            verify(altered, pins, actual=False)
        except (AssertionError, KeyError, TypeError):
            rejected[name] = "rejected"
        else:
            rejected[name] = "accepted-BUG"
    assert all(v == "rejected" for v in rejected.values()), rejected
    return rejected


if __name__ == "__main__":
    check_stage()
    report = read(STAGE / "report.json")
    pins = read(STAGE / "raw-pins.json")
    verify(report, pins)
    print(json.dumps({"decision": "clear-bounded-observational-only", "stageManifestSha256": "sha256:" + sha(STAGE / "stage-manifest.json"), "rawRoots": len(pins["roots"]), "windowsRuns": 100, "macRuns": 100, "faultControls": fault_controls(report, pins)}, sort_keys=True, indent=2))
