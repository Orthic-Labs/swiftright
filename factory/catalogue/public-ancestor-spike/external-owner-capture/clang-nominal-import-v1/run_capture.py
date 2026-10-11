#!/usr/bin/env python3
"""Capture inferred imported nominal variables through real Swift processes."""
from __future__ import annotations

import datetime as dt
import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
TOOLCHAIN = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin")
SWIFTC = TOOLCHAIN / "swiftc"
SOURCEKIT = TOOLCHAIN / "sourcekit-lsp"
DEMANGLE = TOOLCHAIN / "swift-demangle"
TARGET = "arm64-apple-macosx27.0"


def digest(data: bytes) -> str:
    return "sha256:" + hashlib.sha256(data).hexdigest()


def file_digest(path: Path) -> str:
    return digest(path.read_bytes())


def stamp() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def tool_for(name: str) -> Path:
    if name.startswith("swift-"):
        return SWIFTC
    if name == "sourcekit-index":
        return SOURCEKIT
    return DEMANGLE


def process(cmd: list[str], name: str, stdout_path: Path, stderr_path: Path, *, stdin_path: Path | None = None, stdin_bytes: bytes | None = None) -> dict:
    started = stamp()
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    stdin_handle = stdin_path.open("rb") if stdin_path else None
    try:
        with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
            proc = subprocess.Popen(cmd, cwd=str(ROOT), stdin=stdin_handle or (subprocess.PIPE if stdin_bytes is not None else None), stdout=stdout, stderr=stderr)
            if stdin_bytes is not None:
                proc.communicate(stdin_bytes)
            else:
                proc.wait()
    finally:
        if stdin_handle:
            stdin_handle.close()
    ended = stamp()
    tool = tool_for(name)
    record = {
        "name": name,
        "argv": cmd,
        "cwd": str(ROOT),
        "startedAt": started,
        "endedAt": ended,
        "returncode": proc.returncode,
        "tool": str(cmd[0]),
        "toolIdentityPath": str(tool),
        "toolIdentitySha256": file_digest(tool),
        "stdout": str(stdout_path.relative_to(ROOT)),
        "stdoutSha256": file_digest(stdout_path),
        "stdoutBytes": stdout_path.stat().st_size,
        "stderr": str(stderr_path.relative_to(ROOT)),
        "stderrSha256": file_digest(stderr_path),
        "stderrBytes": stderr_path.stat().st_size,
    }
    if stdin_path:
        record["stdin"] = str(stdin_path.relative_to(ROOT))
        record["stdinSha256"] = file_digest(stdin_path)
        record["stdinBytes"] = stdin_path.stat().st_size
    elif stdin_bytes is not None:
        record["stdinSha256"] = digest(stdin_bytes)
        record["stdinBytes"] = len(stdin_bytes)
    return record


EXPECTED = {
    "nsWindow": ("AppKit.NSWindow", 7, "NSWindow", "c:objc(cs)NSWindow", "source.lang.swift.ref.class"),
    "nsApplication": ("AppKit.NSApplication", 8, "NSApplication", "c:objc(cs)NSApplication", "source.lang.swift.ref.class"),
    "nsColor": ("AppKit.NSColor", 9, "NSColor", "c:objc(cs)NSColor", "source.lang.swift.ref.class"),
    "nsControl": ("AppKit.NSControl", 10, "NSControl", "c:objc(cs)NSControl", "source.lang.swift.ref.class"),
    "controlSize": ("AppKit.NSControl.ControlSize", 11, "ControlSize", "c:@E@NSControlSize", "source.lang.swift.ref.enum"),
    "directionalInsets": ("AppKit.NSDirectionalEdgeInsets", 12, "NSDirectionalEdgeInsets", "c:@S@NSDirectionalEdgeInsets", "source.lang.swift.ref.struct"),
    "underlineStyle": ("AppKit.NSUnderlineStyle", 13, "NSUnderlineStyle", "c:@E@NSUnderlineStyle", "source.lang.swift.ref.struct"),
    "animationContext": ("AppKit.NSAnimationContext", 14, "NSAnimationContext", "c:objc(cs)NSAnimationContext", "source.lang.swift.ref.class"),
    "activity": ("Foundation.NSUserActivity", 15, "NSUserActivity", "c:objc(cs)NSUserActivity", "source.lang.swift.ref.class"),
    "point": ("CoreFoundation.CGPoint", 16, "CGPoint", "c:@S@CGPoint", "source.lang.swift.ref.struct"),
    "size": ("CoreFoundation.CGSize", 17, "CGSize", "c:@S@CGSize", "source.lang.swift.ref.struct"),
    "rect": ("CoreFoundation.CGRect", 18, "CGRect", "c:@S@CGRect", "source.lang.swift.ref.struct"),
    "size3D": ("Spatial.Size3D", 19, "Size3D", "c:@UA@SPSize3D", "source.lang.swift.ref.struct"),
}


