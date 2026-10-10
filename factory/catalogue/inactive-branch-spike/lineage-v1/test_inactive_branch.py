#!/usr/bin/env python3
"""Replay checks for inactive WidgetBundleBuilder branch evidence."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EVIDENCE = HERE / "inactive-branch-evidence.json"


def load_guard():
    spec = importlib.util.spec_from_file_location("inactive_guard", HERE / "investigate_inactive_branch.py")
    if spec is None or spec.loader is None:
        raise AssertionError("unable to load inactive guard")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    guard = load_guard()
    payload = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    resolution = payload["resolution"]
    assert payload["status"] == "review-only-inactive-compiler-branch"
    assert resolution["line"] == 28491
    assert resolution["name"] == "buildLimitedAvailability"
    assert resolution["ownerPath"] == ["WidgetBundleBuilder"]
    assert resolution["kind"] == "static-func"
    assert resolution["access"] == "public"
    assert resolution["selectedCondition"] == "compiler(>=5.3) && $InlineAlways"
    assert resolution["selectedBranch"] == "InlineAlways"
    assert resolution["activeLine"] == 28484
    assert resolution["inactiveLine"] == 28491
    assert resolution["indexExactLineNameCount"] == 0
    assert resolution["cursorResult"] == "Unable to resolve cursor info."
    assert resolution["symbolGraphCandidateCount"] == 2
    assert resolution["decision"] == "hold-exact-inactive-else-branch"
    assert all(payload["controls"].values())

    immutable = payload["inputs"]["immutableLink"]
    link = ROOT / immutable["path"]
    assert immutable["sha256"] == immutable["expectedSha256"] == guard.EXPECTED_LINK
    assert digest(link) == immutable["sha256"]

    interface = Path(payload["inputs"]["interface"]["path"])
    assert digest(interface) == payload["inputs"]["interface"]["sha256"]
    probe = payload["probeReceipt"]
    assert probe["runResult"] == "selected=InlineAlways"
    assert digest(HERE / "inline-always-conditional-output.txt") == probe["runStdoutSha256"]
    assert (HERE / "inline-always-conditional-output.txt").read_text().strip() == "selected=InlineAlways"
    assert digest(HERE / "inline-always-conditional-probe.swift") == probe["sourceSha256"]
    assert digest(HERE / "inline-always-conditional-compile.stdout") == probe["compileStdoutSha256"]
    assert digest(HERE / "inline-always-conditional-compile.stderr") == probe["compileStderrSha256"]
    assert digest(HERE / "inline-always-conditional-run.stderr") == probe["runStderrSha256"]

    source = interface.read_text(encoding="utf-8")
    branch = guard.conditional_tree(source, 28491)
    assert branch["condition"] == resolution["selectedCondition"]
    assert branch["inactiveLine"] == resolution["inactiveLine"]
    assert branch["activeLine"] == resolution["activeLine"]

    # Replay production guard against recorded candidate plus current raw inputs.
    assert payload["candidate"]["probeReceipt"] == probe
    assert guard.validate(payload["candidate"], source, branch, "InlineAlways", probe)
    print("inactive branch evidence replay: PASS")


if __name__ == "__main__":
    main()
