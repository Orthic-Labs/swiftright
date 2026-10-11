"""Capture a pinned lexical census plus raw SourceKit record counts.

This is source evidence only. It does not assert Swift grammar completeness,
compiler API completeness, or public API eligibility.
"""
from __future__ import annotations

import collections
import hashlib
import importlib.util
import json
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
INPUT = HERE / "raw"
SNAPSHOT = HERE / "source-snapshot"
SDK_ROOT = Path(
    "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/"
    "Developer/SDKs/MacOSX27.0.sdk"
)
MODULES = {
    "SwiftUI": {
        "source_file": "interfaces/SwiftUI.swiftinterface",
        "source_path": str(SDK_ROOT / "System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"),
        "source_sha256": "sha256:155b00c7d8fa9e9696b96b4bd3291b4c910207b480025d13ba6482f7b9940d38",
        "index_file": "index/SwiftUI.index.txt",
        "index_sha256": "sha256:352c81a020cd442aea487f0d74998f29b27d550b6958fd35582e4e14b3c1ef34",
        "request_file": "index/SwiftUI.request.yaml",
        "request_sha256": "sha256:91ffbe06f6dc3e89074a5daa5d43e9e345e4903b11d70fc5d961601c159d6764",
        "index_lineage": "immutable-836-interface-index",
    },
    "SwiftUICore": {
        "source_file": "interfaces/SwiftUICore.swiftinterface",
        "source_path": str(SDK_ROOT / "System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"),
        "source_sha256": "sha256:4fb89ff3d972d507faee2bde0a7e81761a2cb9c744eaf94df810235918c7ac13",
        "index_file": "index/SwiftUICore.index.txt",
        "index_sha256": "sha256:06ec81f980bad90c171dad909315fe0555df35578efff4a1e173a901babd5520",
        "request_file": "index/SwiftUICore.request.yaml",
        "request_sha256": "sha256:48246455beb6ead6d27c75df9e8715801be7b8d4aeb22b59e1853f0662a22539",
        "index_lineage": "fresh-core-header-correct-index",
    },
}
V12_PATH = INPUT / "index/interface-audit-v12-candidate.json"
V12_SHA256 = "sha256:6f0384e8dfaa1bb21f96c3153cb02425912b6425cfdd534eb01a7f2ab71e1d13"
LINK_PATH = INPUT / "index/immutable-836-link-evidence.json"
LINK_SHA256 = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
CORE_LINEAGE = {
    "index": ("index/SwiftUICore-836-lineage.index.txt", "sha256:293b704c69ef4e80c577a79b23e556f1c480417caac656fddd3b75c2f6ffd506"),
    "request": ("index/SwiftUICore-836-lineage.request.yaml", "sha256:a015dd80fef49c539edc1464d397a2d973ae8fbc8bebda3aef7c213cedf53afa"),
}
PRE_CAPTURE_MANIFEST = HERE / "pre-capture-manifest.json"
LIVE_CAPTURE_SCRIPT = HERE / "live-sdk-validation/capture-live-sdk-source.py"
LIVE_CAPTURE_SCRIPT_SHA256 = "sha256:7010aa3db4c62b4d25cc150b0288a6d2de0fef93ccaa6214ed29db3df08e9cc2"
LIVE_CAPTURE_OUTPUT = HERE / "live-sdk-validation/full-source-census-live-sdk.json"
LIVE_CAPTURE_OUTPUT_SHA256 = "sha256:ea40635179db19a7bdb9b8bb455fd30ce87b0736b42778a22152a80d0f5d8b79"
EXPECTED_PARSER = "sha256:cc6d4dab563f713b91c0ef1f29cbb214a3c129c8f5f3823f438ac24aef75cdd6"
EXPECTED_RAW_PARSER = "sha256:83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5"


