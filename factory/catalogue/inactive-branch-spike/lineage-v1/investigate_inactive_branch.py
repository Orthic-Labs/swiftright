#!/usr/bin/env python3
"""Strict evidence guard for inactive WidgetBundleBuilder overload."""
from __future__ import annotations

import copy
import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
EDGE = ROOT / "factory/catalogue/compiler-edge-spike/edge-evidence.json"
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
INTERFACE = Path(
    "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/"
    "Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/"
    "Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"
)
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
SWIFTC = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc")
PROBE = HERE / "inline-always-conditional-probe.swift"
PROBE_OUTPUT = HERE / "inline-always-conditional-output.txt"
PROBE_COMPILE_STDOUT = HERE / "inline-always-conditional-compile.stdout"
PROBE_COMPILE_STDERR = HERE / "inline-always-conditional-compile.stderr"
PROBE_RUN_STDERR = HERE / "inline-always-conditional-run.stderr"
EXPECTED_LINK = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
EXPECTED_LINE = 28491
EXPECTED_NAME = "buildLimitedAvailability"
EXPECTED_CONDITION = "compiler(>=5.3) && $InlineAlways"
EXPECTED_GRAPH_USRS = {
    "s:7SwiftUI19WidgetBundleBuilderV24buildLimitedAvailabilityyAA0C0_AA01_ghC6MarkerpxAaERzlFZ",
    "s:7SwiftUI19WidgetBundleBuilderV24buildLimitedAvailabilityyAA0C0_AA01_ghC6MarkerpxAA07ControlC0RzlFZ",
}


def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def parse_rows() -> dict[str, Any]:
    edge = json.loads(EDGE.read_text(encoding="utf-8"))
    row = next(item for item in edge["rows"] if item["key"][2] == EXPECTED_LINE)
    return edge, row


def source_lines(text: str) -> list[str]:
    return text.splitlines()


def conditional_tree(text: str, line_number: int) -> dict[str, Any]:
    lines = source_lines(text)
    matches = [i for i, line in enumerate(lines) if EXPECTED_NAME in line and i + 1 == line_number]
    if len(matches) != 1:
        raise ValueError(f"expected one exact source declaration, got {len(matches)}")
    declaration_index = matches[0]
    if_line = next((i for i in range(declaration_index - 1, -1, -1) if lines[i].strip().startswith("#if ")), None)
    if if_line is None or EXPECTED_CONDITION not in lines[if_line]:
        raise ValueError("missing exact InlineAlways condition")
    else_line = next((i for i in range(if_line + 1, len(lines)) if lines[i].strip() == "#else"), None)
    end_line = next((i for i in range((else_line or if_line) + 1, len(lines)) if lines[i].strip() == "#endif"), None)
    if else_line is None or end_line is None or else_line >= end_line:
        raise ValueError("malformed conditional tree")
    selected = [i + 1 for i in range(if_line + 1, else_line) if EXPECTED_NAME in lines[i]]
    inactive = [i + 1 for i in range(else_line + 1, end_line) if EXPECTED_NAME in lines[i]]
    if len(selected) != 1 or len(inactive) != 1:
        raise ValueError(f"conditional declaration cardinality selected={selected} inactive={inactive}")
    return {
        "condition": lines[if_line].strip()[4:],
        "ifLine": if_line + 1,
        "elseLine": else_line + 1,
        "endifLine": end_line + 1,
        "activeLine": selected[0],
        "inactiveLine": inactive[0],
        "activeText": lines[selected[0] - 1].strip(),
        "inactiveText": lines[inactive[0] - 1].strip(),
        "selectedBranch": "if",
        "inactiveBranch": "else",
    }


def probe_selected() -> str:
    value = PROBE_OUTPUT.read_text(encoding="utf-8").strip()
    if value != "selected=InlineAlways":
        raise ValueError(f"unexpected archived branch probe output: {value!r}")
    return value.split("=", 1)[1]


def mutate_target_condition(source: str, replacement: str) -> str:
    """Change condition on target's own #if, never first matching SDK condition."""
    branch = conditional_tree(source, EXPECTED_LINE)
    lines = source_lines(source)
    lines[branch["ifLine"] - 1] = "  #if " + replacement
    return "\n".join(lines) + ("\n" if source.endswith("\n") else "")


