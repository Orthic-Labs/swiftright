#!/usr/bin/env python3
"""Capture exact SourceKit cursor evidence for held SwiftUI destructors."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
FRAMEWORKS = SDK / "System/Library/Frameworks"
RECON = Path("/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/f1-residuals/public-ancestor-v1/preliminary-reconstruction.json")
FROZEN = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
FROZEN_SHA = "836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
RECON_SHA = "58cfe1155ea19358637ca43c9ab90dfc183e78ea07f48248111ca22f72a9e65d"
SOURCEKIT = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp")
DEMANGLE = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-demangle")
XCRUN = Path("/usr/bin/xcrun")
TARGET = "arm64-apple-macosx27.0"
HELD_REASON = "destructor source access semantics require explicit eligibility definition"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_value(value: str):
    value = value.strip().rstrip(",")
    if value.startswith('"') and value.endswith('"'):
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return value
    try:
        return int(value)
    except ValueError:
        return value


def parse_cursor(data: bytes) -> dict:
    text = data.decode("utf-8", errors="strict")
    fields = {}
    for match in re.finditer(r"^  key\.([A-Za-z0-9_]+): (.*)$", text, re.MULTILINE):
        fields[match.group(1)] = parse_value(match.group(2))
    visibility_keys = [k for k in ("effective_access", "accessibility", "access") if k in fields]
    return {
        "raw": text,
        "fields": fields,
        "accessibility": {"status": "observed", "keys": visibility_keys, "values": {k: fields[k] for k in visibility_keys}} if visibility_keys else {"status": "unknown", "keys": [], "values": {}},
    }


def source_path(module: str) -> Path:
    return FRAMEWORKS / f"{module}.framework/Versions/A/Modules/{module}.swiftmodule/arm64e-apple-macos.swiftinterface"


def main() -> int:
    if sha(FROZEN) != FROZEN_SHA or sha(RECON) != RECON_SHA:
        raise SystemExit("frozen input changed")
    reconstruction = json.loads(RECON.read_text(encoding="utf-8"))
    held = [r for r in reconstruction["rows"] if r.get("reason") == HELD_REASON]
    if len(held) != 42:
        raise SystemExit(f"expected 42 held destructors, got {len(held)}")
    (HERE / "requests").mkdir(exist_ok=True)
    (HERE / "outputs").mkdir(exist_ok=True)
    (HERE / "receipts").mkdir(exist_ok=True)
    rows = []
    all_usrs = []
    for source_row in held:
        module = source_row["key"][0]
        line_no = source_row["key"][2]
        source = source_path(module)
        source_bytes = source.read_bytes()
        source_lines = source_bytes.decode("utf-8").splitlines(keepends=True)
        line = source_lines[line_no - 1].rstrip("\r\n")
        if "deinit" not in line:
            raise SystemExit(f"source line lacks deinit: {module}:{line_no}")
        line_start = sum(len(s.encode("utf-8")) for s in source_lines[: line_no - 1])
        offset = line_start + len(line[: line.index("deinit")].encode("utf-8"))
        stem = f"{module}-{line_no}"
        request = HERE / "requests" / f"{stem}.yaml"
        request.write_text("{\n key.request: source.request.cursorinfo,\n key.sourcefile: " + json.dumps(str(source)) + ",\n key.offset: " + str(offset) + ",\n key.compilerargs: [ " + ", ".join(json.dumps(x) for x in (str(source), "-sdk", str(SDK), "-target", TARGET, "-module-name", module)) + " ]\n}\n", encoding="utf-8")
        output = HERE / "outputs" / f"{stem}.txt"
        stderr = HERE / "receipts" / f"{stem}.stderr"
        argv = ["xcrun", "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", str(request)]
        proc = subprocess.run(argv, cwd=ROOT, capture_output=True, check=False)
        output.write_bytes(proc.stdout)
        stderr.write_bytes(proc.stderr)
        parsed = parse_cursor(proc.stdout)
        if parsed["fields"].get("usr"):
            all_usrs.append(parsed["fields"]["usr"])
        rows.append({
            "module": module, "interface": source.name, "line": line_no, "name": "deinit", "signature": source_row["signature"], "sourceLine": line,
            "lineStartByteOffset": line_start, "deinitByteOffset": offset, "conditions": source_row.get("conditions", []), "scopeLines": source_row.get("scopeLines", []),
            "sourceStatus": source_row.get("status"), "sourceReason": source_row.get("reason"), "sourceOwner": source_row.get("owner"), "sourceUsr": source_row.get("usr"),
            "source": {"path": str(source), "sha256": "sha256:" + sha(source), "bytes": len(source_bytes)},
            "request": {"path": str(request.relative_to(ROOT)), "sha256": "sha256:" + sha(request), "bytes": request.stat().st_size},
            "response": {"path": str(output.relative_to(ROOT)), "sha256": "sha256:" + sha(output), "bytes": output.stat().st_size},
            "cursor": parsed,
            "receipt": {"argv": argv, "cwd": str(ROOT), "exitCode": proc.returncode, "dispatcher": {"path": str(XCRUN), "sha256": "sha256:" + sha(XCRUN)}, "tool": {"path": str(SOURCEKIT), "sha256": "sha256:" + sha(SOURCEKIT)}, "stderr": {"path": str(stderr.relative_to(ROOT)), "sha256": "sha256:" + sha(stderr), "bytes": stderr.stat().st_size}},
        })
    unique_usrs = sorted(set(all_usrs))
    usr_input = HERE / "receipts/raw-symbol-input.txt"
    usr_output = HERE / "outputs/raw-symbol-tree.txt"
    usr_stderr = HERE / "receipts/raw-symbol-tree.stderr"
    usr_input.write_text("\n".join(unique_usrs) + "\n", encoding="utf-8")
    demangle = subprocess.run([str(DEMANGLE, ), "--expand"], input=usr_input.read_bytes(), capture_output=True, check=False, cwd=ROOT)
    usr_output.write_bytes(demangle.stdout)
    usr_stderr.write_bytes(demangle.stderr)
    evidence = {
        "kind": "swiftui-destructor-access-cursor-capture", "version": 1, "status": "review-only", "promotionsMade": 0,
        "heldReason": HELD_REASON, "summary": {"heldRows": len(rows), "cursorRequests": len(rows), "cursorExit0": sum(r["receipt"]["exitCode"] == 0 for r in rows), "usrCount": len(unique_usrs)},
        "inputs": {"frozenLinkEvidence": {"path": str(FROZEN.relative_to(ROOT)), "sha256": "sha256:" + sha(FROZEN), "expectedSha256": "sha256:" + FROZEN_SHA}, "reconstruction": {"path": str(RECON), "sha256": "sha256:" + sha(RECON), "expectedSha256": "sha256:" + RECON_SHA}},
        "toolchain": {"target": TARGET, "sourcekitLsp": {"path": str(SOURCEKIT), "sha256": "sha256:" + sha(SOURCEKIT)}, "swiftDemangle": {"path": str(DEMANGLE), "sha256": "sha256:" + sha(DEMANGLE)}, "xcrun": {"path": str(XCRUN), "sha256": "sha256:" + sha(XCRUN)}},
        "rawSymbolTree": {"usrs": unique_usrs, "receipt": {"argv": [str(DEMANGLE), "--expand"], "cwd": str(ROOT), "exitCode": demangle.returncode, "tool": {"path": str(DEMANGLE), "sha256": "sha256:" + sha(DEMANGLE)}, "stdin": {"path": str(usr_input.relative_to(ROOT)), "sha256": "sha256:" + sha(usr_input), "bytes": usr_input.stat().st_size}, "stdout": {"path": str(usr_output.relative_to(ROOT)), "sha256": "sha256:" + sha(usr_output), "bytes": usr_output.stat().st_size}, "stderr": {"path": str(usr_stderr.relative_to(ROOT)), "sha256": "sha256:" + sha(usr_stderr), "bytes": usr_stderr.stat().st_size}}},
        "rows": rows,
    }
    (HERE / "destructor-access-evidence.json").write_text(json.dumps(evidence, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
