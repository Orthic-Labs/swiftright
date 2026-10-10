"""Additive v8 audit scaffold pinned to committed v7 evidence.

V8 does not trust evidence flags or infer compiler visibility. Later receipts
must be independently revalidated before any row changes classification.
"""
from __future__ import annotations

import copy
import importlib.util
import json
import re
from functools import lru_cache
from collections import Counter
from pathlib import Path
from typing import Any

from factory.core import artifacts
from . import audit_v7

V7_AUDIT_HASH = "sha256:164636eee04c1c16df9a1a2021ab1c9831354aefd6e08159d40332fa2078f448"
V7_FILE_SHA256 = "sha256:60275e0e06996fa23615da56ae1e3566102a5889070625efca3660c74f8d20df"
SOURCEKIT_LINK_SHA256 = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
ACCESS_BRIDGE_SHA256 = "sha256:9c54ebc0829b0e59d4882a8b46b6b7319bcde5ec92886313b79376c4adfd42c4"
ACCESS_VALIDATOR_SHA256 = "sha256:8af523fda9b246c317c5b63127146d6f99cb2ba25edf1c4962f38e5aeab97c3e"
ACCESS_TEST_SHA256 = "sha256:8e5b90c8abe96c800d1520494b76b47590e42f8df449f9d895c43da50cb2dd0d"
ACCESS_SCHEMA_SHA256 = "sha256:0f3044f3304331e972acb7b721dd3f6ab36a16a9e0aefa8fc785ae281a7bea24"
ACCESS_MANIFEST_SHA256 = "sha256:89b472b0a32acad994fdddb884368523d7ab90cfbe8f40f7e37e66272d228666"
RESIDUAL_CLASSIFICATIONS = {"active-compiler-conditional-unmapped", "ambiguous-context-signature", "unexplained"}


def _validate_pinned_v7(value: dict[str, Any], observed_file_hash: str) -> dict[str, Any]:
    if observed_file_hash != V7_FILE_SHA256:
        raise ValueError("v7 bytes differ from committed v7 audit snapshot")
    authority = value.get("sourceKitAuthority", {})
    if authority.get("evidenceSha256") != SOURCEKIT_LINK_SHA256:
        raise ValueError("v7 does not pin expected immutable SourceKit link evidence")
    body = dict(value)
    declared_hash = body.pop("auditHash", None)
    if declared_hash != V7_AUDIT_HASH or artifacts.canonical_hash(body) != declared_hash:
        raise ValueError("v7 audit hash differs from committed canonical v7 snapshot")
    return value


def _load_pinned_v7(path: Path) -> dict[str, Any]:
    return _validate_pinned_v7(json.loads(path.read_text(encoding="utf-8")), artifacts.file_hash(path))


def _normal_context(value: list[Any]) -> tuple[str, ...]:
    return tuple(str(item).split(".")[-1].split("<", 1)[0] for item in value)


def _raw_access_entity(row: dict[str, Any], module_entities: list[dict[str, Any]]) -> dict[str, Any]:
    candidates = [entity for entity in module_entities
                  if entity.get("line") == row["line"]
                  and entity.get("kind") == "source.lang.swift.decl.enumelement"
                  and audit_v7._name_matches(str(entity.get("name", "")), str(row["name"]))
                  and _normal_context([item.get("name", "") for item in entity.get("sourcekitContext", [])])
                  == _normal_context(row["context"])]
    if len(candidates) != 1:
        raise ValueError(f"access bridge raw SourceKit entity cardinality is {len(candidates)} for {row.get('module')}:{row.get('line')}")
    entity = candidates[0]
    if entity.get("is_implicit") is True or entity.get("is_implicit") == 1:
        raise ValueError("access bridge raw SourceKit entity is implicit")
    return entity


def _validate_access_entity_claim(candidate: dict[str, Any], entity: dict[str, Any]) -> None:
    if (candidate.get("rawEntityCount") != 1 or candidate.get("rawEntityKind") != entity.get("kind")
            or candidate.get("rawEntityName") != entity.get("name")
            or candidate.get("rawEntityLine") != entity.get("line")
            or candidate.get("rawEntityColumn") != entity.get("column")
            or candidate.get("usr") != entity.get("usr")
            or candidate.get("effectiveAccess") not in {"public", "open"}
            or entity.get("effective_access") != f"source.decl.effective_access.{candidate.get('effectiveAccess')}"):
        raise ValueError("access bridge claim differs from unique raw SourceKit entity")
    sourcekit_context = [{key: item.get(key) for key in ("kind", "name")}
                         for item in entity.get("sourcekitContext", [])]
    if candidate.get("sourcekitContext") != sourcekit_context:
        raise ValueError("access bridge SourceKit context differs from raw response")


