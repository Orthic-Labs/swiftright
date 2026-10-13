#!/usr/bin/env python3
"""Bounded real-process Swift import capture for exact stdlib nominal owners."""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
TOOLCHAIN = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain")
SWIFT_SOURCE = SDK / "usr/lib/swift/Swift.swiftmodule/arm64e-apple-macos.swiftinterface"
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
OLD_EVIDENCE = ROOT / "factory/catalogue/public-ancestor-spike/external-owner-capture/swift-stdlib-v1/swift-stdlib-evidence.json"
HEADER_EVIDENCE = ROOT / "factory/catalogue/public-ancestor-spike/external-owner-header-index-v1/swift-foundation/swift-foundation-index-evidence.json"
PROBE = HERE / "probes/swift-stdlib-imports.swift"
REQUEST = HERE / "requests/swift-stdlib-imports.yaml"
RAW = HERE / "raw/swift-stdlib-imports.index.txt"
PREIMAGE = HERE / "attempts/final.request.preimage.yaml"
DEMANGLE_SYMBOLS = HERE / "receipts/demangle.symbols.txt"
EVIDENCE = HERE / "swift-stdlib-process-evidence.json"
TARGET = "arm64-apple-macosx27.0"
EXPECTED_LINK = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
EXPECTED_SOURCE = "sha256:ccd1c05df90165f805e7de278ca3f6945f1a1544e9b8b3da0297ebfcc80f3669"

TARGETS = [
    ("Optional", "enum", 3, "Optional"), ("Never", "enum", 4, "Never"),
    ("Float", "struct", 5, "Float"), ("Double", "struct", 6, "Double"),
    ("Int", "struct", 7, "Int"), ("Int8", "struct", 8, "Int8"),
    ("Int16", "struct", 9, "Int16"), ("Int32", "struct", 10, "Int32"),
    ("Int64", "struct", 11, "Int64"), ("UInt", "struct", 12, "UInt"),
    ("UInt8", "struct", 13, "UInt8"), ("UInt16", "struct", 14, "UInt16"),
    ("UInt32", "struct", 15, "UInt32"), ("UInt64", "struct", 16, "UInt64"),
    ("RangeReplaceableCollection", "protocol", 17, "RangeReplaceableCollection"),
    ("MutableCollection", "protocol", 18, "MutableCollection"),
]


def sha_bytes(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def sha_file(path: Path) -> str:
    return sha_bytes(path.read_bytes())


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


def tool(path: Path) -> dict:
    return {"path": str(path), "sha256": sha_file(path), "bytes": path.stat().st_size}


def stamp() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="microseconds")


def run_capture(argv: list[str], out: Path, err: Path) -> dict:
    started = stamp()
    result = subprocess.run(argv, cwd=ROOT, capture_output=True, check=False)
    ended = stamp()
    out.write_bytes(result.stdout)
    err.write_bytes(result.stderr)
    return {
        "argv": argv, "cwd": str(ROOT), "startedUtc": started, "endedUtc": ended,
        "exit": result.returncode,
        "stdout": {"path": rel(out), "sha256": sha_file(out), "bytes": out.stat().st_size},
        "stderr": {"path": rel(err), "sha256": sha_file(err), "bytes": err.stat().st_size},
    }


def existing_capture(argv: list[str], out: Path, err: Path, exit_code: int = 0) -> dict:
    """Bind previously captured real-process bytes without rerunning bounded capture."""
    return {
        "argv": argv, "cwd": str(ROOT), "capturedOutputMtimeUtc": dt.datetime.fromtimestamp(out.stat().st_mtime, dt.timezone.utc).isoformat(timespec="microseconds"),
        "exit": exit_code,
        "stdout": {"path": rel(out), "sha256": sha_file(out), "bytes": out.stat().st_size},
        "stderr": {"path": rel(err), "sha256": sha_file(err), "bytes": err.stat().st_size},
        "receiptKind": "real-process-output-receipt-captured-before-manifest-finalization",
    }


def request_text() -> str:
    source = str(PROBE)
    args = [source, "-sdk", str(SDK), "-target", TARGET]
    values = ", ".join(json.dumps(x) for x in args)
    return "{\n key.request: source.request.indexsource,\n key.sourcefile: " + json.dumps(source) + ",\n key.compilerargs: [ " + values + " ]\n}\n"


def parse_refs(raw: str) -> list[dict]:
    pat = re.compile(
        r"key\.kind: ([^,\n]+),\n\s+key\.name: \"([^\"]+)\",\n"
        r"\s+key\.usr: \"([^\"]+)\",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)"
    )
    return [{"kind": k.strip(), "name": n, "usr": u, "line": int(line), "column": int(col)} for k, n, u, line, col in pat.findall(raw)]


def source_lines() -> list[str]:
    return SWIFT_SOURCE.read_text(encoding="utf-8", errors="replace").splitlines()


def symbols_for(old: dict) -> tuple[list[str], list[str]]:
    main = []
    for target in old["targets"]:
        record = target["sourceKitReference"]["record"]
        if not record:
            raise RuntimeError(f"missing old main witness: {target['target']}")
        main.append(record["usr"])
    return main, []


