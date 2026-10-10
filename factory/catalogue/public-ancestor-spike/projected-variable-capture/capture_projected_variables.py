#!/usr/bin/env python3
"""Capture byte-exact SourceKit cursor evidence for projected SwiftUI variables."""
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
SOURCE = SDK / "System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"
TOOLCHAIN = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin")
SOURCEKIT = TOOLCHAIN / "sourcekit-lsp"
DEMANGLE = TOOLCHAIN / "swift-demangle"
XCRUN = Path("/usr/bin/xcrun")
FROZEN = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
FROZEN_SHA = "836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
RAW_ARCHIVE = ROOT / "factory/catalogue/duplicate-identity-spike/raw-record-evidence.json"
RAW_ARCHIVE_SHA = "5287ecdbd267d2d30196855233ee285914b7e6bb4c24e25dafa911386bb1c89f"
TARGET = "arm64-apple-macosx27.0"

CASES = [
    (4080, "$isOn", "ToggleStyleConfiguration"),
    (5533, "$isExpanded", "DisclosureGroupStyleConfiguration"),
    (9717, "$document", "ReferenceFileDocumentConfiguration"),
    (23750, "$document", "FileDocumentConfiguration"),
    (31446, "switch", "ToggleStyle"),
    (32822, "$selection", "DatePickerStyleConfiguration"),
]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def digest_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run(case: dict, request: Path, output: Path, stderr: Path) -> dict:
    argv = ["xcrun", "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", str(request)]
    started = time.time()
    proc = subprocess.run(argv, cwd=ROOT, capture_output=True, check=False)
    elapsed = time.time() - started
    output.write_bytes(proc.stdout)
    stderr.write_bytes(proc.stderr)
    return {
        "argv": argv,
        "cwd": str(ROOT),
        "exitCode": proc.returncode,
        "elapsedSeconds": round(elapsed, 3),
        "dispatcher": {"path": str(XCRUN), "sha256": "sha256:" + sha(XCRUN)},
        "tool": {"path": str(SOURCEKIT), "sha256": "sha256:" + sha(SOURCEKIT)},
        "request": {"path": str(request.relative_to(ROOT)), "sha256": "sha256:" + sha(request), "bytes": request.stat().st_size},
        "stdout": {"path": str(output.relative_to(ROOT)), "sha256": "sha256:" + sha(output), "bytes": output.stat().st_size},
        "stderr": {"path": str(stderr.relative_to(ROOT)), "sha256": "sha256:" + sha(stderr), "bytes": stderr.stat().st_size},
    }


def parse_cursor(data: bytes) -> dict:
    text = data.decode("utf-8", errors="strict")
    fields = {}
    for key in ("kind", "name", "usr", "line", "column", "filepath", "offset", "length", "modulename", "annotated_decl", "fully_annotated_decl"):
        m = re.search(rf"^  key\.{re.escape(key)}: (.*)$", text, re.MULTILINE)
        if m:
            value = m.group(1).strip().rstrip(",")
            if key in {"line", "column", "offset", "length"}:
                value = int(value)
            elif value.startswith('"') and value.endswith('"'):
                value = json.loads(value)
            fields[key] = value
    return {"fields": fields, "raw": text}