def mutate_target_else(source: str, duplicate: bool) -> str:
    """Remove or duplicate target #else, never another SDK conditional."""
    branch = conditional_tree(source, EXPECTED_LINE)
    lines = source_lines(source)
    else_index = branch["elseLine"] - 1
    end_index = branch["endifLine"] - 1
    if duplicate:
        lines.insert(end_index, lines[else_index])
        lines.insert(end_index + 1, branch["inactiveText"])
    else:
        del lines[else_index]
    return "\n".join(lines) + ("\n" if source.endswith("\n") else "")


def probe_receipt() -> dict[str, Any]:
    return {
        "sourcePath": str(PROBE.relative_to(ROOT)),
        "sourceSha256": sha(PROBE),
        "compileArgv": [
            str(SWIFTC), "-sdk", str(SDK), "-target", "arm64-apple-macosx27.0",
            str(PROBE),
            "-o", "/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/f1-residuals/inactive-branch/inline-always-probe",
        ],
        "compileExitCode": 0,
        "compileStdoutSha256": sha(PROBE_COMPILE_STDOUT),
        "compileStderrSha256": sha(PROBE_COMPILE_STDERR),
        "runExitCode": 0,
        "runStdoutSha256": sha(PROBE_OUTPUT),
        "runStderrSha256": sha(PROBE_RUN_STDERR),
        "runResult": PROBE_OUTPUT.read_text(encoding="utf-8").strip(),
        "swiftcPath": str(SWIFTC),
        "swiftcSha256": sha(SWIFTC),
        "sdkPath": str(SDK),
    }


def verify_descriptor(descriptor: dict[str, Any]) -> bool:
    path_value = descriptor.get("path")
    expected = descriptor.get("sha256")
    if not isinstance(path_value, str) or not isinstance(expected, str):
        return False
    path = Path(path_value)
    if not path.is_absolute():
        path = ROOT / path
    try:
        return path.is_file() and sha(path) == expected
    except OSError:
        return False


def validate(
    candidate: dict[str, Any],
    source: str,
    branch: dict[str, Any],
    selected: str,
    receipt: dict[str, Any],
) -> bool:
    if candidate.get("interfaceSha256") != sha(INTERFACE):
        return False
    if candidate.get("line") != EXPECTED_LINE or candidate.get("name") != EXPECTED_NAME:
        return False
    if candidate.get("kind") != "static-func" or candidate.get("access") != "public":
        return False
    if candidate.get("ownerPath") != ["WidgetBundleBuilder"]:
        return False
    if candidate.get("indexExactLineNameCount") != 0 or candidate.get("cursorResult") != "Unable to resolve cursor info.":
        return False
    if candidate.get("symbolGraphCandidateCount") != 2:
        return False
    graph = candidate.get("symbolGraphCandidates")
    if not isinstance(graph, list) or len(graph) != 2:
        return False
    if {item.get("usr") for item in graph} != EXPECTED_GRAPH_USRS:
        return False
    if any(item.get("pathComponents") != ["WidgetBundleBuilder", "buildLimitedAvailability(_:)"] for item in graph):
        return False
    if candidate.get("sourceSignature") != branch.get("inactiveText"):
        return False
    if candidate.get("cursorResponseSha256") != sha(ROOT / "factory/catalogue/compiler-cursor-spike/buildLimitedAvailability-output.txt"):
        return False
    if candidate.get("indexResponseSha256") != sha(ROOT / "factory/catalogue/compiler-cursor-spike/index-interface-output.txt"):
        return False
    if candidate.get("edgeEvidenceSha256") != sha(EDGE):
        return False
    archived = candidate.get("edgeConditionalControl")
    if not isinstance(archived, dict):
        return False
    for key in ("inlineAlwaysControlSource", "inlineAlwaysControlOutput", "probeSource", "probeOutput"):
        if not verify_descriptor(archived.get(key, {})):
            return False
    if archived.get("inlineAlwaysResult") != "selected=InlineAlways" or archived.get("probeResult") != "selected=active":
        return False
    if candidate.get("requestSha256") != sha(ROOT / "factory/catalogue/compiler-cursor-spike/request-buildLimitedAvailability.yaml"):
        return False
    if candidate.get("swiftcPath") != str(SWIFTC) or candidate.get("swiftcSha256") != sha(SWIFTC):
        return False
    if candidate.get("probeReceipt") != receipt:
        return False
    if receipt.get("runResult") != "selected=InlineAlways" or receipt.get("compileExitCode") != 0 or receipt.get("runExitCode") != 0:
        return False
    if selected != "InlineAlways" or branch.get("condition") != EXPECTED_CONDITION:
        return False
    try:
        actual = conditional_tree(source, EXPECTED_LINE)
    except ValueError:
        return False
    if actual != branch or branch["inactiveLine"] != EXPECTED_LINE or branch["activeLine"] == EXPECTED_LINE:
        return False
    return True


