#!/usr/bin/env python3
"""Pure source controls for WorkloadWin's opt-in same-thread CBT guard."""
from pathlib import Path
import hashlib

ROOT = Path(__file__).resolve().parents[1]
GUARD = ROOT / "qualification/tuple12-workload-startupguard/WorkloadStartupGuard.swift"
MAIN_PATCH = ROOT / "qualification/tuple12-workload-startupguard/main.swift.patch"


def check(text: str) -> None:
    for needle in (
        "import SwiftRightBridge",
        "SetWindowsHookExW",
        "GetCurrentThreadId()",
        "HCBT_ACTIVATE",
        "HCBT_SETFOCUS",
        "CallNextHookEx",
        "UnhookWindowsHookEx",
        "deinit { stop() }",
    ):
        assert needle in text, needle


def main() -> int:
    guard = GUARD.read_text(encoding="utf-8")
    patch = MAIN_PATCH.read_text(encoding="utf-8")
    check(guard)
    for needle in (
        'args.options["sr0-noactivate"] == "1"',
        "SR0WorkloadStartupGuard(enabled: sr0NoActivate)",
        "defer { startupGuard.stop() }",
        "try bridge.run(",
        "return 78",
    ):
        assert needle in patch, needle
    faults = []
    for label, needle in (
        ("bridge-import", "import SwiftRightBridge"),
        ("activation-hook", "HCBT_ACTIVATE"),
        ("focus-hook", "HCBT_SETFOCUS"),
        ("hook-release", "UnhookWindowsHookEx"),
        ("lifetime", "defer { startupGuard.stop() }"),
    ):
        mutated = guard + "\n" + patch
        if needle in mutated:
            mutated = mutated.replace(needle, "")
        try:
            if needle not in mutated:
                raise AssertionError(label)
            check(mutated)
        except AssertionError:
            faults.append(label)
    assert len(faults) == 5, faults
    print("tuple12 workload startupguard controls: PASS positive + 5 mutation faults")
    print("guard_sha256=" + hashlib.sha256(GUARD.read_bytes()).hexdigest())
    print("main_patch_sha256=" + hashlib.sha256(MAIN_PATCH.read_bytes()).hexdigest())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
