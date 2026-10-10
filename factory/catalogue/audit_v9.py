"""Additive v9 candidate consuming independently cleared structural compiler links."""
from __future__ import annotations

import copy
import importlib.util
import json
from functools import lru_cache
from pathlib import Path
from typing import Any

from factory.core import artifacts
from . import audit_v7, audit_v8

V8_AUDIT_HASH = "sha256:f4bcda03046b27c7fb300bbc435f253ca36c4edb9c8b865065b33bd6e45ddc3c"
V8_FILE_SHA256 = "sha256:11860d0c3f5243860cf388345b8e38c1f5d2358ac5f92e3332df7aaa95bfbd73"
V8_SOURCE_SHA256 = "sha256:b34a047ed37ef207ed6c0515b6b7570f2ae6e13ae6c8b44a655d9b9dd59aed9a"
V8_TEST_SHA256 = "sha256:76f2f1cb2629361ddccb1bc434dd49cebd4bdc6cca073bf513417fa0c2b93308"
CONTEXT_EVIDENCE_SHA256 = "sha256:1e8178c8c71ebf64eee3dcdd25a70fb494141fe0b93980bb8d7b1895eb6ecdf5"
CONTEXT_SOURCE_SHA256 = "sha256:96ec7a13fba4c215cb5eef8d1106bb874fb802b8bc0eecc323322758bf68d387"
CONTEXT_TEST_SHA256 = "sha256:6d2726017c246b478af60f8035f5c754c2b8a93d98e372418dc1de0f91bda3e5"
CONTEXT_EXPANDED_SHA256 = "sha256:4dd7943d1b3025c806ccfaeeb1d7a1d41c15e6f7caae5493fc59e9da4dd1287a"
CONTEXT_INVESTIGATOR_SHA256 = "sha256:4747107ff13d77d808cafcd9e259480735486d437a90376107e652cacfc319de"
CONTEXT_AUDIT_V6_SHA256 = "sha256:27ea2a1b479361bcecaa61fcd2852e26b799afd56f02ca4a444357bc1c589dfc"
CONTEXT_REVIEW_SHA256 = "sha256:e0c5bdac10ff938cef6209819ed0cf9f9743169bbeb54d79a2f4c4f7c38b9f80"
CONTEXT_FINDINGS_SHA256 = "sha256:d186dbbd8589ca6ed3643438dbf3f36b5f02d7bb883b254e79690c46f1cc0ff9"
LINK_EVIDENCE_SHA256 = audit_v8.SOURCEKIT_LINK_SHA256


def _load_v8(path: Path) -> dict[str, Any]:
    root = Path(__file__).resolve().parents[2]
    if artifacts.file_hash(root / "factory/catalogue/audit_v8.py") != V8_SOURCE_SHA256:
        raise ValueError("v8 candidate source differs from reviewed immutable implementation")
    if artifacts.file_hash(root / "factory/catalogue/test_audit_v8.py") != V8_TEST_SHA256:
        raise ValueError("v8 candidate tests differ from reviewed immutable tests")
    value = json.loads(path.read_text(encoding="utf-8"))
    if artifacts.file_hash(path) != V8_FILE_SHA256:
        raise ValueError("v8 candidate bytes differ from reviewed immutable snapshot")
    body = dict(value)
    declared_hash = body.pop("auditHash", None)
    if declared_hash != V8_AUDIT_HASH or artifacts.canonical_hash(body) != declared_hash:
        raise ValueError("v8 candidate canonical hash differs from reviewed snapshot")
    return value


@lru_cache(maxsize=1)
def _bridge_module():
    source = Path(__file__).resolve().parent / "residual-investigation/bridge_contexts.py"
    if artifacts.file_hash(source) != CONTEXT_SOURCE_SHA256:
        raise ValueError("context bridge source differs from independently cleared implementation")
    spec = importlib.util.spec_from_file_location("_sr1_v9_context_bridge", source)
    if spec is None or spec.loader is None:
        raise ValueError("cannot load pinned context bridge parser")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _require_file_hash(path: Path, expected: str, label: str) -> None:
    if not path.is_file() or artifacts.file_hash(path) != expected:
        raise ValueError(f"{label} bytes differ from exact receipt")


