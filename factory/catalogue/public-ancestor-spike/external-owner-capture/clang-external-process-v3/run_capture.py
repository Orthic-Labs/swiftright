#!/usr/bin/env python3
"""Execute bounded compiler/index/AST processes & record their actual receipts."""
from __future__ import annotations
import datetime as dt
import gzip
import hashlib
import json
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
TOOLCHAIN = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin")
SWIFTC = TOOLCHAIN / "swiftc"
CLANG = TOOLCHAIN / "clang"
SOURCEKIT = TOOLCHAIN / "sourcekit-lsp"
TARGET = "arm64-apple-macosx27.0"

def digest(b: bytes) -> str:
    return "sha256:" + hashlib.sha256(b).hexdigest()

def file_digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return "sha256:" + h.hexdigest()

def stamp() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()

def tool_path(name: str) -> Path:
    return SWIFTC if name == "swift-typecheck" else SOURCEKIT if name == "sourcekit-index" else CLANG

def process(cmd: list[str], name: str, stdout_path: Path, stderr_path: Path, gzip_stdout: bool) -> dict:
    started = stamp()
    stdout_path.parent.mkdir(parents=True, exist_ok=True)
    raw_hash = hashlib.sha256(); raw_size = 0
    with stdout_path.open("wb") as output, stderr_path.open("wb") as error:
        proc = subprocess.Popen(cmd, cwd=str(ROOT), stdout=subprocess.PIPE, stderr=error)
        if gzip_stdout:
            with gzip.GzipFile(fileobj=output, mode="wb", compresslevel=9, mtime=0) as compressed:
                while True:
                    chunk = proc.stdout.read(1024 * 1024)
                    if not chunk:
                        break
                    raw_hash.update(chunk); raw_size += len(chunk); compressed.write(chunk)
        else:
            while True:
                chunk = proc.stdout.read(1024 * 1024)
                if not chunk:
                    break
                raw_hash.update(chunk); raw_size += len(chunk); output.write(chunk)
        proc.wait()
    ended = stamp()
    tool = tool_path(name)
    return {"name": name, "argv": cmd, "cwd": str(ROOT), "startedAt": started, "endedAt": ended, "returncode": proc.returncode, "stdout": str(stdout_path.relative_to(ROOT)), "stdoutSha256": file_digest(stdout_path), "stdoutBytes": stdout_path.stat().st_size, "rawStdoutSha256": "sha256:" + raw_hash.hexdigest(), "rawStdoutBytes": raw_size, "stderr": str(stderr_path.relative_to(ROOT)), "stderrSha256": file_digest(stderr_path), "stderrBytes": stderr_path.stat().st_size, "tool": str(cmd[0]), "toolIdentityPath": str(tool), "toolIdentitySha256": file_digest(tool)}

def trim(node: dict) -> dict:
    keep = {"kind", "name", "mangledName", "completeDefinition", "isReferenced", "loc", "range", "super", "protocols", "type"}
    return {k: node[k] for k in keep if k in node}

def walk(node):
    if isinstance(node, dict):
        yield node
        for value in node.values():
            yield from walk(value)
    elif isinstance(node, list):
        for value in node:
            yield from walk(value)

def ast_records(path: Path, predicate) -> list[dict]:
    with gzip.open(path, "rb") as stream:
        root = json.load(stream)
    return [trim(x) for x in walk(root) if predicate(x)]

