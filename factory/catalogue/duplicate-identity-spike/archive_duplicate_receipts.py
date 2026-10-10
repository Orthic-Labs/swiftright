#!/usr/bin/env python3
"""Archive exact duplicate SourceKit records plus bounded compiler receipts."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import re
import subprocess
from pathlib import Path
from typing import Any


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SPIKE = ROOT / "factory/catalogue/compiler-cursor-spike"
EDGE = ROOT / "factory/catalogue/compiler-edge-spike"
LINK = SPIKE / "link-evidence.json"
REQUEST = SPIKE / "request-index-interface.yaml"
ORIGINAL_RESPONSE = SPIKE / "index-interface-output.txt"
INTERFACE = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface")
SDK = "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"
TARGET = "arm64-apple-macosx27.0"
TOOLCHAIN = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain")
SWIFTC = TOOLCHAIN / "usr/bin/swiftc"
SOURCEKIT_LSP = TOOLCHAIN / "usr/bin/sourcekit-lsp"
DEMANGLE = TOOLCHAIN / "usr/bin/swift-demangle"
XCRUN = Path("/usr/bin/xcrun")
EXPECTED_LINK = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
SPECS = [
    (4080, "$isOn", "ToggleStyleConfiguration", 4067),
    (5533, "$isExpanded", "DisclosureGroupStyleConfiguration", 5507),
    (9717, "$document", "ReferenceFileDocumentConfiguration", 9703),
    (23750, "$document", "FileDocumentConfiguration", 23734),
    (32822, "$selection", "DatePickerStyleConfiguration", 32806),
]


def digest_bytes(value: bytes) -> str:
    return "sha256:" + hashlib.sha256(value).hexdigest()


def digest(path: Path) -> str:
    return digest_bytes(path.read_bytes())


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


def load_investigator() -> Any:
    path = ROOT / "factory/catalogue/residual-investigation/investigate.py"
    spec = importlib.util.spec_from_file_location("duplicate_inv", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def parse_value(value: str) -> Any:
    value = value.rstrip(",")
    if value.startswith('"'):
        return json.loads(value)
    if value in {"0", "1"}:
        return value == "1"
    if value.isdigit():
        return int(value)
    return value


def raw_records(text: str, wanted: set[tuple[int, str]]) -> list[dict[str, Any]]:
    lines = text.splitlines(keepends=True)
    stack: list[dict[str, Any]] = []
    found: list[dict[str, Any]] = []
    for index, line in enumerate(lines):
        opened = re.match(r"^(\s*)\{$", line.rstrip("\n"))
        closed = re.match(r"^(\s*)\}(?:,)?$", line.rstrip("\n"))
        if opened:
            stack.append({"indent": len(opened.group(1)), "start": index, "fields": {}})
            continue
        if closed:
            indent = len(closed.group(1))
            while stack and stack[-1]["indent"] >= indent:
                record = stack.pop()
                fields = record["fields"]
                key = (fields.get("line"), fields.get("name"))
                if (fields.get("kind", "").startswith("source.lang.swift.decl.")
                        and key in wanted):
                    raw = "".join(lines[record["start"]:index + 1])
                    found.append({
                        "line": fields.get("line"), "name": fields.get("name"),
                        "kind": fields.get("kind"), "usr": fields.get("usr"),
                        "text": raw, "sha256": digest_bytes(raw.encode("utf-8")),
                        "bytes": len(raw.encode("utf-8")),
                    })
            continue
        field = re.match(
            r"^(\s*)key\.(kind|name|usr|line|column|is_implicit|effective_access): (.*?)(?:,)?$",
            line.rstrip("\n"),
        )
        if field and stack and stack[-1]["indent"] + 2 == len(field.group(1)):
            stack[-1]["fields"][field.group(2)] = parse_value(field.group(3))
    if stack:
        raise ValueError("unbalanced SourceKit response")
    return found


def active_branch(lines: list[str], line_number: int) -> dict[str, Any]:
    stack: list[dict[str, Any]] = []
    for source_line in lines[:line_number - 1]:
        stripped = source_line.strip()
        if stripped.startswith("#if "):
            stack.append({"condition": stripped[4:], "active": True})
        elif stripped == "#else":
            if not stack:
                return {"active": False, "conditions": [], "error": "unmatched-else"}
            stack[-1]["active"] = not stack[-1]["active"]
        elif stripped.startswith("#elseif "):
            if not stack:
                return {"active": False, "conditions": [], "error": "unmatched-elseif"}
            stack[-1]["condition"] = stripped[8:]
            stack[-1]["active"] = True
        elif stripped == "#endif":
            if not stack:
                return {"active": False, "conditions": [], "error": "unmatched-endif"}
            stack.pop()
    return {"active": all(item["active"] for item in stack),
            "conditions": [item["condition"] for item in stack], "error": None}


def run_capture(argv: list[str], stdout_path: Path, stderr_path: Path) -> dict[str, Any]:
    result = subprocess.run(argv, cwd=ROOT, capture_output=True)
    stdout_path.write_bytes(result.stdout)
    stderr_path.write_bytes(result.stderr)
    return {
        "argv": argv, "cwd": str(ROOT), "exitCode": result.returncode,
        "stdout": {"path": rel(stdout_path), "sha256": digest(stdout_path), "bytes": stdout_path.stat().st_size},
        "stderr": {"path": rel(stderr_path), "sha256": digest(stderr_path), "bytes": stderr_path.stat().st_size},
    }


def tool(path: Path) -> dict[str, str]:
    return {"path": str(path), "sha256": digest(path)}


def main() -> None:
    link = json.loads(LINK.read_text(encoding="utf-8"))
    if digest(LINK) != EXPECTED_LINK:
        raise SystemExit("frozen link hash mismatch")
    inv = load_investigator()
    original_text = ORIGINAL_RESPONSE.read_text(encoding="utf-8")
    source_text = INTERFACE.read_text(encoding="utf-8")
    source_lines = source_text.splitlines()
    wanted = {(line, name) for line, name, _, _ in SPECS}

    sourcekit = run_capture(
        ["xcrun", "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", str(REQUEST)],
        HERE / "sourcekit-index-output.txt", HERE / "sourcekit-index.stderr",
    )
    sourcekit.update({"dispatcher": tool(XCRUN), "tool": tool(SOURCEKIT_LSP),
                      "request": {"path": rel(REQUEST), "sha256": digest(REQUEST)},
                      "frozenResponse": {"path": rel(ORIGINAL_RESPONSE), "sha256": digest(ORIGINAL_RESPONSE)}})
    captured_text = (HERE / "sourcekit-index-output.txt").read_text(encoding="utf-8")
    if digest(HERE / "sourcekit-index-output.txt") != digest(ORIGINAL_RESPONSE):
        raise SystemExit("fresh SourceKit response hash differs from frozen response")
    records = raw_records(captured_text, wanted)
    original_records = raw_records(original_text, wanted)
    if [(x["line"], x["name"]) for x in records] != [(x["line"], x["name"]) for x in original_records]:
        raise SystemExit("fresh SourceKit records differ from frozen record order")
    entities = inv.entities(SPIKE / "index-interface-output.txt")
    by_key: dict[tuple[int, str], list[dict[str, Any]]] = {}
    for entity in entities:
        key = (int(entity["line"]), str(entity["name"]))
        if key in wanted:
            by_key.setdefault(key, []).append(entity)
    rows: list[dict[str, Any]] = []
    for line, name, scope, scope_line in SPECS:
        candidates = [item for item in records if item["line"] == line and item["name"] == name]
        original = [item for item in original_records if item["line"] == line and item["name"] == name]
        link_row = next(row for row in link["rows"] if row.get("module") == "SwiftUI" and int(row.get("line")) == line)
        source_line = source_lines[line - 1]
        exact_lines = [idx + 1 for idx, text in enumerate(source_lines) if re.search(rf"\bvar\s+{re.escape(name)}\s*:", text)]
        raw_entities = by_key[(line, name)]
        rows.append({
            "key": ["SwiftUI", "arm64e-apple-macos.swiftinterface", line, "var"],
            "name": name, "line": line, "module": "SwiftUI", "kind": "var",
            "context": link_row.get("context", []), "signature": link_row.get("signature"),
            "source": {
                "path": rel(INTERFACE), "sha256": digest(INTERFACE), "lineText": source_line,
                "exactDeclarationLineNumbers": exact_lines, "exactDeclarationLineCount": len(exact_lines),
                "lineNameOccurrenceCount": len(re.findall(rf"\bvar\s+{re.escape(name)}\s*:", source_line)),
                "activeBranch": active_branch(source_lines, line),
                "expectedCondition": "compiler(>=5.3) && $TildeSendable",
                "enclosingScope": {"name": scope, "line": scope_line},
                "excerpt": [{"line": n, "text": source_lines[n - 1]} for n in range(max(1, line - 2), min(len(source_lines), line + 2) + 1)],
            },
            "raw": {
                "response": {"path": rel(HERE / "sourcekit-index-output.txt"), "sha256": digest(HERE / "sourcekit-index-output.txt")},
                "frozenResponse": {"path": rel(ORIGINAL_RESPONSE), "sha256": digest(ORIGINAL_RESPONSE)},
                "recordCount": len(candidates), "records": candidates,
                "frozenRecords": original,
                "fullRecordByteEqual": len(candidates) == 2 and candidates[0]["text"] == candidates[1]["text"],
                "fullRecordShaEqual": len(candidates) == 2 and candidates[0]["sha256"] == candidates[1]["sha256"],
                "parsedEntities": raw_entities,
                "parsedEntityEqual": len(raw_entities) == 2 and raw_entities[0] == raw_entities[1],
                "usrSet": sorted({entity.get("usr") for entity in raw_entities}),
            },
            "compilerEvidence": link_row.get("compilerEvidence"),
            "decision": {"status": "held", "promotion": None,
                         "reason": "Two exact-equal raw observations are preserved; bounded validator may accept only this exact duplicate shape."},
        })

    demangle_input = HERE / "usr-input.txt"
    demangle_output = HERE / "usr-demangle.txt"
    demangle_stderr = HERE / "usr-demangle.stderr"
    result = subprocess.run([str(DEMANGLE), "--expand"], input=demangle_input.read_bytes(), cwd=ROOT, capture_output=True)
    demangle_output.write_bytes(result.stdout); demangle_stderr.write_bytes(result.stderr)
    demangle_receipt = {"argv": [str(DEMANGLE), "--expand"], "cwd": str(ROOT), "exitCode": result.returncode,
                        "tool": tool(DEMANGLE), "stdin": {"path": rel(demangle_input), "sha256": digest(demangle_input), "bytes": demangle_input.stat().st_size},
                        "stdout": {"path": rel(demangle_output), "sha256": digest(demangle_output), "bytes": demangle_output.stat().st_size},
                        "stderr": {"path": rel(demangle_stderr), "sha256": digest(demangle_stderr), "bytes": demangle_stderr.stat().st_size}}

    branch_compile = run_capture([str(SWIFTC), "-sdk", SDK, "-target", TARGET, str(HERE / "tilde-sendable-probe.swift"), "-o", "/tmp/duplicate-identity-tilde-probe"], HERE / "branch-compile.stdout", HERE / "branch-compile.stderr")
    branch_run = run_capture(["/tmp/duplicate-identity-tilde-probe"], HERE / "branch-output.txt", HERE / "branch-run.stderr")

    toolchain = link.get("toolchainEvidence", {})
    payload = {"kind": "f1-duplicate-identity-spike", "version": 1,
               "status": "review-only-five-duplicate-rows", "linkEvidenceSha256": digest(LINK),
               "toolchain": toolchain,
               "inputs": {"linkEvidence": {"path": rel(LINK), "sha256": digest(LINK), "expectedSha256": EXPECTED_LINK},
                          "interface": {"path": rel(INTERFACE), "sha256": digest(INTERFACE)},
                          "request": {"path": rel(REQUEST), "sha256": digest(REQUEST)},
                          "frozenResponse": {"path": rel(ORIGINAL_RESPONSE), "sha256": digest(ORIGINAL_RESPONSE)},
                          "validatorSource": {"path": rel(HERE / "duplicate_identity_validator.py"), "sha256": digest(HERE / "duplicate_identity_validator.py")},
                          "investigatorSource": {"path": rel(HERE / "investigate_duplicates.py"), "sha256": digest(HERE / "investigate_duplicates.py")}},
               "receipts": {"sourcekit": sourcekit, "demangle": demangle_receipt,
                            "tildeSendableBranch": {"compile": {**branch_compile, "tool": tool(SWIFTC), "sdk": SDK, "target": TARGET}, "run": branch_run}},
               "summary": {"heldCaseCount": 5, "rawDuplicateRows": 5, "promotionsMade": 0}, "rows": rows}
    (HERE / "raw-record-evidence.json").write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {HERE / 'raw-record-evidence.json'}")


if __name__ == "__main__":
    main()
