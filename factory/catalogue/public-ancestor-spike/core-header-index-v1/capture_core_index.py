#!/usr/bin/env python3
"""Capture header-derived SourceKit index facts for the pinned SwiftUICore interface."""
from __future__ import annotations

import hashlib
import json
import re
import shlex
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
TOOLCHAIN = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain")
SOURCE = SDK / "System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
REQUEST = HERE / "request-index-core-header.yaml"
RAW = HERE / "sourcekit-index-core-header.stdout"
STDERR = HERE / "sourcekit-index-core-header.stderr"
RUN = HERE / "run-receipt.json"
FLAGS = HERE / "header-flags.json"
TARGET = "arm64-apple-macosx27.0"
EXPECTED_SOURCE = "sha256:4fb89ff3d972d507faee2bde0a7e81761a2cb9c744eaf94df810235918c7ac13"
EXPECTED_LINK = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"

def sha(value: bytes | str) -> str:
    if isinstance(value, str): value = value.encode()
    return "sha256:" + hashlib.sha256(value).hexdigest()

def fsha(path: Path) -> str: return sha(path.read_bytes())
def rel(path: Path) -> str: return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)

def tool(path: Path) -> dict: return {"path": str(path), "sha256": fsha(path)}

def header_tokens(prefix: str, lines: list[str]) -> tuple[str, list[str]]:
    rows = [line for line in lines if line.startswith(prefix)]
    if len(rows) != 1: raise RuntimeError(f"expected one {prefix!r} row, found {len(rows)}")
    raw = rows[0][len(prefix):].strip()
    return rows[0], shlex.split(raw)

def remove_target_flags(tokens: list[str]) -> tuple[list[str], list[dict]]:
    removed: list[dict] = []
    kept: list[str] = []
    i = 0
    while i < len(tokens):
        if tokens[i] in {"-target", "-target-variant", "-target-arch-variant"}:
            flag = tokens[i]
            value = tokens[i + 1] if i + 1 < len(tokens) else None
            removed.append({"flag": flag, "value": value})
            i += 2
        else:
            kept.append(tokens[i]); i += 1
    return kept, removed

def forward_frontend_flags(tokens: list[str]) -> tuple[list[str], list[dict]]:
    """Forward frontend-only header options through SourceKit's driver parser."""
    forwarded: list[dict] = []
    kept: list[str] = []
    rejected = {"-enable-objc-interop", "-formal-cxx-interoperability-mode=off"}
    for token in tokens:
        if token in rejected:
            kept.extend(["-Xfrontend", token])
            forwarded.append({"flag": token, "forwardedAs": ["-Xfrontend", token], "reason": "frontend-only-header-option"})
        else:
            kept.append(token)
    return kept, forwarded

def make_compiler_args() -> dict:
    src_lines = SOURCE.read_text(encoding="utf-8", errors="replace").splitlines()
    flag_row, source_flags = header_tokens("// swift-module-flags:", src_lines)
    ignorable_row, ignorable_flags = header_tokens("// swift-module-flags-ignorable:", src_lines)
    kept, removed = remove_target_flags(source_flags)
    kept, forwarded = forward_frontend_flags(kept)
    ignorable_kept, ignorable_forwarded = forward_frontend_flags(ignorable_flags)
    args = [str(SOURCE), *kept, *ignorable_kept, "-sdk", str(SDK), "-target", TARGET]
    return {"source": rel(SOURCE), "sourceSha256": fsha(SOURCE), "rawRows": {"swiftModuleFlags": flag_row, "swiftModuleFlagsIgnorable": ignorable_row}, "parsed": {"swiftModuleFlags": source_flags, "swiftModuleFlagsIgnorable": ignorable_flags}, "removedTargetFlags": removed, "forwardedFrontendFlags": forwarded + ignorable_forwarded, "productionTarget": TARGET, "sdkAppended": str(SDK), "compilerArgs": args, "moduleNameFromHeader": source_flags[source_flags.index("-module-name") + 1], "moduleABIName": source_flags[source_flags.index("-module-abi-name") + 1], "publicModuleName": ignorable_flags[ignorable_flags.index("-public-module-name") + 1]}

def request_bytes(args: list[str]) -> str:
    def quote(v: str) -> str: return json.dumps(v)
    values = ", ".join(quote(v) for v in args)
    return "{\n key.request: source.request.indexsource,\n key.sourcefile: " + quote(str(SOURCE)) + ",\n key.compilerargs: [ " + values + " ]\n}\n"

def run_index() -> dict:
    argv = ["xcrun", "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", str(REQUEST)]
    result = subprocess.run(argv, cwd=ROOT, capture_output=True, check=False)
    RAW.write_bytes(result.stdout); STDERR.write_bytes(result.stderr)
    return {"argv": argv, "cwd": str(ROOT), "exit": result.returncode, "stdout": {"path": rel(RAW), "sha256": fsha(RAW), "bytes": RAW.stat().st_size}, "stderr": {"path": rel(STDERR), "sha256": fsha(STDERR), "bytes": STDERR.stat().st_size}}

def parse_records(raw: str) -> list[dict]:
    pat = re.compile(r"key\.kind: (source\.lang\.swift\.decl\.[^,\n]+),\n\s+key\.name: \"([^\"]*)\",\n\s+key\.usr: \"([^\"]+)\",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)")
    return [{"kind": k, "name": n, "usr": u, "line": int(line), "column": int(col)} for k, n, u, line, col in pat.findall(raw)]