def extract_ast(raw: Path) -> None:
    appkit_targets = {"NSWindow": 283, "NSApplication": 194, "NSColor": 77, "NSControl": 19, "NSAnimationContext": 19}
    appkit = ast_records(raw / "appkit.ast.json.gz", lambda x: (
        x.get("kind") == "ObjCInterfaceDecl" and x.get("name") in appkit_targets and x.get("loc", {}).get("line") == appkit_targets[x["name"]]
    ) or (
        x.get("kind") == "RecordDecl" and x.get("name") == "NSDirectionalEdgeInsets" and x.get("completeDefinition") is True
    ) or (
        x.get("kind") == "TypedefDecl" and x.get("name") == "NSUnderlineStyle"
    ) or (
        x.get("kind") == "TypedefDecl" and x.get("name") in {"NSControlSize", "NSDirectionalEdgeInsets"} and ((x.get("loc", {}).get("spellingLoc") or {}).get("line") in {91} or x.get("loc", {}).get("line") == 58)
    ))
    foundation = ast_records(raw / "foundation.ast.json.gz", lambda x: x.get("kind") == "ObjCInterfaceDecl" and x.get("name") == "NSUserActivity" and x.get("loc", {}).get("line") == 56)
    core = ast_records(raw / "corefoundation.ast.json.gz", lambda x: x.get("kind") == "RecordDecl" and x.get("name") in {"CGPoint", "CGSize", "CGRect"} and x.get("completeDefinition") is True)
    core += ast_records(raw / "corefoundation.ast.json.gz", lambda x: x.get("kind") == "TypedefDecl" and x.get("name") in {"CGPoint", "CGSize", "CGRect"})
    spatial = ast_records(raw / "spatial.ast.json.gz", lambda x: x.get("kind") == "TypedefDecl" and x.get("name") == "SPSize3D" and x.get("isReferenced") is True)
    for name, records in (("appkit-targets.ast.json", appkit), ("foundation-targets.ast.json", foundation), ("corefoundation-targets.ast.json", core), ("spatial-targets.ast.json", spatial)):
        (raw / name).write_text(json.dumps(records, indent=2) + "\n")

def main() -> None:
    probes = HERE / "probes"; raw = HERE / "raw"; receipts = HERE / "receipts"; requests = HERE / "requests"
    sdk = str(SDK); target = TARGET
    runs = []
    runs.append(process(["xcrun", "--sdk", "macosx", "swiftc", "-typecheck", "-sdk", sdk, "-target", target, str(probes / "owners.swift")], "swift-typecheck", receipts / "owners.swiftc.stdout", receipts / "owners.swiftc.stderr", False))
    runs.append(process(["xcrun", "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", str(requests / "owners.yaml")], "sourcekit-index", raw / "owners.index.txt", receipts / "owners.sourcekit.stderr", False))
    runs.append(process(["xcrun", "--sdk", "macosx", "clang", "-fsyntax-only", "-x", "objective-c", "-isysroot", sdk, "-target", target, "-include", "AppKit/AppKit.h", "-Xclang", "-ast-dump=json", str(probes / "appkit_ast.m")], "clang-appkit-ast", raw / "appkit.ast.json.gz", receipts / "appkit.clang.stderr", True))
    runs.append(process(["xcrun", "--sdk", "macosx", "clang", "-fsyntax-only", "-x", "objective-c", "-isysroot", sdk, "-target", target, "-include", "Foundation/Foundation.h", "-Xclang", "-ast-dump=json", str(probes / "foundation_ast.m")], "clang-foundation-ast", raw / "foundation.ast.json.gz", receipts / "foundation.clang.stderr", True))
    runs.append(process(["xcrun", "--sdk", "macosx", "clang", "-fsyntax-only", "-x", "c", "-isysroot", sdk, "-target", target, "-include", "CoreFoundation/CoreFoundation.h", "-Xclang", "-ast-dump=json", str(probes / "corefoundation_ast.c")], "clang-corefoundation-ast", raw / "corefoundation.ast.json.gz", receipts / "corefoundation.clang.stderr", True))
    runs.append(process(["xcrun", "--sdk", "macosx", "clang", "-fsyntax-only", "-x", "c", "-isysroot", sdk, "-target", target, "-include", "CoreGraphics/CoreGraphics.h", "-Xclang", "-ast-dump=json", str(probes / "coregraphics_ast.c")], "clang-coregraphics-ast", raw / "coregraphics.ast.json.gz", receipts / "coregraphics.clang.stderr", True))
    runs.append(process(["xcrun", "--sdk", "macosx", "clang", "-fsyntax-only", "-x", "c", "-isysroot", sdk, "-target", target, "-include", "Spatial/Structures.h", "-Xclang", "-ast-dump=json", str(probes / "spatial_ast.c")], "clang-spatial-ast", raw / "spatial.ast.json.gz", receipts / "spatial.clang.stderr", True))
    extract_ast(raw)
    (raw / "process-runs.json").write_text(json.dumps({"schema": "clang-external-process-v3-runs", "runs": runs}, indent=2) + "\n")
    print(json.dumps({"runs": len(runs), "returncodes": [x["returncode"] for x in runs], "receipt": str((raw / "process-runs.json").relative_to(ROOT))}, indent=2))

if __name__ == "__main__":
    main()
