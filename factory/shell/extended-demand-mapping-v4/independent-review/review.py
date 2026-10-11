#!/usr/bin/env python3
"""Offline independent review of extended-demand-mapping-v4.

This review consumes frozen bytes only.  It never opens any original journey or
SDK path recorded inside evidence.
"""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PACKET = ROOT / "factory/shell/extended-demand-mapping-v4"
OUT = HERE


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def require(ok: bool, message: str) -> None:
    if not ok:
        raise AssertionError(message)


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def frozen(path: str, expected_sha: str, expected_bytes: int) -> bytes:
    """Read a repository-relative frozen input and verify its whole bytes."""
    p = ROOT / path
    require(p.is_file() and not p.is_symlink(), f"missing/non-regular input: {path}")
    data = p.read_bytes()
    require(len(data) == expected_bytes, f"size mismatch: {path}")
    require(sha(data) == expected_sha.removeprefix("sha256:"), f"hash mismatch: {path}")
    return data


def verify_stage() -> dict:
    stage_path = PACKET / "stage-manifest-v4.json"
    stage_data = stage_path.read_bytes()
    require(sha(stage_data) == "a1cbb1b0cce4bc654a69a8e2c998ba01d914b42db49dff90c411f0d28ff591d1", "stage pin")
    stage = json.loads(stage_data)
    require(stage["kind"] == "v4-source-candidate-stage", "stage kind")
    require(stage["fileCount"] == 18 == len(stage["files"]), "stage file denominator")
    require(stage["registryPromotion"] is False, "stage registry promotion")
    expected_counts = {
        "components": 9,
        "demandsWithComponents": 8,
        "newFullDemandResolutions": 0,
        "observedNominalComponents": 2,
        "proposedComponents": 7,
        "registryMappedRows": 0,
    }
    require(stage["counts"] == expected_counts, "stage counts")
    total = 0
    for item in stage["files"]:
        rel = item["path"]
        p = ROOT / rel
        require(not p.is_symlink() and p.is_file(), f"stage file unavailable: {rel}")
        require(ROOT in p.resolve().parents, f"stage path escapes repo: {rel}")
        data = p.read_bytes()
        require(len(data) == item["bytes"], f"stage bytes: {rel}")
        require(sha(data) == item["sha256"], f"stage hash: {rel}")
        total += len(data)
    require(total == stage["totalBytes"], "stage total bytes")
    return {"sha256": "sha256:" + sha(stage_data), "fileCount": len(stage["files"]), "totalBytes": total}


def load_exact_validator():
    path = ROOT / "factory/catalogue/module-provenance-spike/exact_validator.py"
    spec = importlib.util.spec_from_file_location("v4_exact_validator", path)
    require(spec is not None and spec.loader is not None, "validator import")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def verify_inputs(mapping: dict, pins: dict) -> dict:
    require(pins["kind"] == "v4-exact-input-pins", "pin kind")
    require(pins["mapping"]["path"] == "factory/shell/extended-demand-mapping-v4/mapping-v4.json", "mapping pin path")
    require(pins["mapping"]["sha256"] == "dc6ef940bab027639777c62dc7e1f657aaf777d5e702d7dee30cc74ca330ec0b", "mapping pin sha")
    require(pins["priorMappingPreserved"] == mapping["preservation"]["v3Mapping"], "prior mapping pin")
    require(len(pins["inputs"]) == 24, "input denominator")
    joined = 0
    for item in pins["inputs"]:
        frozen(item["path"], item["sha256"], item["bytes"])
        joined += 1
    for item in mapping["inputs"]:
        frozen(item["path"], item["sha256"], item["bytes"])
    return {"inputRefs": joined, "mappingInputs": len(mapping["inputs"])}


def verify_rows(mapping: dict, v3: dict) -> tuple[list[dict], dict]:
    require(len(mapping["rows"]) == 107, "v4 row denominator")
    require(len(v3["rows"]) == 107, "v3 row denominator")
    old = {r["rowKey"]: r for r in v3["rows"]}
    require(len(old) == 107, "v3 row keys")
    components = []
    for row in mapping["rows"]:
        key = row["rowKey"]
        require(key in old, f"new row key: {key}")
        for field, value in old[key].items():
            require(row.get(field) == value, f"v3 field changed: {key}.{field}")
        e = row["v4Evidence"]
        require(e["fullDemandResolved"] is False and e["registryPromotion"] is False, f"promotion: {key}")
        require(e["components"] is not None, f"components absent: {key}")
        components.extend(e["components"])
    require(mapping["denominator"]["extendedDemandRows"] == 107, "denominator extended rows")
    require(mapping["denominator"]["registryMappedRows"] == 0, "denominator registry rows")
    require(mapping["componentCounts"] == {
        "components": 9,
        "demandsWithComponents": 8,
        "newFullDemandResolutions": 0,
        "observedNominalComponents": 2,
        "proposedComponents": 7,
        "registryMappedRows": 0,
    }, "component counts")
    require(len(components) == 9, "component closure")
    require(len({c["rowKey"] for c in components}) == 8, "component demand closure")
    return components, {"rows": 107, "preservedRows": 107}