def variable_rows(text: str) -> list[dict]:
    pattern = re.compile(r'key\.kind: source\.lang\.swift\.decl\.var\.global,\n\s+key\.name: "([^\"]+)",\n\s+key\.usr: "([^\"]+)",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)')
    return [{"name": n, "usr": u, "line": int(line), "column": int(column), "kind": "source.lang.swift.decl.var.global"} for n, u, line, column in pattern.findall(text)]


def nominal_rows(text: str) -> list[dict]:
    pattern = re.compile(r'key\.kind: (source\.lang\.swift\.ref\.(?:class|struct|enum)),\n\s+key\.name: "([^\"]+)",\n\s+key\.usr: "([^\"]+)",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)')
    return [{"kind": k, "name": n, "usr": u, "line": int(line), "column": int(column)} for k, n, u, line, column in pattern.findall(text)]


def main() -> None:
    probes = HERE / "probes"
    requests = HERE / "requests"
    raw = HERE / "raw"
    receipts = HERE / "receipts"
    probe = probes / "owners.swift"
    request = requests / "owners.yaml"
    runs = []
    runs.append(process(["xcrun", "--sdk", "macosx", "swiftc", "-typecheck", "-sdk", str(SDK), "-target", TARGET, str(probe)], "swift-typecheck", receipts / "typecheck.stdout", receipts / "typecheck.stderr"))
    runs.append(process(["xcrun", "--sdk", "macosx", "swiftc", "-typecheck", "-dump-ast", "-sdk", str(SDK), "-target", TARGET, str(probe)], "swift-ast-dump", raw / "owners.ast.txt", receipts / "ast.stderr"))
    runs.append(process(["xcrun", "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", str(request)], "sourcekit-index", raw / "owners.index.txt", receipts / "sourcekit.stderr"))
    indexed = variable_rows((raw / "owners.index.txt").read_text())
    if len(indexed) != len(EXPECTED) or {row["name"] for row in indexed} != set(EXPECTED):
        raise RuntimeError(f"variable row set: {indexed}")
    (raw / "variable-usrs.json").write_text(json.dumps(indexed, indent=2) + "\n")
    raw_usrs = "\n".join(row["usr"] for row in indexed) + "\n"
    (raw / "variable-usrs.txt").write_text(raw_usrs)
    demangle_input = "\n".join("$" + row["usr"][0] + row["usr"][2:] for row in indexed) + "\n"
    (raw / "demangle-input.txt").write_text(demangle_input)
    runs.append(process([str(DEMANGLE), "--expand"], "swift-demangle-expand", raw / "demangle-expand.txt", receipts / "demangle.stderr", stdin_path=raw / "demangle-input.txt"))
    for run in runs:
        run["inputBindings"] = []
        if run["name"] == "sourcekit-index":
            run["inputBindings"].append({"path": str(request.relative_to(ROOT)), "sha256": file_digest(request), "bytes": request.stat().st_size})
        elif run["name"].startswith("swift-"):
            run["inputBindings"].append({"path": str(probe.relative_to(ROOT)), "sha256": file_digest(probe), "bytes": probe.stat().st_size})
        elif run["name"] == "swift-demangle-expand":
            run["inputBindings"].append({"path": str((raw / "demangle-input.txt").relative_to(ROOT)), "sha256": file_digest(raw / "demangle-input.txt"), "bytes": (raw / "demangle-input.txt").stat().st_size})
    (raw / "process-runs.json").write_text(json.dumps({"schema": "clang-nominal-import-v1-runs", "runs": runs}, indent=2) + "\n")
    print(json.dumps({"runs": len(runs), "returncodes": [run["returncode"] for run in runs], "variables": len(indexed), "receipt": str((raw / "process-runs.json").relative_to(ROOT))}, indent=2))


if __name__ == "__main__":
    main()