def summarize(raw: str) -> dict:
    records = parse_records(raw)
    physical_pairs = [(r["line"], r["column"], r["name"], r["kind"], r["usr"]) for r in records]
    public_effective = len(re.findall(r"key\.effective_access: source\.decl\.effective_access\.public", raw))
    public_attributes = len(re.findall(r"key\.attribute: source\.decl\.attribute\.public", raw))
    by_line: dict[str, dict] = {}
    for record in records:
        row = by_line.setdefault(str(record["line"]), {"recordCount": 0, "publicEffectiveAccessFieldCount": 0})
        row["recordCount"] += 1
    # Attribute fields are nested; close each raw declaration at its physical enclosing brace.
    raw_lines = raw.splitlines()
    for i, line in enumerate(raw_lines):
        if not re.match(r"^\s+key\.kind: source\.lang\.swift\.decl\.", line): continue
        indent = len(line) - len(line.lstrip())
        end = next(j for j in range(i + 1, len(raw_lines)) if len(raw_lines[j]) - len(raw_lines[j].lstrip()) == indent - 2 and raw_lines[j].strip() in {"},", "}"})
        block = "\n".join(raw_lines[i:end + 1])
        line_match = re.search(r"key\.line: (\d+)", block)
        if line_match and "key.effective_access: source.decl.effective_access.public" in block:
            by_line.setdefault(line_match.group(1), {"recordCount": 0, "publicEffectiveAccessFieldCount": 0})["publicEffectiveAccessFieldCount"] += 1
    return {"recordDenominator": len(records), "publicEffectiveAccessFieldCount": public_effective, "publicAttributeFieldCount": public_attributes, "physicalPositionNameKindUsrPairs": {"denominator": len(physical_pairs), "unique": len(set(physical_pairs)), "duplicatePairCount": len(physical_pairs) - len(set(physical_pairs))}, "recordsBySourceLine": by_line, "declarationKinds": sorted({r["kind"] for r in records}), "nominalUsrPrefixCounts": {"SwiftUI": sum(r["usr"].startswith("s:7SwiftUI") for r in records if r["kind"].split(".")[-1] in {"struct", "class", "enum", "protocol", "extension"}), "SwiftUICore": sum(r["usr"].startswith("s:11SwiftUICore") for r in records if r["kind"].split(".")[-1] in {"struct", "class", "enum", "protocol", "extension"}), "other": sum(not (r["usr"].startswith("s:7SwiftUI") or r["usr"].startswith("s:11SwiftUICore")) for r in records if r["kind"].split(".")[-1] in {"struct", "class", "enum", "protocol", "extension"})}, "varUsrPrefixCounts": {"SwiftUI": sum(r["usr"].startswith("s:7SwiftUI") for r in records if ".var." in r["kind"]), "SwiftUICore": sum(r["usr"].startswith("s:11SwiftUICore") for r in records if ".var." in r["kind"]), "other": sum(not (r["usr"].startswith("s:7SwiftUI") or r["usr"].startswith("s:11SwiftUICore")) for r in records if ".var." in r["kind"])}}

def main() -> None:
    if fsha(LINK) != EXPECTED_LINK: raise RuntimeError("immutable836 link changed")
    if fsha(SOURCE) != EXPECTED_SOURCE: raise RuntimeError("Core source hash changed")
    parsed = make_compiler_args()
    REQUEST.write_text(request_bytes(parsed["compilerArgs"]), encoding="utf-8")
    FLAGS.write_text(json.dumps(parsed, indent=2) + "\n", encoding="utf-8")
    run = run_index()
    RUN.write_text(json.dumps({"source": rel(SOURCE), "sourceSha256": fsha(SOURCE), "immutableLink": {"path": rel(LINK), "sha256": fsha(LINK)}, "toolchain": {"swiftc": tool(TOOLCHAIN / "usr/bin/swiftc"), "sourcekitLsp": tool(TOOLCHAIN / "usr/bin/sourcekit-lsp"), "sourcekitd": tool(TOOLCHAIN / "usr/lib/sourcekitd.framework/Versions/A/sourcekitd")}, "sourcekit": run, "request": {"path": rel(REQUEST), "sha256": fsha(REQUEST), "bytes": REQUEST.stat().st_size}, "headerFlags": {"path": rel(FLAGS), "sha256": fsha(FLAGS)}}, indent=2) + "\n", encoding="utf-8")
    records = summarize(RAW.read_text(encoding="utf-8", errors="replace"))
    out = {"kind": "f1-core-header-index-raw-capture", "version": 1, "status": "raw-facts-only-no-eligibility-conclusion", "source": {"path": str(SOURCE), "sha256": fsha(SOURCE), "module": "SwiftUICore", "immutableLink": {"path": rel(LINK), "sha256": fsha(LINK)}}, "headerFlags": parsed, "request": {"path": rel(REQUEST), "sha256": fsha(REQUEST), "bytes": REQUEST.stat().st_size}, "response": {"stdout": {"path": rel(RAW), "sha256": fsha(RAW), "bytes": RAW.stat().st_size}, "stderr": {"path": rel(STDERR), "sha256": fsha(STDERR), "bytes": STDERR.stat().st_size}, "exit": run["exit"]}, "runReceipt": {"path": rel(RUN), "sha256": fsha(RUN)}, "summary": records, "interpretation": {"nominalAndVarUsrAbi": "raw prefix counts only; no eligibility inference", "moduleName": parsed["moduleNameFromHeader"], "moduleABIName": parsed["moduleABIName"], "publicModuleName": parsed["publicModuleName"]}}
    (HERE / "core-header-index-evidence.json").write_text(json.dumps(out, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"output": rel(HERE / "core-header-index-evidence.json"), "exit": run["exit"], **records}, indent=2))

if __name__ == "__main__": main()
