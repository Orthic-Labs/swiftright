#!/usr/bin/env python3
"""Generate review-only bounded evidence for five duplicate SourceKit rows."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
RAW = HERE / "raw-record-evidence.json"
EXPECTED_LINK = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"


def digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


def load_validator() -> Any:
    path = HERE / "duplicate_identity_validator.py"
    spec = importlib.util.spec_from_file_location("duplicate_validator", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def baseline_args(row: dict[str, Any], payload: dict[str, Any], validator: Any) -> dict[str, Any]:
    source = row["source"]
    inputs = payload["inputs"]
    receipts = payload["receipts"]
    return {
        "row": {"module": row["module"], "sourceHash": source["sha256"], "line": row["line"],
                "kind": row["kind"], "name": row["name"], "context": row["context"],
                "sourceLine": source["lineText"], "activeCondition": source["expectedCondition"],
                "activeBranch": source["activeBranch"]["active"],
                "scopeName": source["enclosingScope"]["name"], "scopeLine": source["enclosingScope"]["line"]},
        "raw_entities": row["raw"]["parsedEntities"],
        "raw_records": row["raw"]["records"],
        "source_text": Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface").read_text(encoding="utf-8"),
        "source_sha256": source["sha256"],
        "request_text": (ROOT / inputs["request"]["path"]).read_text(encoding="utf-8"),
        "request_sha256": inputs["request"]["sha256"],
        "expected_request_sha256": inputs["request"]["sha256"],
        "response_sha256": receipts["sourcekit"]["stdout"]["sha256"],
        "expected_response_sha256": inputs["frozenResponse"]["sha256"],
        "demangle_text": (HERE / "usr-demangle.txt").read_text(encoding="utf-8"),
        "toolchain": payload["toolchain"],
        "expected_toolchain": copy.deepcopy(payload["toolchain"]),
        "source_path": str(Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface")),
    }


def rejects(validator: Any, args: dict[str, Any], **changes: Any) -> bool:
    mutated = copy.deepcopy(args)
    for key, value in changes.items():
        if key == "row":
            mutated["row"].update(value)
        else:
            mutated[key] = value
    return not validator.duplicate_identity_accepts(**mutated)


def mutate_target_section(text: str, usr: str, old: str, new: str) -> str:
    marker = "Demangling for $s" + usr[2:]
    start = text.index(marker)
    end = text.find("\nDemangling for ", start + 1)
    section = text[start:end if end >= 0 else len(text)]
    changed = section.replace(old, new, 1)
    if changed == section:
        raise ValueError(f"target tree marker not found for {usr}")
    return text[:start] + changed + text[end if end >= 0 else len(text):]


def main() -> None:
    payload = json.loads(RAW.read_text(encoding="utf-8"))
    if payload["linkEvidenceSha256"] != EXPECTED_LINK or digest(LINK) != EXPECTED_LINK:
        raise SystemExit("frozen link hash mismatch")
    validator = load_validator()
    rows: list[dict[str, Any]] = []
    for source_row in payload["rows"]:
        args = baseline_args(source_row, payload, validator)
        accepted = validator.validate_duplicate_identity(**args)
        raw = source_row["raw"]["parsedEntities"]
        wrong_usr = copy.deepcopy(raw); wrong_usr[0]["usr"] = "s:7SwiftUI999WrongUSR"
        wrong_kind = copy.deepcopy(raw); wrong_kind[0]["kind"] = "source.lang.swift.decl.class"
        wrong_access = copy.deepcopy(raw); wrong_access[0]["effective_access"] = "source.decl.effective_access.internal"
        wrong_context = copy.deepcopy(raw); wrong_context[0]["sourcekitContext"] = [{"name": "WrongContext"}]
        wrong_line = copy.deepcopy(raw); wrong_line[0]["line"] = source_row["line"] + 1
        wrong_name = copy.deepcopy(raw); wrong_name[0]["name"] = "wrongName"
        third_card = copy.deepcopy(raw) + [copy.deepcopy(raw[0])]
        distinct_record = copy.deepcopy(args["raw_records"])
        distinct_record[1]["text"] = distinct_record[1]["text"].replace("key.column: 14", "key.column: 15", 1)
        if distinct_record[1]["text"] == args["raw_records"][1]["text"]:
            distinct_record[1]["text"] += "\n"
        distinct_entity = copy.deepcopy(raw); distinct_entity[1]["column"] = (distinct_entity[1].get("column") or 0) + 1
        wrong_tree_usr = copy.deepcopy(raw)
        wrong_tree_usr[0]["usr"] = "s:7SwiftUI28DatePickerStyleConfigurationV10$selectionAA7BindingVy10Foundation0C0VGvp"
        if wrong_tree_usr[0]["usr"] == raw[0]["usr"]:
            wrong_tree_usr[0]["usr"] = "s:7SwiftUI24ToggleStyleConfigurationV5$isOnAA7BindingVySbGvp"
        demangle = args["demangle_text"]
        target = "Demangling for $s" + raw[0]["usr"][2:]
        start = demangle.index(target)
        end = demangle.find("\nDemangling for ", start + 1)
        section = demangle[start:end if end >= 0 else len(demangle)]
        duplicate_section = demangle + "\n" + section
        duplicate_module = mutate_target_section(
            demangle, raw[0]["usr"], '      kind=Module, text="SwiftUI"\n',
            '      kind=Module, text="SwiftUI"\n      kind=Module, text="WrongModule"\n')
        duplicate_identifier = mutate_target_section(
            demangle, raw[0]["usr"], '      kind=Identifier, text="' + source_row["context"][0] + '"\n',
            '      kind=Identifier, text="' + source_row["context"][0] + '"\n      kind=Identifier, text="WrongScope"\n')
        controls = {
            "acceptedBaseline": accepted["accepted"],
            "wrongUsrRejected": rejects(validator, args, raw_entities=wrong_usr),
            "wrongKindRejected": rejects(validator, args, raw_entities=wrong_kind),
            "wrongAccessRejected": rejects(validator, args, raw_entities=wrong_access),
            "wrongContextRejected": rejects(validator, args, raw_entities=wrong_context),
            "wrongLineRejected": rejects(validator, args, raw_entities=wrong_line),
            "wrongNameRejected": rejects(validator, args, raw_entities=wrong_name),
            "thirdCardRejected": rejects(validator, args, raw_entities=third_card),
            "distinctRawMetadataRejected": rejects(validator, args, raw_records=distinct_record),
            "distinctEntityMetadataRejected": rejects(validator, args, raw_entities=distinct_entity),
            "wrongTreeUsrRejected": rejects(validator, args, raw_entities=wrong_tree_usr),
            "duplicateTargetTreeSectionRejected": rejects(validator, args, demangle_text=duplicate_section),
            "duplicateTreeModuleRejected": rejects(validator, args, demangle_text=duplicate_module),
            "duplicateTreeIdentifierRejected": rejects(validator, args, demangle_text=duplicate_identifier),
            "wrongModuleRejected": rejects(validator, args, row={"module": "SwiftUICore"}),
            "wrongScopeRejected": rejects(validator, args, row={"scopeName": "WrongScope"}),
            "wrongSourceHashRejected": rejects(validator, args, row={"sourceHash": "sha256:" + "0" * 64}),
            "changedSourceBytesRejected": rejects(validator, args, source_text=args["source_text"].replace("#endif", "#endif ", 1)),
            "wrongRequestRejected": rejects(validator, args, request_text=args["request_text"].replace('"SwiftUI" ]', '"OtherModule" ]', 1)),
            "wrongSourcePathRejected": rejects(validator, args, source_path="/tmp/wrong.swiftinterface"),
            "wrongRequestHashRejected": rejects(validator, args, request_sha256="sha256:" + "0" * 64),
            "wrongResponsePinRejected": rejects(validator, args, response_sha256="sha256:" + "0" * 64),
            "wrongToolchainPinRejected": rejects(validator, args, toolchain={**args["toolchain"], "target": "x86_64-apple-macosx27.0"}),
        }
        rows.append({"key": source_row["key"], "source": source_row["source"], "compilerEvidence": source_row["compilerEvidence"],
                     "raw": source_row["raw"], "usrTreeEvidence": {"demangle": {"path": rel(HERE / "usr-demangle.txt"), "sha256": digest(HERE / "usr-demangle.txt")}, "accepted": accepted},
                     "validator": accepted, "faultControls": controls,
                     "decision": {"status": "held", "promotion": None, "reason": "Duplicate records are accepted only by bounded exact identity proof; no global deduplication exemption."}})
    result = {"kind": "f1-duplicate-identity-evidence", "version": 1, "status": "review-only-five-duplicate-rows",
              "inputs": {"rawRecordEvidence": {"path": rel(RAW), "sha256": digest(RAW)},
                         "validatorSource": {"path": rel(HERE / "duplicate_identity_validator.py"), "sha256": digest(HERE / "duplicate_identity_validator.py")},
                         "investigatorSource": {"path": rel(HERE / "investigate_duplicates.py"), "sha256": digest(HERE / "investigate_duplicates.py")},
                         "linkEvidence": {"path": rel(LINK), "sha256": digest(LINK), "expectedSha256": EXPECTED_LINK}},
              "toolchain": payload["toolchain"], "summary": {"heldCaseCount": 5, "promotionsMade": 0, "allDuplicateRowsExact": all(row["validator"]["accepted"] for row in rows)},
              "controls": {"frozenLinkHashVerified": digest(LINK) == EXPECTED_LINK, "allFiveBaselineAccepted": all(row["validator"]["accepted"] for row in rows), "allFaultControlsNonvacuous": all(all(row["faultControls"].values()) for row in rows)},
              "rows": rows}
    out = HERE / "duplicate-evidence.json"
    out.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