def verify_sources(mapping: dict) -> tuple[dict, dict[str, bytes]]:
    manifest = load_json(PACKET / "evidence/source-snapshot-manifest.json")
    require(manifest["kind"] == "current-journey-source-capture-v4", "snapshot kind")
    require(len(manifest["sources"]) == 5, "snapshot denominator")
    source_info = {s["evidenceId"]: s for s in manifest["sources"]}
    require(set(source_info) == {"legal-gate", "media-player", "pdf-viewer", "settings-panel", "slice-editor"}, "snapshot identities")
    source_bytes: dict[str, bytes] = {}
    for evidence, item in source_info.items():
        snap = item["snapshot"]
        data = frozen(snap["path"], snap["sha256"], snap["bytes"])
        source_bytes[evidence] = data
        require(item["matchesV3Snapshot"] == (item["v3SnapshotHash"] == snap["sha256"]), f"v3 match flag: {evidence}")
    require(sum(not s["matchesV3Snapshot"] for s in manifest["sources"]) == 1, "intentional source mismatch count")
    require(source_info["settings-panel"]["matchesV3Snapshot"] is False, "settings mismatch witness")
    require(all(source_info[x]["matchesV3Snapshot"] for x in source_info if x != "settings-panel"), "unexpected source mismatch")

    seen = set()
    language_counts = {"Swift": 0, "TypeScript/React": 0}
    for row in mapping["rows"]:
        for c in row["v4Evidence"]["components"]:
            j = c["journeySource"]
            evidence = j["evidenceId"]
            require(evidence in source_info, f"unknown source evidence: {evidence}")
            src = source_info[evidence]
            require(j["snapshot"] == src["snapshot"], f"source snapshot join: {c['component']}")
            require(j["originalPath"] == src["originalPath"], f"source path join: {c['component']}")
            lines = source_bytes[evidence].decode("utf-8").splitlines()
            require(1 <= j["line"] <= len(lines), f"source line range: {c['component']}")
            require(lines[j["line"] - 1] == j["exactLine"], f"source exact line: {c['component']}")
            require(j["language"] in language_counts, f"source language: {c['component']}")
            language_counts[j["language"]] += 1
            identity = (evidence, j["line"], j["exactLine"])
            require(identity not in seen, f"duplicate source mapping: {identity}")
            seen.add(identity)
    require(language_counts == {"Swift": 2, "TypeScript/React": 7}, "source language counts")
    return {"sources": len(source_info), "languageCounts": language_counts, "intentionalMismatch": "settings-panel", "distinctMappings": len(seen)}, source_bytes


def verify_sdk(mapping: dict, components: list[dict]) -> dict:
    validator = load_exact_validator()
    entities_cache: dict[str, list[dict]] = {}
    catalogue_data = load_json(ROOT / "factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json")
    catalogue = catalogue_data["symbols"]
    by_usr: dict[str, list[dict]] = {}
    for symbol in catalogue:
        by_usr.setdefault(symbol.get("usr"), []).append(symbol)
    joins = []
    expected = {
        "Binding": "s:7SwiftUI7BindingV",
        "Button": "s:7SwiftUI6ButtonV",
        "TextField": "s:7SwiftUI9TextFieldV",
        "FocusState": "s:7SwiftUI10FocusStateV",
        "RadioGroupPickerStyle": "s:7SwiftUI21RadioGroupPickerStyleV",
        "CheckboxToggleStyle": "s:7SwiftUI19CheckboxToggleStyleV",
        "NavigationSplitView": "s:7SwiftUI19NavigationSplitViewV",
        "Slider": "s:7SwiftUI6SliderV",
    }
    for c in components:
        b = c["sdkBinding"]
        name = c["component"]
        usr = b["usr"]
        require(usr == expected[name], f"component USR: {name}")
        require(usr == b["compilerRecord"]["usr"] == c["catalogueIdentity"]["usr"] == c["catalogueIdentity"]["precise"], f"USR join: {name}")
        require(b["physicalModule"] in {"SwiftUI", "SwiftUICore"}, f"physical module: {name}")
        require(b["physicalModule"] == ("SwiftUICore" if name == "Binding" else "SwiftUI"), f"physical source owner: {name}")
        source_data = frozen(b["sourceInput"]["path"], b["sourceInput"]["sha256"], b["sourceInput"]["bytes"])
        require(b["installedSdkSourceReference"]["sha256"].removeprefix("sha256:") == b["sourceInput"]["sha256"], f"installed source hash: {name}")
        require(b["installedSdkSourceReference"]["bytes"] == b["sourceInput"]["bytes"], f"installed source bytes: {name}")
        raw_data = frozen(b["rawIndexInput"]["path"], b["rawIndexInput"]["sha256"], b["rawIndexInput"]["bytes"])
        req_data = frozen(b["requestInput"]["path"], b["requestInput"]["sha256"], b["requestInput"]["bytes"])
        req_text = req_data.decode("utf-8")
        require("key.request: source.request.indexsource" in req_text, f"request kind: {name}")
        require("key.sourcefile:" in req_text and "-target" in req_text and b["physicalModule"] in req_text, f"request source binding: {name}")
        if b["physicalModule"] not in entities_cache:
            entities_cache[b["physicalModule"]] = validator.entities(raw_data.decode("utf-8"))
        candidates = [e for e in entities_cache[b["physicalModule"]] if e.get("usr") == usr]
        require(len(candidates) == 1, f"raw USR cardinality: {name}")
        rec = candidates[0]
        require(rec == b["compilerRecord"], f"raw/compiler record: {name}")
        source_lines = source_data.decode("utf-8").splitlines()
        line = b["sdkLine"]
        col = b["sdkColumn"]
        require(line == b["compilerRecord"]["line"] and col == b["compilerRecord"]["column"], f"line cursor: {name}")
        require(source_lines[line - 1] == b["sdkExactLine"], f"SDK exact line: {name}")
        require(source_lines[line - 1][col - 1:].startswith(name), f"SDK name cursor: {name}")
        require(b["compilerRecord"]["kind"] == "source.lang.swift.decl.struct", f"SDK kind: {name}")
        require(b["compilerRecord"]["effective_access"] == "source.decl.effective_access.public", f"SDK access: {name}")
        require(b["compilerRecord"]["sourcekitContext"] == [], f"SDK context: {name}")
        symbols = by_usr.get(usr, [])
        require(len(symbols) == 1, f"catalogue USR cardinality: {name}")
        require(symbols[0] == c["catalogueIdentity"], f"catalogue identity: {name}")
        require(symbols[0]["path"] == f"SwiftUI.{name}" and symbols[0]["status"] == "inventory", f"catalogue path/status: {name}")
        joins.append({"component": name, "usr": usr, "physicalModule": b["physicalModule"], "line": line, "column": col, "cataloguePath": symbols[0]["path"], "rawRecordCount": len(candidates)})
    return {"components": len(joins), "uniqueUSRs": len({j["usr"] for j in joins}), "rawRecords": len(joins), "catalogueRecords": len(joins), "journeySDKJoins": joins}