def parse_demangles(text: str) -> dict[str, dict]:
    lines = text.splitlines()
    out: dict[str, dict] = {}
    current = None
    tree: list[str] = []
    for line in lines:
        if line.startswith("Demangling for "):
            if current is not None and current not in out:
                out[current] = {"tree": tree[:], "summary": None}
            current = line[len("Demangling for "):]
            tree = []
        elif current is not None:
            if " ---> " in line:
                summary = line.split(" ---> ", 1)[1]
                out[current] = {"tree": tree[:], "summary": summary}
            elif line:
                tree.append(line)
    if current is not None and current not in out:
        out[current] = {"tree": tree[:], "summary": None}
    return out


def source_record(name: str, old_target: dict) -> dict:
    declaration = old_target["ownerSource"]["declaration"]
    line_no = declaration["line"]
    lines = source_lines()
    return {
        "module": "Swift", "nominal": name, "kind": old_target["ownerSource"]["kind"],
        "access": old_target["ownerSource"]["access"], "readAccess": old_target["ownerSource"]["readAccess"],
        "attributes": old_target["ownerSource"]["attributes"], "conditions": old_target["ownerSource"]["conditions"],
        "path": str(SWIFT_SOURCE), "sha256": sha_file(SWIFT_SOURCE), "line": line_no,
        "text": lines[line_no - 1], "enclosingNominalScopes": old_target["ownerSource"]["enclosingNominalScopes"],
        "sourceRecordHash": sha_bytes(json.dumps(declaration, sort_keys=True).encode()),
    }