@lru_cache(maxsize=4)
def _parsed_access_scopes(interface_path: str, module: str) -> dict[int, list[dict[str, Any]]]:
    parser_path = Path(__file__).resolve().parent / "access-inheritance-spike/exact_access_bridge.py"
    if artifacts.file_hash(parser_path) != ACCESS_VALIDATOR_SHA256:
        raise ValueError("access scope parser bytes differ from reviewed validator")
    spec = importlib.util.spec_from_file_location("_sr1_v8_access_scope_parser", parser_path)
    if spec is None or spec.loader is None:
        raise ValueError("cannot load pinned access scope parser")
    parser = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(parser)
    return parser.parse_lexical_scopes(Path(interface_path), module)


def _validate_access_scope(row: dict[str, Any], interface_path: Path) -> None:
    """Reparse exact scopes with pinned production parser before trusting receipt."""
    row_line = row.get("line")
    parsed = _parsed_access_scopes(str(interface_path), str(row.get("module")))
    actual = parsed.get(row_line)
    if actual != row.get("lexicalScopes"):
        raise ValueError("access bridge lexical scopes differ from independently reparsed source scopes")

    lines = interface_path.read_text(encoding="utf-8").splitlines()
    scopes = row.get("lexicalScopes")
    context = _normal_context(row.get("context", []))
    if not isinstance(scopes, list) or len(scopes) != len(context):
        raise ValueError("access bridge lexical scope count differs from context")
    if tuple(str(scope.get("name", "")) for scope in scopes) != context:
        raise ValueError("access bridge lexical scope names differ from context")
    for index, scope in enumerate(scopes):
        start, end = scope.get("startLine"), scope.get("endLine")
        if (not isinstance(start, int) or not isinstance(end, int) or start < 1 or end < row["line"]
                or start > row["line"] or end > len(lines)):
            raise ValueError("access bridge lexical scope range does not contain case line")
        if scope.get("module") != row["module"]:
            raise ValueError("access bridge lexical scope module differs from source module")
        if scope.get("declaration") != lines[start - 1].strip():
            raise ValueError("access bridge scope declaration differs from pinned interface source line")
        if scope.get("resolvedAccess") not in {"public", "open"}:
            raise ValueError("access bridge scope is not proven public/open")
        if index and (scopes[index - 1].get("startLine", 0) > start
                      or scopes[index - 1].get("endLine", len(lines) + 1) < end):
            raise ValueError("access bridge lexical scope ranges are not properly nested")
        if scope.get("kind") == "extension":
            target = str(scope.get("target", ""))
            declared = re.match(r"^\s*extension\s+([A-Za-z_$][A-Za-z_0-9$]*(?:(?:::|\.)[A-Za-z_$][A-Za-z_0-9$]*)*)", lines[start - 1])
            if not declared or declared.group(1) != target:
                raise ValueError("access bridge extension target differs from exact interface declaration")
            target_parts = target.replace("::", ".").split(".")
            if target_parts[0] == row["module"]:
                target_parts = target_parts[1:]
            qualified_target = ".".join(target_parts)
            if scope.get("qualifiedTarget") != qualified_target or scope.get("resolvedQualifiedName") != qualified_target:
                raise ValueError("access bridge extension owner is not exact module-relative qualified target")
            owner_chain = scope.get("resolvedOwnerChain")
            if not isinstance(owner_chain, list) or not owner_chain:
                raise ValueError("access bridge extension lacks resolved compiler owner chain")
            owner_names = [str(owner.get("name", "")) for owner in owner_chain]
            if owner_names != target_parts:
                raise ValueError("access bridge extension owner chain differs from qualified target")
            for owner_index, owner in enumerate(owner_chain):
                owner_start = owner.get("startLine")
                if (owner.get("module") != row["module"] or owner.get("resolvedAccess") not in {"public", "open"}
                        or owner.get("kind") not in {"struct", "enum", "class", "actor", "protocol"}
                        or not isinstance(owner_start, int) or owner_start < 1 or owner_start > len(lines)
                        or owner.get("declaration") != lines[owner_start - 1].strip()
                        or owner.get("explicitAccess") not in {"public", "open"}):
                    raise ValueError("access bridge extension owner chain lacks exact visible source declaration")
                owner_decl = re.match(r"^\s*(?:(?:@[\w.]+(?:\([^)]*\))?)\s+)*(public|open)\s+(?:indirect\s+)?(struct|enum|class|actor|protocol)\s+`?([A-Za-z_$][A-Za-z_0-9$]*)", owner["declaration"])
                if not owner_decl or (owner_decl.group(1), owner_decl.group(2), owner_decl.group(3)) != (
                        owner.get("explicitAccess"), owner.get("kind"), owner.get("name")):
                    raise ValueError("access bridge extension owner source declaration identity mismatch")
                expected_prefix = ".".join(owner_names[:owner_index + 1])
                if owner.get("qualifiedName") != expected_prefix:
                    raise ValueError("access bridge extension owner qualified chain is inconsistent")
        else:
            declaration = lines[start - 1]
            match = re.match(r"^\s*(?:(?:@[\w.]+(?:\([^)]*\))?)\s+)*(public|open)\s+(?:indirect\s+)?(struct|enum|class|actor|protocol)\s+`?([A-Za-z_$][A-Za-z_0-9$]*)", declaration)
            if not match or match.group(1) != scope.get("explicitAccess"):
                raise ValueError("access bridge type scope lacks exact explicit public/open source declaration")
            if match.group(2) != scope.get("kind") or match.group(3) != scope.get("name"):
                raise ValueError("access bridge type scope kind/name differs from source declaration")
    if scopes[-1].get("kind") != "enum":
        raise ValueError("access bridge nearest lexical scope is not enum")