def sha256(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot load pinned parser {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def descriptor(path: Path, expected: str | None = None) -> dict:
    actual = sha256(path)
    if expected is not None and actual != expected:
        raise ValueError(f"pinned input hash mismatch: {path}: {actual}")
    try:
        label = str(path.relative_to(HERE))
    except ValueError:
        label = str(path)
    return {"path": label, "sha256": actual, "bytes": path.stat().st_size}


def _scope_payload(scope: dict, module: str) -> dict:
    return {
        "module": module,
        "line": scope["line"],
        "kind": scope["kind"],
        "name": scope["name"],
        "targetSpelling": scope.get("targetSpelling"),
        "normalizedTarget": scope.get("name") if scope["kind"] == "extension" else None,
        "targetNamespaceQualifiers": scope.get("targetNamespaceQualifiers", []),
        "explicitAccess": scope.get("explicitAccess"),
        "conditions": scope["conditions"],
        "attributes": scope["attributes"],
        "path": scope.get("path", []),
        "endLine": scope.get("endLine"),
        "insideFunction": scope.get("insideFunction", False),
    }


def _raw_entity(entity: dict, module: str, index: int) -> dict:
    return {
        "module": module,
        "rawEntityIndex": index,
        "line": entity.get("line"),
        "column": entity.get("column"),
        "kind": entity.get("kind"),
        "name": entity.get("name"),
        "usr": entity.get("usr"),
        "is_implicit": entity.get("is_implicit", False),
        "effective_access": entity.get("effective_access"),
        "sourcekitContext": entity.get("sourcekitContext", []),
    }


def capture() -> dict:
    lexical_path = SNAPSHOT / "lexical_model_v2.py"
    raw_parser_path = SNAPSHOT / "exact_validator.py"
    if sha256(lexical_path) != EXPECTED_PARSER:
        raise ValueError("frozen lexical parser source changed")
    if sha256(raw_parser_path) != EXPECTED_RAW_PARSER:
        raise ValueError("frozen SourceKit record parser source changed")
    lexical = load_module(lexical_path, "census_v2_lexical_model")
    raw_parser = load_module(raw_parser_path, "census_v2_raw_entity_parser")
    if sha256(LIVE_CAPTURE_SCRIPT) != LIVE_CAPTURE_SCRIPT_SHA256:
        raise ValueError("preserved original live-SDK capture source changed")
    if sha256(LIVE_CAPTURE_OUTPUT) != LIVE_CAPTURE_OUTPUT_SHA256:
        raise ValueError("preserved original live-SDK capture output changed")
    live_capture = json.loads(LIVE_CAPTURE_OUTPUT.read_text())
    if live_capture.get("captureScript", {}).get("sha256") != LIVE_CAPTURE_SCRIPT_SHA256:
        raise ValueError("preserved live-SDK output does not identify its original capture source")

    manifest = json.loads(PRE_CAPTURE_MANIFEST.read_text())
    manifest_files = manifest.get("files")
    if not isinstance(manifest_files, list) or not manifest_files:
        raise ValueError("pre-capture source/input manifest is missing files")
    expected_paths = {"capture.py"}
    expected_paths.update(path.relative_to(HERE).as_posix() for path in SNAPSHOT.rglob("*") if path.is_file())
    expected_paths.update(path.relative_to(HERE).as_posix() for path in INPUT.rglob("*") if path.is_file())
    seen_paths = set()
    for item in manifest_files:
        relative = item.get("path")
        if not isinstance(relative, str) or relative in seen_paths:
            raise ValueError("pre-capture manifest has malformed or duplicate path")
        seen_paths.add(relative)
        path = (HERE / relative).resolve()
        if HERE.resolve() not in path.parents or not path.is_file():
            raise ValueError("pre-capture manifest path escapes capture directory or is absent")
        if sha256(path) != item.get("sha256") or path.stat().st_size != item.get("bytes"):
            raise ValueError(f"pre-capture source/input changed: {relative}")
    if seen_paths != expected_paths:
        raise ValueError("pre-capture manifest does not cover exact source/input closure")

    v12 = json.loads(V12_PATH.read_text())
    if sha256(V12_PATH) != V12_SHA256:
        raise ValueError("pinned v12 lineage bytes changed")
    link = json.loads(LINK_PATH.read_text())
    if sha256(LINK_PATH) != LINK_SHA256:
        raise ValueError("pinned 836 link bytes changed")

    source_rows: list[dict] = []
    lexical_modules: dict[str, dict] = {}
    for module, config in MODULES.items():
        source_copy = INPUT / config["source_file"]
        copy_descriptor = descriptor(source_copy, config["source_sha256"])
        live_module = live_capture["sourceCensus"]["modules"][module]
        live_source = live_module.get("installedSdkSource", {})
        if live_source.get("path") != config["source_path"] or live_source.get("sha256") != config["source_sha256"]:
            raise ValueError(f"preserved live-SDK source verification does not match captured {module} copy")
        source = source_copy.read_text()
        parsed = lexical.model(source, module)
        scope_by_line = {scope["line"]: scope for scope in parsed["scopes"]}
        module_rows = []
        line_ordinals: collections.Counter[int] = collections.Counter()
        for ordinal, row in enumerate(parsed["declarations"], 1):
            line = row["line"]
            line_ordinals[line] += 1
            record_id = f"{module}:{line}:{line_ordinals[line]}"
            owner_scopes = [scope_by_line[n] for n in row["scopeLines"]]
            direct_scope = scope_by_line.get(line)
            conditions = row["conditions"]
            frames = [parsed["frames"][item["ifLine"]] for item in conditions]
            source_record = {
                "id": record_id,
                "module": module,
                "interface": "arm64e-apple-macos.swiftinterface",
                "sourceSha256": config["source_sha256"],
                "line": line,
                "lineOrdinal": line_ordinals[line],
                "keywordOffset": row["keywordOffset"],
                "kind": row["kind"],
                "name": row["name"],
                "sourceText": row["text"],
                "explicitAccess": row["explicitAccess"],
                "conditions": conditions,
                "conditionalFrames": frames,
                "attributes": row["attributes"],
                "insideFunction": row["insideFunction"],
                "lexicalOwnerScopes": [_scope_payload(scope, module) for scope in owner_scopes],
                "directScopeIdentity": _scope_payload(direct_scope, module) if direct_scope else None,
            }
            module_rows.append(source_record)
            source_rows.append(source_record)
        scope_rows = [_scope_payload(scope, module) for scope in parsed["scopes"]]
        lexical_modules[module] = {
            "sourceCopy": copy_descriptor,
            "installedSdkSourceReference": {
                "path": config["source_path"],
                "sha256": copy_descriptor["sha256"],
                "bytes": copy_descriptor["bytes"],
                "verification": "matched-by-preserved-pinned-live-sdk-capture",
            },
            "declarationStartCount": len(module_rows),
            "extensionScopeCount": sum(x["kind"] == "extension" for x in scope_rows),
            "nominalScopeCount": sum(x["kind"] in lexical.NOMINAL for x in scope_rows),
            "declarationKinds": dict(sorted(collections.Counter(x["kind"] for x in module_rows).items())),
            "declarations": module_rows,
            "nominalAndExtensionScopes": scope_rows,
            "conditionalFrames": list(parsed["frames"].values()),
        }

    # V12 relation is exact module + line + source family + parsed source name.
    source_by_key: dict[tuple, list[str]] = collections.defaultdict(list)
    source_by_line_family: dict[tuple, list[str]] = collections.defaultdict(list)
    for row in source_rows:
        source_by_key[(row["module"], row["line"], row["kind"], row["name"])].append(row["id"])
        source_by_line_family[(row["module"], row["line"], row["kind"])].append(row["id"])
    lineage_rows = []
    for ordinal, row in enumerate(v12["declarations"], 1):
        key = (row["module"], row["line"], row["kind"], row["name"])
        exact = source_by_key.get(key, [])
        family = source_by_line_family.get(key[:3], [])
        state = "exact-source-start" if len(exact) == 1 else (
            "multiple-exact-source-starts" if len(exact) > 1 else (
                "unique-line-family-source-start-name-differs" if len(family) == 1 else (
                    "ambiguous-line-family-source-start-name-differs" if family else "no-same-line-family-start"
                )
            )
        )
        lineage_rows.append({
            "v12DeclarationOrdinal": ordinal,
            "v12Key": [row["module"], row["interface"], row["line"], row["kind"], row["name"]],
            "state": state,
            "sourceStartIds": exact if exact else family,
            "sourceNames": [next(row["name"] for row in source_rows if row["id"] == source_id)
                            for source_id in (exact if exact else family)],
        })
    lineage_counts = collections.Counter(row["state"] for row in lineage_rows)
    addressed_lineages = lineage_counts["exact-source-start"] + lineage_counts["unique-line-family-source-start-name-differs"]
    addressed_source_ids = [row["sourceStartIds"][0] for row in lineage_rows if len(row["sourceStartIds"]) == 1]
    if len(addressed_source_ids) != addressed_lineages or len(set(addressed_source_ids)) != addressed_lineages:
        raise ValueError("v12 rows do not map one-to-one to exact or unique line/family source starts")
    source_by_id = {row["id"]: row for row in source_rows}
    if any(source_by_id[item]["kind"] == "extension" for item in addressed_source_ids):
        raise ValueError("v12 lineage unexpectedly maps to an extension header")
    nonextension_count = sum(row["kind"] != "extension" for row in source_rows)

    raw_index = {}
    for module, config in MODULES.items():
        index_path = INPUT / config["index_file"]
        request_path = INPUT / config["request_file"]
        index_descriptor = descriptor(index_path, config["index_sha256"])
        request_descriptor = descriptor(request_path, config["request_sha256"])
        request_text = request_path.read_text()
        if module == "SwiftUI":
            if '"-module-name", "SwiftUI"' not in request_text or '"-target", "arm64-apple-macosx27.0"' not in request_text:
                raise ValueError("SwiftUI SourceKit request identity differs from pinned module/target")
        else:
            required = (
                '"-module-name", "SwiftUICore"',
                '"-public-module-name", "SwiftUI"',
                '"-module-abi-name", "SwiftUI"',
                '"-target", "arm64-apple-macosx27.0"',
            )
            if not all(token in request_text for token in required):
                raise ValueError("fresh Core SourceKit request lacks exact SwiftUI ABI/module identity")
        raw_records = raw_parser.entities(index_path.read_text())
        raw_index[module] = {
            "lineage": config["index_lineage"],
            "request": request_descriptor,
            "output": index_descriptor,
            "rawEntityCount": len(raw_records),
            "distinctUsrCount": len({item.get("usr") for item in raw_records if item.get("usr")}),
            "rawEntityKinds": dict(sorted(collections.Counter(str(x.get("kind")) for x in raw_records).items())),
            "effectiveAccessValues": dict(sorted(collections.Counter(str(x.get("effective_access")) for x in raw_records).items())),
            "records": [_raw_entity(item, module, index) for index, item in enumerate(raw_records, 1)],
        }

    lineage_index_path, lineage_index_hash = CORE_LINEAGE["index"]
    lineage_request_path, lineage_request_hash = CORE_LINEAGE["request"]
    lineage_index = INPUT / lineage_index_path
    lineage_request = INPUT / lineage_request_path
    lineage_records = raw_parser.entities(lineage_index.read_text())
    core_receipt_path = INPUT / "index/SwiftUICore.run-receipt.json"
    core_stderr_path = INPUT / "index/SwiftUICore.stderr.txt"
    core_flags_path = INPUT / "index/SwiftUICore.header-flags.json"
    core_tool_versions_path = INPUT / "index/SwiftUICore.tool-versions.json"
    core_index_evidence_path = INPUT / "index/SwiftUICore.header-index-evidence.json"
    core_receipt = json.loads(core_receipt_path.read_text())
    if core_receipt.get("sourceSha256") != MODULES["SwiftUICore"]["source_sha256"]:
        raise ValueError("fresh Core index receipt source hash differs from captured interface")
    if core_receipt.get("sourcekit", {}).get("stdout", {}).get("sha256") != MODULES["SwiftUICore"]["index_sha256"]:
        raise ValueError("fresh Core index receipt output hash differs from captured index stream")
    if core_receipt.get("request", {}).get("sha256") != MODULES["SwiftUICore"]["request_sha256"]:
        raise ValueError("fresh Core index receipt request differs from captured request")
    lineage_capture = {
        "module": "SwiftUICore",
        "lineage": "immutable-836-core-index-only-lineage",
        "request": descriptor(lineage_request, lineage_request_hash),
        "output": descriptor(lineage_index, lineage_index_hash),
        "rawEntityCount": len(lineage_records),
        "distinctUsrCount": len({item.get("usr") for item in lineage_records if item.get("usr")}),
        "rawEntityKinds": dict(sorted(collections.Counter(str(x.get("kind")) for x in lineage_records).items())),
        "effectiveAccessValues": dict(sorted(collections.Counter(str(x.get("effective_access")) for x in lineage_records).items())),
        "records": [_raw_entity(item, "SwiftUICore", index) for index, item in enumerate(lineage_records, 1)],
    }
    old_count = raw_index["SwiftUI"]["rawEntityCount"] + lineage_capture["rawEntityCount"]
    fresh_count = raw_index["SwiftUI"]["rawEntityCount"] + raw_index["SwiftUICore"]["rawEntityCount"]
    census_total = len(source_rows)
    extension_starts = sum(row["kind"] == "extension" for row in source_rows)
    nonextension_starts = census_total - extension_starts
    script_path = Path(__file__).resolve()
    return {
        "kind": "sdk-full-source-lexical-census",
        "version": 2,
        "status": "raw-census-only-no-universal-swift-grammar-or-public-api-completeness-claim",
        "captureScript": {"path": str(script_path.relative_to(HERE)), "sha256": sha256(script_path)},
        "parserSnapshot": {
            "lexicalModelV2": {"path": "source-snapshot/lexical_model_v2.py", "sha256": sha256(lexical_path)},
            "sourceKitRecordParser": {"path": "source-snapshot/exact_validator.py", "sha256": sha256(raw_parser_path)},
            "strictMatchParserSnapshotPresentButNotExecuted": {
                "path": "source-snapshot/strict_match.py",
                "sha256": sha256(SNAPSHOT / "strict_match.py"),
            },
        },
        "preCaptureSnapshotManifest": {
            "path": str(PRE_CAPTURE_MANIFEST.relative_to(HERE)),
            "sha256": sha256(PRE_CAPTURE_MANIFEST),
            "fileCount": len(manifest_files),
        },
        "preservedLiveSdkCheck": {
            "captureScript": {"path": str(LIVE_CAPTURE_SCRIPT.relative_to(HERE)), "sha256": sha256(LIVE_CAPTURE_SCRIPT)},
            "captureOutput": {"path": str(LIVE_CAPTURE_OUTPUT.relative_to(HERE)), "sha256": sha256(LIVE_CAPTURE_OUTPUT)},
            "replayMode": "archived-source-and-raw-inputs-only; does-not-read-installed-SDK-or-cache",
        },
        "immutableReferences": {
            "v12Audit": descriptor(V12_PATH, V12_SHA256),
            "v12DeclaredStartCount": len(v12["declarations"]),
            "immutable836Link": descriptor(LINK_PATH, LINK_SHA256),
            "target": "arm64-apple-macosx27.0",
            "sdk": str(SDK_ROOT),
            "xcode": "Xcode 27.0 (27A266)",
            "compiler": json.loads(LINK_PATH.read_text())["pinnedInputs"]["compiler"],
            "symbolGraphTarget": json.loads(LINK_PATH.read_text())["pinnedInputs"]["symbolGraphTarget"],
            "sourceKitToolchainEvidence": json.loads(LINK_PATH.read_text())["toolchainEvidence"],
        },
        "sourceCensus": {
            "declarationStarts": census_total,
            "extensionHeaderStarts": extension_starts,
            "nonextensionDeclarationStarts": nonextension_starts,
            "nominalScopeCount": sum(v["nominalScopeCount"] for v in lexical_modules.values()),
            "extensionScopeCount": sum(v["extensionScopeCount"] for v in lexical_modules.values()),
            "v12LineageRows": len(lineage_rows),
            "v12LineageJoinStates": dict(sorted(lineage_counts.items())),
            "v12LineageRowsAddressedByExactKeyOrUniqueLineAndFamily": addressed_lineages,
            "v12LineageRowsUnaddressedOrAmbiguous": len(lineage_rows) - addressed_lineages,
            "distinctSourceStartsAddressedByV12": len(set(addressed_source_ids)),
            "v12SourceStartMappingIsOneToOne": len(set(addressed_source_ids)) == len(lineage_rows),
            "addedNonextensionSourceStartsBeyondV12": nonextension_count - len(set(addressed_source_ids)),
            "modules": lexical_modules,
            "v12LineageJoins": lineage_rows,
        },
        "sourceKitCensus": {
            "immutable836ObservedRawEntityCount": old_count,
            "freshUiPlusCoreHeaderObservedRawEntityCount": fresh_count,
            "uiPlusCoreRecordCountAgreesAcrossOldAndFreshCoreInputs": old_count == fresh_count,
            "modules": raw_index,
            "immutable836CoreLineage": lineage_capture,
            "freshCoreHeaderIndexReceipt": descriptor(core_receipt_path, "sha256:69b9f36244cbf45bb7f86aa5e9a768f120c1908daa6b0d1ffd41e77bed4994b7"),
            "freshCoreHeaderIndexReceiptContents": core_receipt,
            "freshCoreHeaderFlags": json.loads(core_flags_path.read_text()),
            "freshCoreToolVersions": json.loads(core_tool_versions_path.read_text()),
            "freshCoreHeaderIndexEvidence": json.loads(core_index_evidence_path.read_text()),
            "freshCoreHeaderAuxiliaryInputs": [
                descriptor(core_stderr_path, "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
                descriptor(core_flags_path, "sha256:4337bdc164f77db8d26ae61aaa3f7e2f2106a3693f16f8051ce84fdfe7219984"),
                descriptor(core_tool_versions_path, "sha256:f9bcceac918dbab6e6fad70e81b452b3fdb895bbb7ef93a3bf0fc652f41c6ba4"),
                descriptor(core_index_evidence_path, "sha256:ed8b67a39f3273f5f8f6789c5b58e9d67b3050db79468b1b4bc76bc40f705acf"),
            ],
        },
        "scope": "Two installed SDK interfaces plus captured SourceKit index streams only. Conditional branches, lexical scopes, explicit access spelling, extension target spelling, and raw compiler records are retained as observed. No API-eligibility classifications are inferred here.",
        "limitations": [
            "Lexical parser output enumerates constructs recognized by pinned lexical_model_v2.py; it is not a universal Swift grammar proof.",
            "Counts of SourceKit records describe captured streams, not all compiler-generated declarations or all SDK API.",
            "A source start or raw compiler entity is not thereby public, eligible, hidden, or resolved to another representation.",
            "V12 joins use exact module, line, declaration family, and source name; non-exact rows stay explicitly classified with candidate source IDs, not guessed repairs.",
            "SwiftUICore’s 836 index is preserved as lineage. Fresh header-correct Core request/output are separate observations; their access fields differ in places.",
        ],
    }


if __name__ == "__main__":
    output = HERE / "full-source-census-v2.json"
    output.write_text(json.dumps(capture(), sort_keys=True, separators=(",", ":")) + "\n")
    print(json.dumps({"path": str(output), "sha256": sha256(output)}))
