#!/usr/bin/env python3
"""Strict verifier for captured projected-variable compiler evidence."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
EVIDENCE = HERE / "projected-variable-evidence.json"
SOURCE = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface")
EXPECTED_SOURCE = "155b00c7d8fa9e9696b96b4bd3291b4c910207b480025d13ba6482f7b9940d38"
EXPECTED_LINK = "836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
EXPECTED_RAW = "5287ecdbd267d2d30196855233ee285914b7e6bb4c24e25dafa911386bb1c89f"
EXPECTED = {
    4080: ("$isOn", "ToggleStyleConfiguration", "s:7SwiftUI24ToggleStyleConfigurationV4isOnSbvp", 2),
    5533: ("$isExpanded", "DisclosureGroupStyleConfiguration", "s:7SwiftUI33DisclosureGroupStyleConfigurationV10isExpandedSbvp", 2),
    9717: ("$document", "ReferenceFileDocumentConfiguration", "s:7SwiftUI34ReferenceFileDocumentConfigurationV8documentxvp", 2),
    23750: ("$document", "FileDocumentConfiguration", "s:7SwiftUI25FileDocumentConfigurationV8documentxvp", 2),
    31446: ("switch", "ToggleStyle", "s:7SwiftUI11ToggleStylePA2A06SwitchcD0VRszrlE6switchAEvpZ", 1),
    32822: ("$selection", "DatePickerStyleConfiguration", "s:7SwiftUI28DatePickerStyleConfigurationV9selection10Foundation0C0Vvp", 2),
}
EXPECTED_OFFSET = {4080: 238026, 5533: 317223, 9717: 565108, 23750: 1354326, 31446: 1798666, 32822: 1877035}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(data: dict, root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    frozen = root / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
    raw = root / "factory/catalogue/duplicate-identity-spike/raw-record-evidence.json"
    if digest(frozen) != EXPECTED_LINK:
        errors.append("frozen link evidence hash")
    if digest(raw) != EXPECTED_RAW:
        errors.append("frozen raw archive hash")
    try:
        source_bytes = SOURCE.read_bytes()
    except OSError:
        return ["source unreadable"]
    if hashlib.sha256(source_bytes).hexdigest() != EXPECTED_SOURCE:
        errors.append("source hash")
    if data.get("status") != "review-only" or data.get("promotionsMade") != 0:
        errors.append("promotion/status")
    if data.get("inputs", {}).get("frozenLinkEvidence", {}).get("sha256") != "sha256:" + EXPECTED_LINK:
        errors.append("evidence link pin")
    if data.get("inputs", {}).get("source", {}).get("sha256") != "sha256:" + EXPECTED_SOURCE:
        errors.append("evidence source pin")
    rows = data.get("rows")
    if not isinstance(rows, list) or len(rows) != len(EXPECTED):
        return errors + ["row count"]
    seen: set[int] = set()
    lines = source_bytes.decode("utf-8").splitlines(keepends=True)
    for row in rows:
        line_no = row.get("line")
        if line_no in seen or line_no not in EXPECTED:
            errors.append(f"unexpected/duplicate row {line_no}"); continue
        seen.add(line_no)
        name, context, cursor_usr, occurrence_count = EXPECTED[line_no]
        if row.get("name") != name or row.get("context") != context:
            errors.append(f"row identity {line_no}")
        line = lines[line_no - 1].rstrip("\r\n")
        if row.get("sourceLine") != line or name not in line:
            errors.append(f"source line {line_no}")
        line_start = sum(len(x.encode()) for x in lines[: line_no - 1])
        expected_offset = line_start + len(line[:line.index(name)].encode())
        if row.get("lineStartByteOffset") != line_start or row.get("nameByteOffset") != expected_offset or expected_offset != EXPECTED_OFFSET[line_no]:
            errors.append(f"source offset {line_no}")
        c = row.get("cursor", {}).get("fields", {})
        if c.get("name") != name or c.get("usr") != cursor_usr or c.get("modulename") != "SwiftUI" or c.get("kind") not in {"source.lang.swift.decl.var.instance", "source.lang.swift.decl.var.static"}:
            errors.append(f"cursor identity {line_no}")
        receipt = row.get("receipt", {})
        if receipt.get("exitCode") != 0 or receipt.get("stderr", {}).get("bytes") != 0:
            errors.append(f"compiler receipt {line_no}")
        request_path = root / row.get("request", "")
        output_path = root / row.get("response", "")
        if not request_path.is_file() or digest(request_path) != row.get("requestSha256", "").removeprefix("sha256:"):
            errors.append(f"request bytes {line_no}")
        if not output_path.is_file() or digest(output_path) != row.get("responseSha256", "").removeprefix("sha256:"):
            errors.append(f"response bytes {line_no}")
        occurrences = row.get("rawIdentity", {}).get("occurrences", [])
        if len(occurrences) != occurrence_count:
            errors.append(f"raw cardinality {line_no}")
        for occurrence in occurrences:
            if occurrence.get("name") != name or occurrence.get("line") != line_no or occurrence.get("usr") != row.get("frozenLinkRow", {}).get("occurrences", [{}])[0].get("usr"):
                errors.append(f"raw identity {line_no}")
            if occurrence.get("sourcekitContext", [{}])[0].get("name") != context:
                errors.append(f"raw context {line_no}")
        archive = row.get("rawIdentity", {}).get("duplicateArchive")
        if line_no == 31446 and archive is not None:
            errors.append("unique row has duplicate archive")
        if line_no != 31446 and (not archive or archive.get("sha256") != "sha256:" + EXPECTED_RAW or not archive.get("row", {}).get("fullRecordByteEqual")):
            errors.append(f"duplicate proof {line_no}")
    if seen != set(EXPECTED):
        errors.append("missing rows")
    demangle = data.get("rawSymbolTree", {}).get("receipt", {})
    if demangle.get("exitCode") != 0 or demangle.get("stdin", {}).get("bytes", 0) == 0 or demangle.get("stdout", {}).get("bytes", 0) == 0:
        errors.append("demangle receipt")
    return errors


def main() -> int:
    data = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    errors = validate(data)
    if errors:
        raise SystemExit("; ".join(errors))
    print("projected variable capture valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