def _validate_live_tool_bindings(bindings: dict[str, Any]) -> None:
    for label, record, path_key in (
        ("compiler", bindings.get("compiler", {}), "executablePath"),
        ("sourcekitLsp", bindings.get("sourcekitLsp", {}), "path"),
        ("sourcekitd", bindings.get("sourcekitd", {}), "path"),
    ):
        executable = Path(str(record.get(path_key, "")))
        if not executable.is_file() or artifacts.file_hash(executable) != record.get("sha256"):
            raise ValueError(f"access bridge live {label} binary differs from pinned hash")


def _validate_access_bridge(bridge_path: Path, v7: dict[str, Any], *, root: Path) -> list[dict[str, Any]]:
    if artifacts.file_hash(bridge_path) != ACCESS_BRIDGE_SHA256:
        raise ValueError("access bridge bytes differ from Oracle-cleared receipt")
    access_dir = root / "factory/catalogue/access-inheritance-spike"
    pins = {
        access_dir / "exact_access_bridge.py": ACCESS_VALIDATOR_SHA256,
        access_dir / "test_exact_access_bridge.py": ACCESS_TEST_SHA256,
        access_dir / "BRIDGE-SCHEMA.md": ACCESS_SCHEMA_SHA256,
        access_dir / "bridge-manifest.txt": ACCESS_MANIFEST_SHA256,
    }
    for path, expected in pins.items():
        if artifacts.file_hash(path) != expected:
            raise ValueError(f"access bridge consumer pin changed: {path.name}")
    bridge = json.loads(bridge_path.read_text(encoding="utf-8"))
    if bridge.get("kind") != "compiler-enum-case-access-bridge" or bridge.get("version") != 1:
        raise ValueError("unexpected access bridge kind/version")
    summary = bridge.get("summary", {})
    if summary != {"heldRows": 0, "sourceRows": 51, "uniqueCompilerUsrs": 51, "validatedRows": 51}:
        raise ValueError("access bridge summary differs from reviewed 51-row receipt")
    if bridge.get("validatorSourceSha256") != ACCESS_VALIDATOR_SHA256:
        raise ValueError("access bridge does not bind reviewed validator source")
    seed_path = root / bridge.get("seedAccessEvidencePath", "")
    receipt_path = root / bridge.get("seedRunReceiptPath", "")
    if artifacts.file_hash(seed_path) != bridge.get("seedAccessEvidenceSha256"):
        raise ValueError("access bridge seed evidence bytes changed")
    if artifacts.file_hash(receipt_path) != bridge.get("seedRunReceiptSha256"):
        raise ValueError("access bridge seed run receipt bytes changed")
    link_path = root / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
    links = json.loads(link_path.read_text(encoding="utf-8"))
    if artifacts.file_hash(link_path) != SOURCEKIT_LINK_SHA256:
        raise ValueError("access bridge SourceKit link archive changed")
    bindings = bridge.get("bindings", {})
    if bindings.get("sourceLinkSha256") != SOURCEKIT_LINK_SHA256:
        raise ValueError("access bridge binds different SourceKit link archive")
    if bindings.get("auditHash") != links.get("pinnedInputs", {}).get("auditHash"):
        raise ValueError("access bridge SourceKit archive binds different parent audit")
    if bindings.get("target") != v7.get("symbolgraphTarget"):
        raise ValueError("access bridge target differs from pinned v7 graph target")
    pinned_sdk = v7["sourceKitAuthority"]["pinnedInputs"]["sdk"]
    if bindings.get("sdkPath") != pinned_sdk:
        raise ValueError("access bridge SDK differs from pinned v7 SDK")
    sdk_settings = Path(bindings.get("sdkSettingsPath", ""))
    if artifacts.file_hash(sdk_settings) != bindings.get("sdkSettingsSha256"):
        raise ValueError("access bridge SDK settings bytes changed")
    toolchain = links.get("toolchainEvidence", {})
    if bindings.get("compiler") != toolchain.get("compiler"):
        raise ValueError("access bridge compiler receipt differs from immutable link archive")
    if bindings.get("sourcekitLsp") != toolchain.get("sourcekitLsp") or bindings.get("sourcekitd") != toolchain.get("sourcekitd"):
        raise ValueError("access bridge SourceKit binaries differ from immutable link archive")
    if bindings.get("xcodebuildVersion") != toolchain.get("xcodebuildVersion"):
        raise ValueError("access bridge Xcode version differs from immutable link archive")
    _validate_live_tool_bindings(bindings)

    interface_records = {item["module"]: item for item in v7["sourceKitAuthority"]["interfaces"]}
    module_records = bridge.get("modules", {})
    raw_entities: dict[str, list[dict[str, Any]]] = {}
    interface_lines: dict[str, list[str]] = {}
    for module in ("SwiftUI", "SwiftUICore"):
        v7_interface = interface_records[module]
        module_binding = module_records.get(module, {})
        for path_key, hash_key in (("interfacePath", "interfaceSha256"),
                                   ("requestPath", "requestSha256"),
                                   ("rawOutputPath", "rawOutputSha256")):
            path = Path(module_binding.get(path_key, ""))
            if path_key != "interfacePath":
                path = root / path
            if artifacts.file_hash(path) != module_binding.get(hash_key):
                raise ValueError(f"access bridge {module} {path_key} bytes changed")
        if module_binding.get("interfacePath") != v7_interface["path"] or module_binding.get("interfaceSha256") != v7_interface["sha256"]:
            raise ValueError(f"access bridge {module} interface differs from v7 source receipt")
        if module_binding.get("rawOutputPath") != v7_interface["indexOutput"] or module_binding.get("rawOutputSha256") != v7_interface["indexOutputSha256"]:
            raise ValueError(f"access bridge {module} raw SourceKit output differs from v7 receipt")
        if module_binding.get("requestPath") != v7_interface["indexRequest"] or module_binding.get("requestSha256") != v7_interface["indexRequestSha256"]:
            raise ValueError(f"access bridge {module} request differs from v7 receipt")
        identity = v7_interface["requestIdentity"]
        if module_binding.get("requestIdentity") != identity:
            raise ValueError(f"access bridge {module} request identity differs from v7")
        audit_v7._validate_request_identity(root / module_binding["requestPath"],
            interface=v7_interface["path"], sdk=pinned_sdk, target=bindings["target"], module=module)
        interface_lines[module] = Path(v7_interface["path"]).read_text(encoding="utf-8").splitlines()
        raw_entities[module] = audit_v7._index_entities(root / module_binding["rawOutputPath"])

    v7_by_identity: dict[tuple[Any, ...], list[dict[str, Any]]] = {}
    for declaration in v7["declarations"]:
        module = declaration.get("module")
        interface = next((item["file"] for item in v7["interfaces"] if item["module"] == module), None)
        key = (module, interface, declaration.get("line"), declaration.get("name"),
               tuple(declaration.get("context", [])), declaration.get("signature"),
               next((item["sha256"] for item in v7["interfaces"] if item["module"] == module), None))
        v7_by_identity.setdefault(key, []).append(declaration)
    link_rows = {row.get("auditRowKey"): row for row in links.get("rows", [])}
    bridge_rows = bridge.get("rows", [])
    if len(bridge_rows) != 51:
        raise ValueError("access bridge row count differs from reviewed receipt")
    usr_seen: set[str] = set()
    promotions: list[dict[str, Any]] = []
    for candidate in bridge_rows:
        module = candidate.get("module")
        interface = next((item["file"] for item in v7["interfaces"] if item["module"] == module), None)
        interface_hash = next((item["sha256"] for item in v7["interfaces"] if item["module"] == module), None)
        link = link_rows.get(candidate.get("auditRowKey"))
        if not link:
            raise ValueError("access bridge auditRowKey does not bind immutable source-link row")
        if (link.get("module"), link.get("interface"), link.get("line"), link.get("name"),
                tuple(link.get("context", [])), link.get("sourceHash")) != (
                    module, interface, candidate.get("line"), candidate.get("name"),
                    tuple(candidate.get("context", [])), candidate.get("sourceHash")):
            raise ValueError("access bridge identity differs from immutable source-link row")
        identity = (module, interface, link.get("line"), link.get("name"),
                    tuple(link.get("context", [])), link.get("signature"), link.get("sourceHash"))
        matches = v7_by_identity.get(identity, [])
        if len(matches) != 1:
            raise ValueError("access bridge does not bind exactly one v7 declaration/signature row")
        declaration = matches[0]
        if interface_hash != candidate.get("sourceHash") or declaration.get("kind") != "case":
            raise ValueError("access bridge source hash or declaration kind does not match v7")
        old_evidence = declaration.get("sourceKitEvidence", {})
        if old_evidence.get("reason") != "interface-signature-does-not-prove-public-or-open-access":
            raise ValueError("access bridge row is not held by v7's expected access reason")
        if link.get("linkHoldReason") != "expected-access-unavailable" or link.get("linkEligibility") is not False:
            raise ValueError("access bridge source row was not held at expected access gate")
        entity = _raw_access_entity(candidate, raw_entities[module])
        _validate_access_entity_claim(candidate, entity)
        _validate_access_scope(candidate, Path(interface_records[module]["path"]))
        if candidate["usr"] in usr_seen:
            raise ValueError("access bridge repeats a compiler USR across case rows")
        usr_seen.add(candidate["usr"])
        promotions.append({"declaration": declaration, "bridgeRow": candidate, "entity": entity})
    if len(usr_seen) != 51:
        raise ValueError("access bridge does not have 51 distinct raw compiler USRs")
    return promotions


