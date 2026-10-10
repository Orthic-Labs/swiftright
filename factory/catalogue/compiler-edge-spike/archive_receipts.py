#!/usr/bin/env python3
"""Run edge probes headlessly and archive command/tool/output receipts."""
from __future__ import annotations

import hashlib
import json
import os
import subprocess
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SDK = "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"
TARGET = "arm64-apple-macosx27.0"
TOOLCHAIN = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain")
SWIFTC = TOOLCHAIN / "usr/bin/swiftc"
SOURCEKIT_LSP = TOOLCHAIN / "usr/bin/sourcekit-lsp"
DEMANGLE = TOOLCHAIN / "usr/bin/swift-demangle"
XCRUN = Path("/usr/bin/xcrun")


def digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def run_capture(argv: list[str], stdout_path: Path, stderr_path: Path) -> dict:
    result = subprocess.run(argv, cwd=ROOT, capture_output=True)
    stdout_path.write_bytes(result.stdout)
    stderr_path.write_bytes(result.stderr)
    return {
        "argv": argv,
        "cwd": str(ROOT),
        "exitCode": result.returncode,
        "stdout": {"path": str(stdout_path.relative_to(ROOT)), "sha256": digest(stdout_path), "bytes": stdout_path.stat().st_size},
        "stderr": {"path": str(stderr_path.relative_to(ROOT)), "sha256": digest(stderr_path), "bytes": stderr_path.stat().st_size},
    }


def tool(path: Path) -> dict:
    return {"path": str(path), "sha256": digest(path)}


def main() -> None:
    sourcekit_request = HERE / "request-actor-kind.yaml"
    sourcekit = run_capture(
        ["xcrun", "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", str(sourcekit_request)],
        HERE / "actor-kind-output.txt", HERE / "actor-kind-sourcekit.stderr",
    )
    sourcekit.update({"dispatcher": tool(XCRUN), "tool": tool(SOURCEKIT_LSP), "request": {"path": str(sourcekit_request.relative_to(ROOT)), "sha256": digest(sourcekit_request)}})

    typecheck_request = [str(SWIFTC), "-typecheck", "-sdk", SDK, "-target", TARGET, str(HERE / "actor-kind-probe.swift")]
    typecheck = run_capture(typecheck_request, HERE / "actor-kind-typecheck.stdout", HERE / "actor-kind-typecheck.stderr")
    typecheck.update({"tool": tool(SWIFTC), "sdk": SDK, "target": TARGET})

    demangle_input = "$s11SwiftUICore16_ImpossibleActorC\n$s14ActorKindProbe0cA0C\n$s14ActorKindProbe0C5ClassC\n"
    demangle_input_path = HERE / "actor-kind-demangle-input.txt"
    demangle_input_path.write_text(demangle_input, encoding="utf-8")
    demangle = subprocess.run([str(DEMANGLE), "--expand"], input=demangle_input.encode(), cwd=ROOT, capture_output=True)
    (HERE / "actor-kind-demangle.txt").write_bytes(demangle.stdout)
    (HERE / "actor-kind-demangle.stderr").write_bytes(demangle.stderr)
    demangle_receipt = {
        "argv": [str(DEMANGLE), "--expand"], "cwd": str(ROOT), "exitCode": demangle.returncode,
        "tool": tool(DEMANGLE),
        "stdin": {"path": str(demangle_input_path.relative_to(ROOT)), "sha256": digest(demangle_input_path), "bytes": demangle_input_path.stat().st_size},
        "stdout": {"path": "factory/catalogue/compiler-edge-spike/actor-kind-demangle.txt", "sha256": digest(HERE / "actor-kind-demangle.txt"), "bytes": (HERE / "actor-kind-demangle.txt").stat().st_size},
        "stderr": {"path": "factory/catalogue/compiler-edge-spike/actor-kind-demangle.stderr", "sha256": digest(HERE / "actor-kind-demangle.stderr"), "bytes": (HERE / "actor-kind-demangle.stderr").stat().st_size},
    }

    branch_request = [str(SWIFTC), "-sdk", SDK, "-target", TARGET, str(HERE / "tilde-sendable-branch-probe.swift"), "-o", "/tmp/compiler-edge-tilde-probe"]
    branch_compile = run_capture(branch_request, HERE / "tilde-sendable-branch-compile.stdout", HERE / "tilde-sendable-branch-compile.stderr")
    branch_run = run_capture(["/tmp/compiler-edge-tilde-probe"], HERE / "tilde-sendable-branch-output.txt", HERE / "tilde-sendable-branch-run.stderr")
    branch = {"compile": {**branch_compile, "tool": tool(SWIFTC), "sdk": SDK, "target": TARGET}, "run": branch_run}

    receipt = {
        "kind": "compiler-edge-probe-receipts", "version": 1,
        "sourcekitActor": sourcekit, "actorTypecheck": typecheck,
        "actorDemangle": demangle_receipt, "tildeSendableBranch": branch,
    }
    out = HERE / "probe-receipts.json"
    out.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