def run(output: Path) -> dict[str, Any]:
    if sha(LINK) != EXPECTED_LINK:
        raise ValueError("immutable 836 link evidence changed")
    edge, edge_row = parse_rows()
    text = INTERFACE.read_text(encoding="utf-8")
    branch = conditional_tree(text, EXPECTED_LINE)
    selected = probe_selected()
    receipt = probe_receipt()
    source_signature = edge_row["interface"]["signature"]
    candidate = {
        "line": EXPECTED_LINE,
        "name": EXPECTED_NAME,
        "kind": "static-func",
        "access": "public",
        "ownerPath": edge_row["interface"]["context"],
        "interfaceSha256": sha(INTERFACE),
        "indexExactLineNameCount": edge_row["raw"]["indexExactLineNameCount"],
        "cursorResult": edge_row["raw"]["cursorResult"],
        "symbolGraphCandidateCount": len(edge_row["symbolGraphCandidates"]),
        "symbolGraphCandidates": copy.deepcopy(edge_row["symbolGraphCandidates"]),
        "requestSha256": edge_row["request"]["sha256"],
        "cursorResponseSha256": edge_row["raw"]["cursorResponse"]["sha256"],
        "indexResponseSha256": edge_row["raw"]["indexResponse"]["sha256"],
        "edgeEvidenceSha256": sha(EDGE),
        "edgeConditionalControl": copy.deepcopy(edge_row["compilerConditionalControl"]),
        "swiftcPath": str(SWIFTC),
        "swiftcSha256": sha(SWIFTC),
        "sourceSignature": source_signature,
        "probeReceipt": receipt,
    }
    if not validate(candidate, text, branch, selected, receipt):
        raise ValueError("production inactive exclusion guard failed baseline")
    controls: dict[str, bool] = {}
    mutated = copy.deepcopy(candidate)
    mutated["line"] = EXPECTED_LINE - 1
    controls["wrongLineRejected"] = not validate(mutated, text, branch, selected, receipt)
    mutated = copy.deepcopy(candidate)
    mutated["name"] = "unknownDeclaration"
    controls["wrongNameRejected"] = not validate(mutated, text, branch, selected, receipt)
    mutated = copy.deepcopy(candidate)
    mutated["kind"] = "func"
    controls["wrongKindRejected"] = not validate(mutated, text, branch, selected, receipt)
    mutated = copy.deepcopy(candidate)
    mutated["access"] = "internal"
    controls["wrongAccessRejected"] = not validate(mutated, text, branch, selected, receipt)
    mutated = copy.deepcopy(candidate)
    mutated["ownerPath"] = ["WrongOwner"]
    controls["wrongOwnerRejected"] = not validate(mutated, text, branch, selected, receipt)
    mutated = copy.deepcopy(candidate)
    mutated["interfaceSha256"] = "sha256:wrong"
    controls["wrongSourceHashRejected"] = not validate(mutated, text, branch, selected, receipt)
    mutated = copy.deepcopy(candidate)
    mutated["requestSha256"] = "sha256:wrong"
    controls["wrongRequestHashRejected"] = not validate(mutated, text, branch, selected, receipt)
    mutated = copy.deepcopy(candidate)
    mutated["swiftcSha256"] = "sha256:wrong"
    controls["wrongToolHashRejected"] = not validate(mutated, text, branch, selected, receipt)
    controls["changedActiveConditionRejected"] = not validate(candidate, mutate_target_condition(text, "compiler(>=5.3) && $OtherFlag"), branch, selected, receipt)
    controls["unknownBranchRejected"] = not validate(candidate, text, branch, "Unknown", receipt)
    controls["elseSelectedRejected"] = not validate(candidate, text, branch, "else", receipt)
    controls["missingElseRejected"] = not validate(candidate, mutate_target_else(text, duplicate=False), branch, selected, receipt)
    controls["duplicateBranchRejected"] = not validate(candidate, mutate_target_else(text, duplicate=True), branch, selected, receipt)
    mutated = copy.deepcopy(candidate)
    mutated["symbolGraphCandidates"][0]["usr"] = "s:fake"
    controls["wrongGraphEntityRejected"] = not validate(mutated, text, branch, selected, receipt)
    mutated = copy.deepcopy(candidate)
    mutated["cursorResponseSha256"] = "sha256:wrong"
    controls["wrongCursorResponseRejected"] = not validate(mutated, text, branch, selected, receipt)
    mutated = copy.deepcopy(candidate)
    mutated["edgeConditionalControl"]["inlineAlwaysResult"] = "selected=else"
    controls["wrongArchivedProbeRejected"] = not validate(mutated, text, branch, selected, receipt)
    mutated = copy.deepcopy(candidate)
    mutated["probeReceipt"] = dict(receipt, runResult="selected=else")
    controls["wrongProbeResultRejected"] = not validate(mutated, text, branch, selected, receipt)
    if not all(controls.values()):
        raise ValueError(f"inactive controls failed: {controls}")
    payload = {
        "kind": "f1-inactive-branch-investigation",
        "version": 1,
        "status": "review-only-inactive-compiler-branch",
        "resolution": {
            "key": edge_row["key"],
            "line": EXPECTED_LINE,
            "name": EXPECTED_NAME,
            "ownerPath": candidate["ownerPath"],
            "kind": candidate["kind"],
            "access": candidate["access"],
            "selectedCondition": EXPECTED_CONDITION,
            "selectedBranch": selected,
            "activeLine": branch["activeLine"],
            "inactiveLine": branch["inactiveLine"],
            "indexExactLineNameCount": candidate["indexExactLineNameCount"],
            "cursorResult": candidate["cursorResult"],
            "symbolGraphCandidateCount": candidate["symbolGraphCandidateCount"],
            "decision": "hold-exact-inactive-else-branch",
        },
        "inputs": {
            "immutableLink": {"path": str(LINK.relative_to(ROOT)), "sha256": sha(LINK), "expectedSha256": EXPECTED_LINK},
            "edgeEvidence": {"path": str(EDGE.relative_to(ROOT)), "sha256": sha(EDGE)},
            "interface": {"path": str(INTERFACE), "sha256": sha(INTERFACE)},
            "cursorRequest": {"path": edge_row["request"]["path"], "sha256": edge_row["request"]["sha256"]},
            "cursorResponse": {"path": edge_row["raw"]["cursorResponse"]["path"], "sha256": edge_row["raw"]["cursorResponse"]["sha256"]},
            "indexResponse": {"path": edge_row["raw"]["indexResponse"]["path"], "sha256": edge_row["raw"]["indexResponse"]["sha256"]},
            "inlineProbeSource": {"path": str(PROBE.relative_to(ROOT)), "sha256": sha(PROBE)},
            "inlineProbeOutput": {"path": str(PROBE_OUTPUT.relative_to(ROOT)), "sha256": sha(PROBE_OUTPUT)},
            "inlineProbeCompileStdout": {"path": str(PROBE_COMPILE_STDOUT.relative_to(ROOT)), "sha256": sha(PROBE_COMPILE_STDOUT)},
            "inlineProbeCompileStderr": {"path": str(PROBE_COMPILE_STDERR.relative_to(ROOT)), "sha256": sha(PROBE_COMPILE_STDERR)},
            "inlineProbeRunStderr": {"path": str(PROBE_RUN_STDERR.relative_to(ROOT)), "sha256": sha(PROBE_RUN_STDERR)},
            "edgeConditionalControl": copy.deepcopy(edge_row["compilerConditionalControl"]),
            "swiftc": {"path": str(SWIFTC), "sha256": sha(SWIFTC)},
            "sdk": str(SDK),
        },
        "probeReceipt": receipt,
        "branch": branch,
        "candidate": candidate,
        "controls": controls,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")
    return payload


if __name__ == "__main__":
    result = run(HERE / "inactive-branch-evidence.json")
    print(json.dumps(result["resolution"], sort_keys=True))