def build_audit_v8(v7_path: Path, *, root: Path, access_bridge_path: Path | None = None) -> dict[str, Any]:
    """Create v8 candidate; optional access bridge is rechecked against raw inputs.

    Without a reviewed bridge, every v7 row remains unchanged. With one, only
    exact public/open enum cases pass local raw identity and scope checks.
    """
    v7_path = Path(v7_path)
    root = Path(root)
    v7 = _load_pinned_v7(v7_path)
    declarations = copy.deepcopy(v7["declarations"])
    if declarations != v7["declarations"]:
        raise AssertionError("v8 declaration copy unexpectedly differs from v7")
    promotions = []
    if access_bridge_path is not None:
        promotions = _validate_access_bridge(Path(access_bridge_path), v7, root=root)
        for entry in promotions:
            original = entry["declaration"]
            expected = (original.get("module"), original.get("interface"), original.get("line"),
                        original.get("name"), tuple(original.get("context", [])), original.get("signature"),
                        original.get("sourceKitEvidence", {}).get("interfaceSha256"))
            copied = [row for row in declarations if (
                row.get("module"), row.get("interface"), row.get("line"), row.get("name"),
                tuple(row.get("context", [])), row.get("signature"),
                row.get("sourceKitEvidence", {}).get("interfaceSha256")) == expected]
            if len(copied) != 1:
                raise ValueError("validated bridge promotion does not map uniquely into v8 declaration copy")
            entry["declaration"] = copied[0]
        for entry in promotions:
            declaration = entry["declaration"]
            bridge_row = entry["bridgeRow"]
            usr = str(bridge_row["usr"])
            declaration["symbol"] = {"usr": usr, "source": "SourceKit indexsource + verified enum-case access bridge"}
            declaration["sourceKitEvidence"].pop("reason", None)
            declaration["sourceKitEvidence"]["accessBridge"] = {
                "path": str(Path(access_bridge_path).relative_to(root)),
                "sha256": ACCESS_BRIDGE_SHA256,
                "validatorSha256": ACCESS_VALIDATOR_SHA256,
                "sourceLinkEvidenceSha256": SOURCEKIT_LINK_SHA256,
                "rawEntityKind": bridge_row["rawEntityKind"],
                "effectiveAccess": bridge_row["effectiveAccess"],
                "lexicalScopes": bridge_row["lexicalScopes"],
            }
            declaration["sourceKitEvidence"]["compilerUsr"] = usr
            # Catalogue presence is checked below from the v7-pinned catalogue.
    catalogue_path = root / v7["sourceKitAuthority"]["pinnedInputs"]["symbolCatalogue"]
    if artifacts.file_hash(catalogue_path) != v7["sourceKitAuthority"]["pinnedInputs"]["symbolCatalogueHash"]:
        raise ValueError("v7-pinned symbol catalogue bytes changed")
    catalogue = json.loads(catalogue_path.read_text(encoding="utf-8"))
    graph_by_usr: dict[str, list[dict[str, Any]]] = {}
    for symbol in catalogue.get("symbols", []):
        if symbol.get("usr") != symbol.get("precise"):
            raise ValueError("pinned catalogue has inconsistent USR/precise fields")
        graph_by_usr.setdefault(str(symbol["usr"]), []).append(symbol)
    for entry in promotions:
        declaration, bridge_row = entry["declaration"], entry["bridgeRow"]
        graph_matches = graph_by_usr.get(str(bridge_row["usr"]), [])
        declaration["sourceKitEvidence"]["symbolGraphMatches"] = graph_matches
        declaration["classification"] = (
            "matched-sourcekit-usr-in-symbolgraph" if graph_matches
            else "matched-sourcekit-usr-absent-from-symbolgraph")

    counts = Counter(row["classification"] for row in declarations)
    remaining = sum(counts[name] for name in RESIDUAL_CLASSIFICATIONS)
    held_reasons = Counter(row.get("sourceKitEvidence", {}).get("reason")
                           for row in declarations
                           if row.get("classification") in RESIDUAL_CLASSIFICATIONS
                           and row.get("sourceKitEvidence", {}).get("reason"))
    promoted_present = sum(bool(graph_by_usr.get(str(entry["bridgeRow"]["usr"]))) for entry in promotions)
    promoted_absent = len(promotions) - promoted_present
    access_path = Path(access_bridge_path) if access_bridge_path is not None else None
    pending_evidence = [
        {"kind": "compiler-demangle-structural-owner-evidence", "path": None,
         "expectedRows": "strict subset only", "state": "awaiting reviewed receipt path",
         "application": "pending compilerbridge_review clearance and local structural validation"},
    ]
    if access_path is None:
        pending_evidence.insert(0, {
            "kind": "compiler-enum-case-effective-access-evidence",
            "path": "factory/catalogue/access-inheritance-spike/derived-access-bridge.json",
            "expectedRows": 51,
            "state": "awaiting independent Oracle clearance",
            "application": "pending-independent-exact-row-and-raw-entity validation",
        })
    else:
        pending_evidence.insert(0, {
            "kind": "compiler-enum-case-effective-access-evidence",
            "path": str(access_path.relative_to(root)), "expectedRows": 51,
            "appliedRows": len(promotions), "sha256": ACCESS_BRIDGE_SHA256,
            "validatorSha256": ACCESS_VALIDATOR_SHA256,
            "state": "candidate-applied-awaiting-independent-consumer-review",
        })
    payload: dict[str, Any] = {
        "kind": "swift-interface-audit",
        "version": 8,
        "status": ("incomplete-v8-access-bridge-consumer-review-pending" if access_path
                   else "incomplete-awaiting-independent-bridge-validation"),
        "method": (
            "V8 carries committed v7 classifications and may add exact public/open enum cases only after "
            "local raw SourceKit identity, interface context, effective access, lexical owner source, "
            "extension qualification, and immutable receipt checks. Structural owner bridge remains pending."
        ),
        "parentAudit": {
            "path": str(v7_path.relative_to(root)),
            "fileSha256": V7_FILE_SHA256,
            "auditHash": V7_AUDIT_HASH,
            "sourceKitLinkEvidenceSha256": SOURCEKIT_LINK_SHA256,
        },
        "pendingEvidence": [
            *pending_evidence,
        ],
        "summary": {
            "inheritedV7ExactSourceKitUsrLinks": v7["summary"]["exactSourceKitUsrLinks"],
            "inheritedV7HeldSourceKitRows": v7["summary"]["heldSourceKitRows"],
            "newlyPromotedRows": len(promotions),
            "sourceKitUsrPresentInSymbolGraph": v7["summary"]["sourceKitUsrPresentInSymbolGraph"] + promoted_present,
            "sourceKitUsrAbsentFromSymbolGraph": v7["summary"]["sourceKitUsrAbsentFromSymbolGraph"] + promoted_absent,
            "exactSourceKitUsrLinks": v7["summary"]["exactSourceKitUsrLinks"] + len(promotions),
            "heldSourceKitRows": v7["summary"]["heldSourceKitRows"] - len(promotions),
            "heldSourceKitReasons": dict(sorted(held_reasons.items())),
            "remainingActiveUnmappedAmbiguousOrUnexplained": remaining,
            "byClassification": dict(sorted(counts.items())),
        },
        "interfaces": v7["interfaces"],
        "symbolGraphs": v7["symbolGraphs"],
        "symbolgraphTarget": v7["symbolgraphTarget"],
        "declarations": declarations,
        "sourceKitBridgeEvidence": ({
            "kind": "compiler-enum-case-access-bridge",
            "path": str(access_path.relative_to(root)),
            "sha256": ACCESS_BRIDGE_SHA256,
            "validatorSha256": ACCESS_VALIDATOR_SHA256,
            "testSha256": ACCESS_TEST_SHA256,
            "schemaSha256": ACCESS_SCHEMA_SHA256,
            "manifestSha256": ACCESS_MANIFEST_SHA256,
            "promotedRows": len(promotions),
            "status": "awaiting-independent-consumer-review",
        } if access_path else None),
        "provenance": artifacts.provenance(
            V7_AUDIT_HASH,
            ([{"path": str(v7_path.relative_to(root)), "hash": V7_FILE_SHA256}]
             + ([{"path": str(access_path.relative_to(root)), "hash": ACCESS_BRIDGE_SHA256},
                 {"path": "factory/catalogue/access-inheritance-spike/exact_access_bridge.py", "hash": ACCESS_VALIDATOR_SHA256},
                 {"path": "factory/catalogue/access-inheritance-spike/test_exact_access_bridge.py", "hash": ACCESS_TEST_SHA256},
                 {"path": "factory/catalogue/access-inheritance-spike/BRIDGE-SCHEMA.md", "hash": ACCESS_SCHEMA_SHA256},
                 {"path": "factory/catalogue/access-inheritance-spike/bridge-manifest.txt", "hash": ACCESS_MANIFEST_SHA256}]
                if access_path else [])),
            producer="sr1-factory.catalogue.audit-v8-candidate",
        ),
    }
    payload["auditHash"] = artifacts.canonical_hash(payload)
    return payload


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    value = build_audit_v8(root / "factory/catalogue/evidence/interface-audit-v7.json", root=root,
                           access_bridge_path=root / "factory/catalogue/access-inheritance-spike/derived-access-bridge.json")
    artifacts.write_artifact(root / "factory/catalogue/evidence/interface-audit-v8-candidate.json", value)


if __name__ == "__main__":
    main()