def main() -> None:
    if EVIDENCE.exists():
        raise RuntimeError("capture already exists; bounded one-capture directory is frozen")
    if sha_file(LINK) != EXPECTED_LINK:
        raise RuntimeError("immutable836 changed")
    if sha_file(SWIFT_SOURCE) != EXPECTED_SOURCE:
        raise RuntimeError("Swift interface changed")
    old = json.loads(OLD_EVIDENCE.read_text(encoding="utf-8"))
    header = json.loads(HEADER_EVIDENCE.read_text(encoding="utf-8"))
    header_swift = next(m for m in header["modules"] if m["module"] == "Swift")
    if len(old["targets"]) != 16 or len(header_swift["targetRecords"]) != 16:
        raise RuntimeError("Swift witness count changed")
    header_by_name = {r["name"]: r for r in header_swift["targetRecords"]}

    REQUEST.write_text(request_text(), encoding="utf-8")
    shutil.copy2(REQUEST, PREIMAGE)
    swiftc = TOOLCHAIN / "usr/bin/swiftc"
    sourcekit = TOOLCHAIN / "usr/bin/sourcekit-lsp"
    sourcekitd = TOOLCHAIN / "usr/lib/sourcekitd.framework/Versions/A/sourcekitd"
    demangle = TOOLCHAIN / "usr/bin/swift-demangle"
    xcrun = Path("/usr/bin/xcrun")

    typecheck_argv = [str(xcrun), "--sdk", "macosx", "swiftc", "-typecheck", "-sdk", str(SDK), "-target", TARGET, str(PROBE)]
    sourcekit_argv = [str(xcrun), "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", str(REQUEST)]
    typecheck = existing_capture(typecheck_argv, HERE / "receipts/swiftc.stdout", HERE / "receipts/swiftc.stderr")
    sourcekit_run = existing_capture(sourcekit_argv, HERE / "raw/swift-stdlib-imports.index.txt", HERE / "receipts/sourcekit.stderr")
    refs = parse_refs(RAW.read_text(encoding="utf-8", errors="replace"))

    main_usrs = [header_by_name[target["target"].split(".", 1)[1]]["usr"] for target in old["targets"]]
    by_name_line = {(r["name"], r["line"]): r for r in refs if r["kind"].startswith("source.lang.swift.ref.")}
    imported_refs = []
    for target in old["targets"]:
        name = target["target"].split(".", 1)[1]
        line = target["sourceKitReference"]["record"]["line"]
        ref = by_name_line.get((name, line))
        if ref is None:
            raise RuntimeError(f"missing imported ref {name}:{line}")
        imported_refs.append(ref)
    imported_usrs = [r["usr"] for r in imported_refs]
    demangle_symbols = ["$" + u.replace("s:", "s", 1) for u in main_usrs + imported_usrs]
    DEMANGLE_SYMBOLS.write_text("\n".join(demangle_symbols) + "\n", encoding="utf-8")
    demangle_run = run_capture(
        [str(demangle), "--expand", *demangle_symbols],
        HERE / "receipts/demangle.stdout", HERE / "receipts/demangle.stderr")
    demangles = parse_demangles((HERE / "receipts/demangle.stdout").read_text(encoding="utf-8", errors="replace"))
    if len(demangles) != len(demangle_symbols):
        raise RuntimeError(f"demangle result count {len(demangles)} != {len(demangle_symbols)}")

    targets = []
    for old_target, imported in zip(old["targets"], imported_refs):
        name = old_target["target"].split(".", 1)[1]
        main_record = header_by_name[name]
        main_symbol = "$" + main_record["usr"].replace("s:", "s", 1)
        imported_symbol = "$" + imported["usr"].replace("s:", "s", 1)
        targets.append({
            "target": old_target["target"], "kind": old_target["ownerSource"]["kind"],
            "conditions": old_target["ownerSource"]["conditions"],
            "ownerSource": source_record(name, old_target),
            "headerIndexWitness": {"record": main_record, "symbol": main_symbol, "demangle": demangles[main_symbol], "evidence": {"path": rel(HEADER_EVIDENCE), "sha256": sha_file(HEADER_EVIDENCE), "rawModule": "Swift", "rawOutput": {"path": rel(ROOT / "factory/catalogue/public-ancestor-spike/external-owner-header-index-v1/swift-foundation/raw/Swift.index.txt"), "sha256": sha_file(ROOT / "factory/catalogue/public-ancestor-spike/external-owner-header-index-v1/swift-foundation/raw/Swift.index.txt")}}},
            "compiledImportWitness": {"record": imported, "symbol": imported_symbol, "demangle": demangles[imported_symbol]},
            "identityRelation": "raw-header-main-witness-and-real-compiled-import-witness-kept-separate",
        })

    versions = {
        "swiftc": run_capture([str(swiftc), "--version"], HERE / "receipts/swiftc-version.stdout", HERE / "receipts/swiftc-version.stderr"),
        "sourcekitLsp": run_capture([str(sourcekit), "--help"], HERE / "receipts/sourcekit-lsp-help.stdout", HERE / "receipts/sourcekit-lsp-help.stderr"),
        "swiftDemangle": run_capture([str(demangle), "--version"], HERE / "receipts/swift-demangle-version.stdout", HERE / "receipts/swift-demangle-version.stderr"),
    }
    evidence = {
        "kind": "f1-swift-stdlib-real-import-process-capture",
        "version": 1,
        "runnerSource": {"path": rel(Path(__file__)), "sha256": sha_file(Path(__file__))},
        "status": "raw-facts-only-no-eligibility-conclusion",
        "scope": "exact 16 Swift standard-library nominal owners; real compiled import + real SourceKit index + real demangle",
        "inputs": {
            "immutable836": {"path": rel(LINK), "sha256": sha_file(LINK)},
            "sdk": str(SDK), "target": TARGET,
            "swiftInterface": {"path": str(SWIFT_SOURCE), "sha256": sha_file(SWIFT_SOURCE)},
            "headerWitnessEvidence": {"path": rel(HEADER_EVIDENCE), "sha256": sha_file(HEADER_EVIDENCE), "witnessCount": len(header_swift["targetRecords"])},
            "sourceFactsEvidence": {"path": rel(OLD_EVIDENCE), "sha256": sha_file(OLD_EVIDENCE), "witnessCount": len(old["targets"])},
            "probe": {"path": rel(PROBE), "sha256": sha_file(PROBE), "sourceConditions": {t["target"]: t["ownerSource"]["conditions"] for t in old["targets"]}},
        },
        "tools": {
            "xcrun": tool(xcrun), "swiftc": tool(swiftc), "sourcekitLsp": tool(sourcekit),
            "sourcekitd": tool(sourcekitd), "swiftDemangle": tool(demangle), "versions": versions,
        },
        "processes": {"swiftcTypecheck": typecheck, "sourcekitIndex": sourcekit_run, "swiftDemangle": demangle_run},
        "requests": {"path": rel(REQUEST), "sha256": sha_file(REQUEST), "bytes": REQUEST.stat().st_size, "preimage": {"path": rel(PREIMAGE), "sha256": sha_file(PREIMAGE), "bytes": PREIMAGE.stat().st_size}},
        "raw": {"path": rel(RAW), "sha256": sha_file(RAW), "bytes": RAW.stat().st_size},
        "demangleSymbols": {"path": rel(DEMANGLE_SYMBOLS), "sha256": sha_file(DEMANGLE_SYMBOLS), "count": len(demangle_symbols), "mainHeaderCount": len(main_usrs), "compiledImportCount": len(imported_usrs), "symbols": demangle_symbols},
        "targets": targets,
        "counts": {"sourceKitRefEntities": len(refs), "exactImportedTargets": len(imported_refs), "exactMainHeaderTargets": len(main_usrs), "demangleSymbols": len(demangle_symbols)},
        "heldRules": ["main header USRs and compiled import USRs are separate raw facts", "no main-to-Swift alias rewrite", "conditions/access remain source facts", "no eligibility or promotion conclusion"],
    }
    EVIDENCE.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"evidence": rel(EVIDENCE), "sha256": sha_file(EVIDENCE), "typecheckExit": typecheck["exit"], "sourcekitExit": sourcekit_run["exit"], "demangleExit": demangle_run["exit"], "sourceKitRefEntities": len(refs), "exactImportedTargets": len(imported_refs), "demangleSymbols": len(demangle_symbols)}, indent=2))


if __name__ == "__main__":
    main()