def verify_faults() -> dict:
    controls = load_json(PACKET / "evidence/controls.json")
    required = {"raw-usr", "raw-name", "raw-kind", "raw-line", "raw-column", "raw-effective_access", "raw-duplicate", "raw-owner-context", "source-access", "source-owner-name"}
    require(controls["kind"] == "v4-sdk-source-semantic-controls", "controls kind")
    require(len(controls["controls"]) == 10 and controls["passed"] == 10, "control denominator")
    require({c["control"] for c in controls["controls"]} == required, "control names")
    for c in controls["controls"]:
        require(c["changedActualBytes"] is True and c["acceptedBaseline"] is True and c["rejected"] is True, f"control outcome: {c['control']}")
    process = load_json(PACKET / "evidence/test-process.json")
    stdout = (PACKET / "evidence/test.stdout.txt").read_bytes()
    stderr = (PACKET / "evidence/test.stderr.txt").read_bytes()
    require(process["returncode"] == 0, "test process return code")
    require(sha(stdout) == process["stdoutSha256"] and sha(stderr) == process["stderrSha256"], "test output pins")
    require((PACKET / "evidence/test.exit-code.txt").read_text() == "0\n", "exit receipt")
    out = stdout.decode()
    require("10/10 changed raw/source semantic controls passed" in out and "107 rows preserved" in out and "9 components bound" in out, "test stdout claim")
    require(process["argv"][0].endswith("python3.14") and process["cwd"] == str(ROOT), "process provenance")
    return {"faultControls": 10, "processReturncode": 0, "processArgv": process["argv"], "processCwd": process["cwd"], "stdoutSha256": "sha256:" + sha(stdout), "stderrSha256": "sha256:" + sha(stderr)}


def main() -> None:
    stage = verify_stage()
    mapping = load_json(PACKET / "mapping-v4.json")
    pins = load_json(PACKET / "raw-pins-v4.json")
    v3 = load_json(ROOT / "factory/shell/extended-demand-mapping-v3/mapping-v3.json")
    input_result = verify_inputs(mapping, pins)
    components, rows = verify_rows(mapping, v3)
    source_result, _ = verify_sources(mapping)
    sdk_result = verify_sdk(mapping, components)
    faults = verify_faults()
    result = {
        "kind": "independent-review-extended-demand-mapping-v4",
        "status": "PASS",
        "scope": "offline frozen source/catalogue/raw journey joins; no registry or full-demand promotion",
        "stage": stage,
        "mappingSha256": "sha256:" + sha((PACKET / "mapping-v4.json").read_bytes()),
        "rows": rows,
        "inputs": input_result,
        "source": source_result,
        "sdk": sdk_result,
        "faults": faults,
        "registryPromotion": False,
        "fullDemandResolution": False,
        "disposition": "candidate source mappings only; registry/native acceptance remains held",
    }
    (OUT / "review.json").write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