def _validate_input_join(input_record: dict[str, Any], *, expected_path: str, expected_sha: str,
                         root: Path, label: str) -> Path:
    path = Path(input_record["path"])
    live_path = path if path.is_absolute() else root / path
    if input_record.get("path") != expected_path or input_record.get("sha256") != expected_sha:
        raise ValueError(f"{label} path/hash do not join to pinned v7 receipt")
    _require_file_hash(live_path, expected_sha, label)
    return live_path


def _parse_context_trees(bridge: Any, expanded_path: Path, expected_sha: str,
                         expected_usrs: set[str]) -> dict[str, dict[str, Any]]:
    _require_file_hash(expanded_path, expected_sha, "expanded demangle output")
    trees = bridge.parse_sections(expanded_path.read_text(encoding="utf-8"))
    if set(trees) != expected_usrs:
        raise ValueError("demangle output USR set differs from exact source rows")
    return trees


def _evaluate_context_claim(link: dict[str, Any], claim: dict[str, Any],
                            entities: list[dict[str, Any]], tree: dict[str, Any],
                            scopes: list[dict[str, Any]], bridge: Any, investigator: Any) -> dict[str, Any]:
    """Production semantic gate, separately callable for non-vacuous fault tests."""
    if len(entities) != 1:
        raise ValueError(f"context raw compiler entity cardinality is {len(entities)}")
    entity = entities[0]
    raw_claim = claim.get("raw", {})
    fields = ("kind", "name", "usr", "line", "column", "effective_access", "is_implicit", "sourcekitContext")
    if any(raw_claim.get(field) != entity.get(field) for field in fields):
        raise ValueError("context raw SourceKit claim differs from exact compiler response")
    if entity.get("is_implicit") is True or entity.get("is_implicit") == 1:
        raise ValueError("context declaration is compiler implicit")
    owner = bridge.structural_owner(tree, str(claim["name"]))
    if owner != claim.get("compilerOwner"):
        raise ValueError("context structural owner differs from exact parsed compiler tree")
    expected_module = bridge.expected_nominal_module(link, scopes)
    owner_match = bridge.owner_matches_row(link, owner, expected_module)
    module_provenance = claim.get("bridge", {}).get("moduleProvenance", {})
    raw_identity = bridge.raw_entity_matches(link, [entity], investigator)
    kind_match = investigator.kind_matches(str(link["kind"]), str(entity.get("kind", "")))
    access_match = investigator.access_matches(link, entity)
    context_match = investigator.context_matches(link, entity)
    access_level = str(entity.get("effective_access", "")).rsplit(".", 1)[-1]
    visible_access = access_level in {"public", "open"}
    derived_eligible = bool(raw_identity and owner_match and not context_match and kind_match and access_match and visible_access)
    bridge_claim = claim.get("bridge", {})
    if (bridge_claim.get("structuralOwnerExact") is not owner_match
            or module_provenance.get("expectedNominalModule") != expected_module
            or module_provenance.get("nominalModuleExact") is not (owner.get("nominalModule") == expected_module)
            or module_provenance.get("extensionModuleExact") is not (
                owner.get("extensionModule") is None or owner.get("extensionModule") == link["module"])
            or bridge_claim.get("kindMatch") is not kind_match
            or bridge_claim.get("accessMatch") is not access_match
            or bridge_claim.get("strictContextMatch") is not context_match
            or bridge_claim.get("proposedBridgeEligible") is not derived_eligible):
        raise ValueError("context eligibility receipt differs from independent identity/access/context gates")
    if derived_eligible and (owner.get("genericReferencePathCount") != 0 or owner.get("functionLocalScope") is not False):
        raise ValueError("context promotion has generic-reference or function-local owner")
    return {"eligible": derived_eligible, "owner": owner, "entity": entity,
            "kindMatch": kind_match, "accessMatch": access_match, "contextMatch": context_match,
            "accessLevel": access_level}