def main() -> int:
    if not FROZEN.is_file() or sha(FROZEN) != FROZEN_SHA:
        raise SystemExit("frozen link evidence changed or missing")
    source_bytes = SOURCE.read_bytes()
    source_text = source_bytes.decode("utf-8")
    source_hash = digest_bytes(source_bytes)
    frozen_link = json.loads(FROZEN.read_text(encoding="utf-8"))
    raw_archive = json.loads(RAW_ARCHIVE.read_text(encoding="utf-8"))
    requests = HERE / "requests"
    outputs = HERE / "outputs"
    receipts = HERE / "receipts"
    for d in (requests, outputs, receipts):
        d.mkdir(exist_ok=True)
    rows = []
    lines = source_text.splitlines(keepends=True)
    for line_no, name, context in CASES:
        line = lines[line_no - 1].rstrip("\r\n")
        if name not in line:
            raise SystemExit(f"{name!r} absent from source line {line_no}")
        line_start = sum(len(x.encode("utf-8")) for x in lines[: line_no - 1])
        name_offset = line_start + len(line[: line.index(name)].encode("utf-8"))
        stem = f"line-{line_no}-{name.replace('$', 'projected-').replace('`', '').replace(' ', '-') }"
        request = requests / f"{stem}.yaml"
        request.write_text("{\n key.request: source.request.cursorinfo,\n key.sourcefile: " + json.dumps(str(SOURCE)) + ",\n key.offset: " + str(name_offset) + ",\n key.compilerargs: [ " + ", ".join(json.dumps(x) for x in (str(SOURCE), "-sdk", str(SDK), "-target", TARGET, "-module-name", "SwiftUI")) + " ]\n}\n", encoding="utf-8")
        output = outputs / f"{stem}.txt"
        err = receipts / f"{stem}.stderr"
        case = {"line": line_no, "name": name, "context": context, "sourceLine": line, "lineStartByteOffset": line_start, "nameByteOffset": name_offset}
        receipt = run(case, request, output, err)
        cursor = parse_cursor(output.read_bytes())
        link_rows = [r for r in frozen_link["rows"] if r.get("line") == line_no and any(o.get("name") == name for m in r.get("indexMatches", []) for o in m.get("occurrences", []))]
        if len(link_rows) != 1:
            raise SystemExit(f"expected one frozen link row for {line_no} {name}, got {len(link_rows)}")
        link_row = link_rows[0]
        occurrences = [o for m in link_row["indexMatches"] for o in m.get("occurrences", []) if o.get("name") == name]
        duplicate_raw = None
        if line_no != 31446:
            archived = [r for r in raw_archive["rows"] if r.get("line") == line_no and r.get("name") == name]
            if len(archived) != 1:
                raise SystemExit(f"expected one duplicate archive row for {line_no} {name}, got {len(archived)}")
            duplicate_raw = {"path": str(RAW_ARCHIVE.relative_to(ROOT)), "sha256": "sha256:" + sha(RAW_ARCHIVE), "row": archived[0]["raw"]}
        case.update({
            "request": str(request.relative_to(ROOT)),
            "requestSha256": "sha256:" + sha(request),
            "response": str(output.relative_to(ROOT)),
            "responseSha256": "sha256:" + sha(output),
            "cursor": cursor,
            "receipt": receipt,
            "frozenLinkRow": {"auditRowKey": link_row["auditRowKey"], "name": link_row["name"], "kind": link_row["kind"], "line": link_row["line"], "module": link_row["module"], "context": link_row["context"], "signature": link_row["signature"], "compilerEvidence": link_row["compilerEvidence"], "occurrences": occurrences},
            "rawIdentity": {"source": "frozen index-interface output", "occurrences": occurrences, "duplicateArchive": duplicate_raw},
        })
        rows.append(case)
    raw_usrs = sorted({o["usr"] for r in rows for o in r["rawIdentity"]["occurrences"]} | {r["cursor"]["fields"].get("usr") for r in rows})
    raw_usrs = [u for u in raw_usrs if u]
    usr_input = HERE / "receipts/raw-symbol-input.txt"
    usr_output = HERE / "outputs/raw-symbol-tree.txt"
    usr_stderr = HERE / "receipts/raw-symbol-tree.stderr"
    usr_input.write_text("\n".join(raw_usrs) + "\n", encoding="utf-8")
    demangle = subprocess.run([str(DEMANGLE), "--expand"], input=usr_input.read_bytes(), capture_output=True, check=False, cwd=ROOT)
    usr_output.write_bytes(demangle.stdout)
    usr_stderr.write_bytes(demangle.stderr)
    demangle_receipt = {
        "argv": [str(DEMANGLE), "--expand"], "cwd": str(ROOT), "exitCode": demangle.returncode,
        "tool": {"path": str(DEMANGLE), "sha256": "sha256:" + sha(DEMANGLE)},
        "stdin": {"path": str(usr_input.relative_to(ROOT)), "sha256": "sha256:" + sha(usr_input), "bytes": usr_input.stat().st_size},
        "stdout": {"path": str(usr_output.relative_to(ROOT)), "sha256": "sha256:" + sha(usr_output), "bytes": usr_output.stat().st_size},
        "stderr": {"path": str(usr_stderr.relative_to(ROOT)), "sha256": "sha256:" + sha(usr_stderr), "bytes": usr_stderr.stat().st_size},
    }
    evidence = {
        "kind": "swiftui-projected-variable-cursor-capture",
        "version": 1,
        "status": "review-only",
        "promotionsMade": 0,
        "inputs": {
            "frozenLinkEvidence": {"path": str(FROZEN.relative_to(ROOT)), "sha256": "sha256:" + sha(FROZEN), "expectedSha256": "sha256:" + FROZEN_SHA},
            "frozenRawArchive": {"path": str(RAW_ARCHIVE.relative_to(ROOT)), "sha256": "sha256:" + sha(RAW_ARCHIVE), "expectedSha256": "sha256:" + RAW_ARCHIVE_SHA},
            "source": {"path": str(SOURCE), "sha256": "sha256:" + source_hash, "bytes": len(source_bytes)},
            "sdk": str(SDK),
            "target": TARGET,
        },
        "toolchain": {
            "xcode": "Xcode 27.0 (27A266a)",
            "swift": "Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)",
            "sourcekitLsp": {"path": str(SOURCEKIT), "sha256": "sha256:" + sha(SOURCEKIT)},
            "swiftDemangle": {"path": str(DEMANGLE), "sha256": "sha256:" + sha(DEMANGLE)},
            "xcrun": {"path": str(XCRUN), "sha256": "sha256:" + sha(XCRUN)},
        },
        "rows": rows,
        "rawSymbolTree": {"usrs": raw_usrs, "receipt": demangle_receipt},
        "summary": {"requestedRows": len(rows), "successfulRequests": sum(r["receipt"]["exitCode"] == 0 for r in rows), "cursorResults": sum(bool(r["cursor"]["fields"]) for r in rows)},
    }
    (HERE / "projected-variable-evidence.json").write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
