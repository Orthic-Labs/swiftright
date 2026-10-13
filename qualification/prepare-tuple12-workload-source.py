#!/usr/bin/env python3
"""Emit hash-bound SR0 tuple12 WorkloadWin source closure metadata.

This is source preparation only: it never copies, builds, signs, connects remotely,
or mutates Git.  Dell staging must target a fresh ignored directory.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
from pathlib import Path

SOURCE_COMMIT = "0e201571e4320a3b6ccce14313fd2ad67e523904"
RENDERER_SHA256 = "7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2"
ABI_SHA256 = "12764e1f5e24457617a2a46b993ce405bde3f9b25625882425a997e4a8f2689b"

SOURCE_DIRS = (
    "probes/sr0-b/workload/Sources/WorkloadCore",
    "probes/sr0-b/workload/Sources/WorkloadWin",
    "probes/sr0-s/fresh-runtime/Sources/SwiftRightRuntime",
    "packages/SwiftRightBridge/Sources",
)
SOURCE_FILES = (
    "probes/sr0-b/workload/Package.swift",
    "probes/sr0-s/fresh-runtime/Package.swift",
    "packages/SwiftRightBridge/Package.swift",
    "render/swiftright-abi/include/swiftright.h",
)
SCRIPT_FILES = (
    "probes/sr0-b/workload/analysis/analyze_workload.py",
    "probes/sr0-b/workload/scripts/build-workload.ps1",
    "probes/sr0-b/workload/scripts/run-workload.ps1",
    "probes/sr0-b/workload/scripts/task-workload.ps1",
    "probes/sr0-b/workload/scripts/sample-resources.ps1",
    "probes/sr0-b/workload/scripts/verify-artifacts.ps1",
    "probes/sr0-b/workload/scripts/verify-manifest.ps1",
)
OVERLAY_FILES = (
    "qualification/tuple12-workload-background-overlay.patch",
    "qualification/tuple12-workload-run-overlay.patch",
    "qualification/tuple12-workload-startupguard-overlay.json",
    "qualification/tuple12-workload-startupguard/WorkloadStartupGuard.swift",
    "qualification/tuple12-workload-startupguard/main.swift.patch",
)


def sha256(path: Path) -> tuple[int, str]:
    data = path.read_bytes()
    return len(data), hashlib.sha256(data).hexdigest()


def git_bytes(repo: Path, commit: str, rel: str) -> bytes:
    p = subprocess.run(
        ["git", "-C", str(repo), "show", f"{commit}:{rel}"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return p.stdout


def add_entry(repo: Path, entries: list[dict], rel: str, *, commit_bound: bool) -> None:
    path = repo / rel
    if not path.is_file():
        raise SystemExit(f"missing source file: {rel}")
    size, digest = sha256(path)
    expected = None
    if commit_bound:
        expected = hashlib.sha256(git_bytes(repo, SOURCE_COMMIT, rel)).hexdigest()
        if digest != expected:
            raise SystemExit(f"working source differs from pinned {SOURCE_COMMIT}: {rel}")
    entries.append({
        "path": rel,
        "bytes": size,
        "sha256": digest,
        "commit_sha256": expected,
        "kind": "source" if commit_bound else "script-or-overlay",
    })


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--stage-root", default=r"D:\Claude\swiftright\.work\sr0-r12-workload-v1")
    args = ap.parse_args()
    repo = args.repo.resolve()
    out = args.out or repo / "qualification/tuple12-workload-source-manifest.json"
    entries: list[dict] = []
    paths = list(SOURCE_FILES)
    for directory in SOURCE_DIRS:
        paths.extend(
            str(p.relative_to(repo)).replace("\\", "/")
            for p in sorted((repo / directory).rglob("*"))
            if p.is_file() and ".build" not in p.parts
        )
    for rel in sorted(set(paths)):
        add_entry(repo, entries, rel, commit_bound=True)
    for rel in SCRIPT_FILES + OVERLAY_FILES:
        add_entry(repo, entries, rel, commit_bound=False)
    package_sources = [e for e in entries if e["kind"] == "source"]
    if not any(e["path"] == "packages/SwiftRightBridge/Sources/CSwiftRight/swiftright.h" for e in package_sources):
        raise SystemExit("SwiftRightBridge header missing from source closure")
    header = next(e for e in package_sources if e["path"] == "render/swiftright-abi/include/swiftright.h")
    if header["sha256"] != ABI_SHA256:
        raise SystemExit(f"ABI header changed: {header['sha256']}")
    payload = {
        "kind": "sr0-tuple12-workloadwin-source-closure-v1",
        "source_commit": SOURCE_COMMIT,
        "stage_root": args.stage_root,
        "source_root": args.stage_root + r"\src",
        "product": "WorkloadWin",
        "renderer_abi": "0.6",
        "renderer_sha256": RENDERER_SHA256,
        "abi_header_sha256": ABI_SHA256,
        "package_inputs": [
            "probes/sr0-b/workload/Package.swift",
            "probes/sr0-s/fresh-runtime/Package.swift",
            "packages/SwiftRightBridge/Package.swift",
            "probes/sr0-b/workload/Sources/WorkloadCore",
            "probes/sr0-b/workload/Sources/WorkloadWin",
            "probes/sr0-s/fresh-runtime/Sources/SwiftRightRuntime",
            "packages/SwiftRightBridge/Sources",
        ],
        "excluded_from_archive": [
            "**/.build/**", "probes/sr0-b/workload/results/**", "probes/sr0-b/workload/out-mac/**",
            "probes/sr0-s/fresh-runtime/Tests/**", "packages/SwiftRightBridge/Tests/**",
        ],
        "entries": entries,
        "windows_build": {
            "working_directory": args.stage_root + r"\src\probes\sr0-b\workload",
            "swift_path_prefix": r"C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin",
            "scratch_path": args.stage_root + r"\scratch",
            "manifest_dependency": "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'",
            "argv": [
                "swift", "build", "--jobs", "1", "-c", "release", "--product", "WorkloadWin",
                "--scratch-path", "<STAGE>\\scratch", "-Xlinker", "/MANIFEST:EMBED",
                "-Xlinker", "<MANIFEST_DEPENDENCY>",
            ],
            "show_bin_argv": [
                "swift", "build", "--jobs", "1", "-c", "release",
                "--scratch-path", "<STAGE>\\scratch", "--show-bin-path",
            ],
            "dll_source": "<STAGE>\\payload\\bin\\swiftright_render.dll",
            "dll_sha256": RENDERER_SHA256,
        },
        "runtime_policy": {
            "workload_runs_per_configuration": 3,
            "warmup_seconds": 10,
            "measure_seconds": 60,
            "cross_compare_runs_per_side": 20,
            "three_run_exception": False,
            "key_delivery": "WM_CHAR PostMessage to retained workload HWND only",
            "background_candidate": "apply tuple12-workload-run-overlay.patch & tuple12-workload-background-overlay.patch; invoke run-workload.ps1 -NoActivate; require guard marker, background_noactivate=PASS, HWND_BOTTOM, SWP_NOACTIVATE, positive client metrics; default scripts remain unchanged",
            "startup_activation": "WorkloadWin same-thread WH_CBT guard marker before bridge.run; vetoes HCBT_ACTIVATE & HCBT_SETFOCUS through full bridge.run; install failure exits 78; source-bound admission requires marker",
        },
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {out} entries={len(entries)} source_entries={len(package_sources)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