def _validate_context_bridge(path: Path, v8: dict[str, Any], *, root: Path) -> list[dict[str, Any]]:
    if artifacts.file_hash(path) != CONTEXT_EVIDENCE_SHA256:
        raise ValueError("context bridge evidence differs from independently cleared bytes")
    evidence = json.loads(path.read_text(encoding="utf-8"))
    if evidence.get("summary", {}).get("proposedBridgeEligible") != 173 or evidence.get("summary", {}).get("finalLinkContextHolds") != 206:
        raise ValueError("context bridge summary differs from reviewed 173/206 receipt")
    pinned_files = {
        "factory/catalogue/residual-investigation/bridge_contexts.py": CONTEXT_SOURCE_SHA256,
        "factory/catalogue/residual-investigation/test_bridge_contexts.py": CONTEXT_TEST_SHA256,
        "factory/catalogue/residual-investigation/swift-demangle-expand-v1.txt": CONTEXT_EXPANDED_SHA256,
        "factory/catalogue/residual-investigation/investigate.py": CONTEXT_INVESTIGATOR_SHA256,
        "factory/catalogue/residual-investigation/BRIDGE.md": CONTEXT_REVIEW_SHA256,
        "factory/catalogue/residual-investigation/BRIDGE-REVIEW-FINDINGS.md": CONTEXT_FINDINGS_SHA256,
        "factory/catalogue/evidence/interface-audit-v6.json": CONTEXT_AUDIT_V6_SHA256,
        "factory/catalogue/compiler-cursor-spike/link-evidence.json": LINK_EVIDENCE_SHA256,
    }
    for rel, expected in pinned_files.items():
        if artifacts.file_hash(root / rel) != expected:
            raise ValueError(f"context bridge input changed: {rel}")

    bridge = _bridge_module()
    inputs = evidence["inputs"]
    expanded_path = root / "factory/catalogue/residual-investigation/swift-demangle-expand-v1.txt"
    if artifacts.file_hash(expanded_path) != CONTEXT_EXPANDED_SHA256:
        raise ValueError("context bridge expanded demangle bytes changed")
    demangler = Path(inputs["swiftDemangle"]["path"])
    _require_file_hash(demangler, inputs["swiftDemangle"]["sha256"], "live swift-demangle binary")

    link_path = root / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
    links = json.loads(link_path.read_text(encoding="utf-8"))
    toolchain = links.get("toolchainEvidence", {})
    audit_v8._validate_live_tool_bindings({
        "compiler": toolchain.get("compiler", {}),
        "sourcekitLsp": toolchain.get("sourcekitLsp", {}),
        "sourcekitd": toolchain.get("sourcekitd", {}),
    })
    audit6 = json.loads((root / "factory/catalogue/evidence/interface-audit-v6.json").read_text(encoding="utf-8"))
    audit6_by_key: dict[tuple[Any, ...], list[dict[str, Any]]] = {}
    for row in audit6["declarations"]:
        audit6_by_key.setdefault((row.get("module"), row.get("line"), row.get("name")), []).append(row)
    v7_ifaces = {item["module"]: item for item in v8["interfaces"]}
    v7 = _load_v8_parent(root)
    v7_interface_records = {item["module"]: item for item in v7["sourceKitAuthority"]["interfaces"]}
    context_holds = [row for row in links["rows"] if row.get("linkHoldReason") == "enclosing-context-mismatch"]
    if len(context_holds) != 206:
        raise ValueError("context bridge does not bind exact 206 source-link holds")
    for module, record in v7_interface_records.items():
        for input_group in ("interfaces", "rawIndexOutputs", "rawIndexRequests"):
            item = inputs[input_group][module]
            expected_path = (record["path"] if input_group == "interfaces" else
                             record["indexOutput"] if input_group == "rawIndexOutputs" else
                             record["indexRequest"])
            expected_sha = (record["sha256"] if input_group == "interfaces" else
                            record["indexOutputSha256"] if input_group == "rawIndexOutputs" else
                            record["indexRequestSha256"])
            _validate_input_join(item, expected_path=expected_path, expected_sha=expected_sha,
                                 root=root, label=f"context {module} {input_group}")
        interface_input = inputs["interfaces"][module]
        output_input = inputs["rawIndexOutputs"][module]
        request_input = inputs["rawIndexRequests"][module]
        if (interface_input["path"] != record["path"] or interface_input["sha256"] != record["sha256"]
                or output_input["path"] != record["indexOutput"] or output_input["sha256"] != record["indexOutputSha256"]
                or request_input["path"] != record["indexRequest"] or request_input["sha256"] != record["indexRequestSha256"]):
            raise ValueError(f"context bridge {module} source/index receipts differ from v7 authority")
        if any(row.get("module") == module and row.get("sourceHash") != interface_input["sha256"]
               for row in context_holds):
            raise ValueError(f"context bridge {module} rows do not bind exact pinned interface hash")
        audit_v7._validate_request_identity(
            root / record["indexRequest"], interface=record["path"],
            sdk=v7["sourceKitAuthority"]["pinnedInputs"]["sdk"],
            target=v7["symbolgraphTarget"], module=module)
    _ = v7_ifaces

    if len(context_holds) != 206 or len(evidence.get("rows", [])) != 206:
        raise ValueError("context bridge does not cover exact 206 immutable context holds")
    if len({(row.get("module"), row.get("line"), row.get("name")) for row in context_holds}) != 206:
        raise ValueError("immutable context source rows contain duplicate identities")
    if len({(row.get("module"), row.get("line"), row.get("name")) for row in evidence["rows"]}) != 206:
        raise ValueError("context evidence rows contain duplicate identities")
    raw_by_module = {module: audit_v7._index_entities(root / record["indexOutput"])
                     for module, record in v7_interface_records.items()}
    expected_tree_usrs = {"$s" + str(row["raw"]["usr"])[2:] for row in evidence["rows"]}
    if len(expected_tree_usrs) != 206:
        raise ValueError("demangle output USR set differs from exact 206 context evidence rows")
    trees = _parse_context_trees(bridge, expanded_path, CONTEXT_EXPANDED_SHA256, expected_tree_usrs)
    link_by_key = {(row["module"], row["line"], row["name"]): row for row in context_holds}
    accepted: list[dict[str, Any]] = []
    accepted_usrs: set[str] = set()
    investigator = bridge.load_investigator()
    for claim in evidence["rows"]:
        key = (claim.get("module"), claim.get("line"), claim.get("name"))
        link = link_by_key.get(key)
        if link is None:
            raise ValueError("context evidence row is not an immutable held source-link row")
        if claim.get("key") != [link["module"], link["interface"], link["line"], link["name"]] or claim.get("interfaceContext") != link.get("context") or claim.get("interfaceKind") != link.get("kind"):
            raise ValueError("context evidence source declaration identity differs from immutable link")
        audited = audit6_by_key.get(key, [])
        if len(audited) != 1:
            raise ValueError("context evidence does not resolve to unique v6 interface row")
        scopes = audited[0].get("v6Evidence", {}).get("enclosingScopes", [])
        if not scopes or claim.get("interfaceEnclosingScopes") != scopes:
            raise ValueError("context evidence lexical scopes differ from pinned v6 interface audit")
        candidates = [entity for entity in raw_by_module[key[0]] if entity.get("line") == key[1]
                      and audit_v7._name_matches(str(entity.get("name", "")), key[2])]
        if len(candidates) != 1:
            raise ValueError("context raw compiler entity cardinality is not exactly one")
        entity = candidates[0]
        tree = trees["$s" + str(entity["usr"])[2:]]
        evaluated = _evaluate_context_claim(link, claim, [entity], tree, scopes, bridge, investigator)
        if not evaluated["eligible"]:
            continue
        owner = evaluated["owner"]
        module_provenance = claim["bridge"]["moduleProvenance"]
        if (module_provenance.get("nominalModuleExact") is not True
                or module_provenance.get("extensionModuleExact") is not True
                or owner.get("genericReferencePathCount") != 0
                or owner.get("functionLocalScope") is not False):
            raise ValueError("context promotion fails exact module/generic/function-scope gate")
        if entity["usr"] in accepted_usrs:
            raise ValueError("context bridge repeats exact compiler USR")
        accepted_usrs.add(entity["usr"])
        declarations = [row for row in v7["declarations"] if (
            row.get("module"), row.get("interface"), row.get("line"), row.get("name"),
            tuple(row.get("context", [])), row.get("signature"),
            row.get("sourceKitEvidence", {}).get("interfaceSha256")) == (
            link.get("module"), link.get("interface"), link.get("line"), link.get("name"),
            tuple(link.get("context", [])), link.get("signature"), link.get("sourceHash"))]
        if len(declarations) != 1 or declarations[0].get("classification") not in audit_v8.RESIDUAL_CLASSIFICATIONS:
            raise ValueError("context promotion does not map to one unresolved v7 declaration")
        accepted.append({"declaration": declarations[0], "bridgeRow": claim, "entity": entity, "owner": owner})
    if len(accepted) != 173 or len(accepted_usrs) != 173:
        raise ValueError(f"context bridge exact accepted count differs: {len(accepted)}")
    return accepted


def _load_v8_parent(root: Path) -> dict[str, Any]:
    """Load exact committed v7 authority needed to validate bridge ancestry."""
    v7_path = root / "factory/catalogue/evidence/interface-audit-v7.json"
    return audit_v8._load_pinned_v7(v7_path)


def build_audit_v9(v8_path: Path, *, root: Path, context_bridge_path: Path) -> dict[str, Any]:
    root = Path(root)
    v8 = _load_v8(Path(v8_path))
    promoted = _validate_context_bridge(Path(context_bridge_path), v8, root=root)
    declarations = copy.deepcopy(v8["declarations"])
    v7_authority = _load_v8_parent(root)
    catalogue_path = root / v7_authority["sourceKitAuthority"]["pinnedInputs"]["symbolCatalogue"]
    catalogue_hash = v7_authority["sourceKitAuthority"]["pinnedInputs"]["symbolCatalogueHash"]
    if artifacts.file_hash(catalogue_path) != catalogue_hash:
        raise ValueError("v7-pinned symbol catalogue bytes changed")
    catalogue = json.loads(catalogue_path.read_text(encoding="utf-8"))
    graph_by_usr: dict[str, list[dict[str, Any]]] = {}
    for symbol in catalogue.get("symbols", []):
        if symbol.get("usr") != symbol.get("precise"):
            raise ValueError("v7-pinned catalogue has inconsistent USR/precise fields")
        graph_by_usr.setdefault(str(symbol["usr"]), []).append(symbol)
    for item in promoted:
        source = item["declaration"]
        declaration = next(row for row in declarations if row is source or (
            row.get("module"), row.get("interface"), row.get("line"), row.get("name"),
            tuple(row.get("context", [])), row.get("signature")) == (
            source.get("module"), source.get("interface"), source.get("line"), source.get("name"),
            tuple(source.get("context", [])), source.get("signature")))
        usr = str(item["entity"]["usr"])
        declaration["symbol"] = {"usr": usr, "source": "SourceKit index + exact expanded compiler owner tree"}
        declaration["sourceKitEvidence"].pop("reason", None)
        declaration["sourceKitEvidence"]["compilerUsr"] = usr
        declaration["sourceKitEvidence"]["contextBridge"] = {
            "path": str(Path(context_bridge_path).relative_to(root)),
            "sha256": CONTEXT_EVIDENCE_SHA256,
            "sourceSha256": CONTEXT_SOURCE_SHA256,
            "expandedOutputSha256": CONTEXT_EXPANDED_SHA256,
            "ownerModule": item["owner"].get("ownerModule"),
            "nominalModule": item["owner"].get("nominalModule"),
            "extensionModule": item["owner"].get("extensionModule"),
            "ownerNames": item["owner"].get("ownerNames"),
        }
        declaration["sourceKitEvidence"].pop("reason", None)
        graph_matches = graph_by_usr.get(usr, [])
        declaration["sourceKitEvidence"]["symbolGraphMatches"] = graph_matches
        declaration["classification"] = (
            "matched-sourcekit-usr-in-symbolgraph" if graph_matches
            else "matched-sourcekit-usr-absent-from-symbolgraph")

    from collections import Counter
    counts = Counter(row["classification"] for row in declarations)
    remaining = sum(counts[name] for name in audit_v8.RESIDUAL_CLASSIFICATIONS)
    held_reasons = Counter(row.get("sourceKitEvidence", {}).get("reason") for row in declarations
                            if row.get("classification") in audit_v8.RESIDUAL_CLASSIFICATIONS
                            and row.get("sourceKitEvidence", {}).get("reason"))
    present = sum(bool(graph_by_usr.get(str(item["entity"]["usr"]))) for item in promoted)
    absent = len(promoted) - present
    payload = copy.deepcopy(v8)
    payload.pop("auditHash", None)
    payload.update({
        "version": 9,
        "status": "incomplete-v9-context-bridge-consumer-validated",
        "method": (v8["method"] + " V9 independently validates exact SourceKit rows, expanded demangle trees, "
                   "lexical scopes, owner path, and module provenance before applying 173 compiler-owner links; "
                   "33 nominal-module mismatches remain held."),
        "parentAudit": {"path": str(Path(v8_path).relative_to(root)), "fileSha256": V8_FILE_SHA256,
                        "auditHash": V8_AUDIT_HASH},
        "declarations": declarations,
        "sourceKitBridgeEvidence": {
            **(v8.get("sourceKitBridgeEvidence") or {}),
            "status": "consumer-validated-in-v9",
        },
        "summary": {
            **v8["summary"],
            "newlyPromotedRows": v8["summary"]["newlyPromotedRows"] + len(promoted),
            "exactSourceKitUsrLinks": v8["summary"]["exactSourceKitUsrLinks"] + len(promoted),
            "heldSourceKitRows": v8["summary"]["heldSourceKitRows"] - len(promoted),
            "sourceKitUsrPresentInSymbolGraph": v8["summary"]["sourceKitUsrPresentInSymbolGraph"] + present,
            "sourceKitUsrAbsentFromSymbolGraph": v8["summary"]["sourceKitUsrAbsentFromSymbolGraph"] + absent,
            "heldSourceKitReasons": dict(sorted(held_reasons.items())),
            "remainingActiveUnmappedAmbiguousOrUnexplained": remaining,
            "byClassification": dict(sorted(counts.items())),
        },
        "contextBridgeEvidence": {"path": str(Path(context_bridge_path).relative_to(root)),
                                  "sha256": CONTEXT_EVIDENCE_SHA256,
                                  "sourceSha256": CONTEXT_SOURCE_SHA256,
                                  "expandedOutputSha256": CONTEXT_EXPANDED_SHA256,
                                  "promotedRows": len(promoted), "heldModuleAliasRows": 33,
                                  "state": "consumer-validated"},
        "pendingEvidence": [
            {"kind": "unsupported-compiler-nominal-module-alias", "path": str(Path(context_bridge_path).relative_to(root)),
             "expectedRows": 33, "state": "held-no-alias-inference"},
            {"kind": "remaining-active-unmapped-ambiguous-or-unexplained", "path": None,
             "expectedRows": remaining, "state": "unresolved"},
        ],
    })
    payload["provenance"] = artifacts.provenance(V8_AUDIT_HASH,
        [{"path": str(Path(v8_path).relative_to(root)), "hash": V8_FILE_SHA256},
         {"path": str(Path(context_bridge_path).relative_to(root)), "hash": CONTEXT_EVIDENCE_SHA256},
         {"path": "factory/catalogue/audit_v9.py", "hash": artifacts.file_hash(Path(__file__))},
         {"path": "factory/catalogue/residual-investigation/bridge_contexts.py", "hash": CONTEXT_SOURCE_SHA256},
         {"path": "factory/catalogue/residual-investigation/test_bridge_contexts.py", "hash": CONTEXT_TEST_SHA256},
         {"path": "factory/catalogue/residual-investigation/swift-demangle-expand-v1.txt", "hash": CONTEXT_EXPANDED_SHA256}],
        producer="sr1-factory.catalogue.audit-v9-candidate")
    payload["auditHash"] = artifacts.canonical_hash(payload)
    return payload


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    value = build_audit_v9(
        root / "factory/catalogue/evidence/interface-audit-v8-candidate.json", root=root,
        context_bridge_path=root / "factory/catalogue/residual-investigation/context-bridge-evidence.json")
    artifacts.write_artifact(root / "factory/catalogue/evidence/interface-audit-v9-candidate.json", value)


if __name__ == "__main__":
    main()
