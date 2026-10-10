"""Consumer-validated actor-edge addition, incremental from immutable v9."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import subprocess
from functools import lru_cache
from pathlib import Path
from typing import Any

from factory.core import artifacts
from . import audit_v7, audit_v8, audit_v9

V9_AUDIT_HASH = "sha256:9e3d2b8703bad1aaee415f60dbd281c24e7e59d02b15f9606106b4ebe3d9b66b"
V9_FILE_SHA256 = "sha256:c4d370ec044836ecb973e0f0969fe9b72e204534c75aaebfe1382da1d4bbf1d5"
V9_SOURCE_SHA256 = "sha256:bd5155235ddb74e90e703e784c1a3381cb5c2d0dfadb3d3de0da824e632cea05"
V9_TEST_SHA256 = "sha256:76b97f76f5d3a8138e39c86230f6ea157c5407b61778ce41a46677117de7f6fe"
LINK_SHA256 = audit_v8.SOURCEKIT_LINK_SHA256
EDGE_EVIDENCE_SHA256 = "sha256:d202d006825340cb8e4c7c0de93db268a4ee778ab65427268b3b21ec1bc8df90"
ACTOR_VALIDATOR_SHA256 = "sha256:f0f75cf4b7228067de0eb7e2862a117aed736b191e21e528b0b7adba559f60b4"
ACTOR_MODULE = "SwiftUICore"
ACTOR_LINE = 18132
ACTOR_NAME = "_ImpossibleActor"
MODULE_EVIDENCE_SHA256 = "sha256:122b1ca2c62342a27e6c5e15b2d371e62bf09d0ab586327f3304f510a670d560"
MODULE_VALIDATOR_SHA256 = "sha256:83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5"
MODULE_TEST_SHA256 = "sha256:fc4d196900f945778258778453dd2804a1a199f8d52ea81f3382c11c2f38431b"
MODULE_INVESTIGATOR_SHA256 = "sha256:9ec399ea6e40017b438712e07b99ad0c248051b1b53be8b851b486f0bddbc60f"
MODULE_TREES_SHA256 = "sha256:924a33607f00ede51328ef89559d18aa70d15ed4a45afef8ec9077972f154e10"


def _load_v9(path: Path, *, root: Path) -> dict[str, Any]:
    if artifacts.file_hash(root / "factory/catalogue/audit_v9.py") != V9_SOURCE_SHA256:
        raise ValueError("v9 source bytes differ from committed v9")
    if artifacts.file_hash(root / "factory/catalogue/test_audit_v9.py") != V9_TEST_SHA256:
        raise ValueError("v9 test bytes differ from committed v9")
    if artifacts.file_hash(path) != V9_FILE_SHA256:
        raise ValueError("v9 candidate bytes differ from committed snapshot")
    value = json.loads(path.read_text(encoding="utf-8"))
    body = dict(value)
    declared_hash = body.pop("auditHash", None)
    if declared_hash != V9_AUDIT_HASH or artifacts.canonical_hash(body) != declared_hash:
        raise ValueError("v9 canonical audit hash differs from committed snapshot")
    return value


@lru_cache(maxsize=1)
def _actor_validator():
    path = Path(__file__).resolve().parent / "compiler-edge-spike/actor_bridge_validator.py"
    if artifacts.file_hash(path) != ACTOR_VALIDATOR_SHA256:
        raise ValueError("actor bridge validator differs from reviewed bytes")
    spec = importlib.util.spec_from_file_location("_sr1_v10_actor_bridge", path)
    if spec is None or spec.loader is None:
        raise ValueError("cannot load pinned actor bridge validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _require_hash(path: Path, expected: str, label: str) -> None:
    if not path.is_file() or artifacts.file_hash(path) != expected:
        raise ValueError(f"{label} bytes differ from exact receipt")


def _validate_join(record: dict[str, Any], *, expected_path: str, expected_sha: str,
                   root: Path, label: str) -> Path:
    if record.get("path") != expected_path or record.get("sha256") != expected_sha:
        raise ValueError(f"{label} path/hash differs from pinned SourceKit interface receipt")
    path = Path(expected_path)
    if not path.is_absolute():
        path = root / path
    _require_hash(path, expected_sha, label)
    return path


def _evaluate_actor_candidate(row: dict[str, Any], raw_entities: list[dict[str, Any]], *,
                              interface_text: str, interface_sha256: str,
                              demangle_text: str) -> dict[str, Any]:
    if row.get("module") != ACTOR_MODULE or row.get("kind") != "actor":
        raise ValueError("actor adapter accepts only exact SwiftUICore actor declaration")
    if (row.get("line"), row.get("name"), row.get("expectedAccess")) != (ACTOR_LINE, ACTOR_NAME, "public"):
        raise ValueError("actor adapter source identity differs from reviewed candidate")
    validator = _actor_validator()
    result = validator.validate_actor_bridge(row, raw_entities, interface_text=interface_text,
                                             interface_sha256=interface_sha256,
                                             demangle_text=demangle_text)
    if not result.get("accepted"):
        raise ValueError("actor bridge production validator rejected row: " + ",".join(result.get("reasons", [])))
    usr = raw_entities[0]["usr"]
    mangled = "$s" + usr[2:] if usr.startswith("s:") else usr
    result_lines = [line for line in demangle_text.splitlines() if line.startswith("$s")]
    if len(result_lines) != 1 or not result_lines[0].startswith(mangled + " ---> "):
        raise ValueError("actor demangle stdout result identity differs from exact raw USR")
    return {"usr": usr, "validator": result, "rawEntity": raw_entities[0]}


def _validate_actor_bridge(v9: dict[str, Any], *, root: Path,
                           edge_evidence_path: Path) -> dict[str, Any]:
    _require_hash(edge_evidence_path, EDGE_EVIDENCE_SHA256, "actor edge evidence")
    edge = json.loads(edge_evidence_path.read_text(encoding="utf-8"))
    _require_hash(root / "factory/catalogue/compiler-edge-spike/actor_bridge_validator.py",
                  ACTOR_VALIDATOR_SHA256, "actor validator")
    if edge.get("kind") != "f1-compiler-edge-spike":
        raise ValueError("unexpected actor evidence kind")
    inputs = edge.get("inputs", {})
    pinned = {
        "factory/catalogue/compiler-cursor-spike/link-evidence.json": LINK_SHA256,
        "factory/catalogue/compiler-edge-spike/actor_bridge_validator.py": ACTOR_VALIDATOR_SHA256,
        "factory/catalogue/compiler-edge-spike/actor-kind-probe.swift": inputs["actorFixtureSource"]["sha256"],
        "factory/catalogue/compiler-edge-spike/investigate_edges.py": inputs["edgeInvestigator"]["sha256"],
        "factory/catalogue/residual-investigation/residual-evidence.json": inputs["residualEvidence"]["sha256"],
        "factory/catalogue/residual-investigation/investigate.py": inputs["residualInvestigatorSource"]["sha256"],
        "factory/catalogue/compiler-cursor-spike/strict_match.py": inputs["strictMatcherSource"]["sha256"],
        "factory/catalogue/evidence/interface-audit-v6.json": inputs["v6Audit"]["sha256"],
    }
    for relative, expected in pinned.items():
        _require_hash(root / relative, expected, relative)
    link_path = root / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
    links = json.loads(link_path.read_text(encoding="utf-8"))
    module_record = next(item for item in v9["interfaces"] if item["module"] == ACTOR_MODULE)
    v7 = audit_v8._load_pinned_v7(root / "factory/catalogue/evidence/interface-audit-v7.json")
    v7_record = next(item for item in v7["sourceKitAuthority"]["interfaces"] if item["module"] == ACTOR_MODULE)
    edge_row = next(row for row in edge["rows"] if row.get("category") == "wrong-kind")
    source_link = next((row for row in links["rows"] if row.get("module") == ACTOR_MODULE
                        and row.get("line") == ACTOR_LINE and row.get("name") == ACTOR_NAME), None)
    if source_link is None:
        raise ValueError("actor bridge row is absent from immutable link evidence")
    if (source_link.get("linkHoldReason") != "declaration-kind-mismatch"
            or source_link.get("linkEligibility") is not False
            or source_link.get("kind") != "actor"
            or source_link.get("expectedAccess") != "public"
            or source_link.get("sourceHash") != module_record["sha256"]):
        raise ValueError("actor bridge link row differs from pinned unresolved actor source")
    if edge_row.get("key") != [ACTOR_MODULE, module_record["file"], ACTOR_LINE, ACTOR_NAME]:
        raise ValueError("actor edge evidence names a different exact interface declaration")
    declaration_matches = [row for row in v9["declarations"] if (
        row.get("module"), row.get("interface"), row.get("line"), row.get("name"),
        tuple(row.get("context", [])), row.get("signature")) == (
        source_link.get("module"), source_link.get("interface"), source_link.get("line"),
        source_link.get("name"), tuple(source_link.get("context", [])), source_link.get("signature"))]
    if len(declaration_matches) != 1 or declaration_matches[0].get("classification") != "unexplained":
        raise ValueError("actor candidate does not resolve to one unresolved v9 row")
    declaration = declaration_matches[0]
    if declaration.get("sourceKitEvidence", {}).get("reason") != "sourcekit-kind-does-not-match-interface":
        raise ValueError("actor candidate does not have exact expected v9 hold reason")

    interface_input = inputs.get("linkEvidence")
    if (v7_record["sha256"] != module_record["sha256"]
            or edge_row.get("interface", {}).get("path") != v7_record["path"]
            or edge_row.get("interface", {}).get("sha256") != module_record["sha256"]):
        raise ValueError("actor interface source does not join to v7 and edge receipt")
    raw_request = edge_row.get("request", {})
    request_path = _validate_join(raw_request, expected_path=v7_record["indexRequest"],
                                  expected_sha=v7_record["indexRequestSha256"], root=root,
                                  label="actor SourceKit request")
    raw_response = edge_row.get("raw", {}).get("response", {})
    response_path = _validate_join(raw_response, expected_path=v7_record["indexOutput"],
                                   expected_sha=v7_record["indexOutputSha256"], root=root,
                                   label="actor SourceKit response")
    audit_v7._validate_request_identity(request_path, interface=v7_record["path"],
        sdk=v7["sourceKitAuthority"]["pinnedInputs"]["sdk"], target=v7["symbolgraphTarget"], module=ACTOR_MODULE)
    toolchain = links.get("toolchainEvidence", {})
    audit_v9.audit_v8._validate_live_tool_bindings({
        "compiler": toolchain.get("compiler", {}), "sourcekitLsp": toolchain.get("sourcekitLsp", {}),
        "sourcekitd": toolchain.get("sourcekitd", {}),
    })
    demangle_receipt = edge_row.get("compilerKindControl", {}).get("demangleInvocationReceipt", {})
    demangler = Path(demangle_receipt.get("tool", {}).get("path", ""))
    _require_hash(demangler, demangle_receipt.get("tool", {}).get("sha256", ""), "live swift-demangle binary")
    interface_path = Path(v7_record["path"])
    _require_hash(interface_path, module_record["sha256"], "actor SDK interface")
    raw_entities = audit_v7._index_entities(response_path)
    candidates = [entity for entity in raw_entities if entity.get("line") == ACTOR_LINE
                 and entity.get("name") == ACTOR_NAME]
    if len(candidates) != 1:
        raise ValueError(f"actor raw SourceKit identity cardinality is {len(candidates)}")
    entity = candidates[0]
    edge_cards = edge_row.get("raw", {}).get("cards")
    if (not isinstance(edge_cards, list) or len(edge_cards) != 1
            or edge_cards[0].get("is_implicit") not in (None, False)
            or {key: value for key, value in edge_cards[0].items() if key != "is_implicit"} != entity):
        raise ValueError("actor edge raw card differs from pinned SourceKit response")
    target = v7["symbolgraphTarget"]
    if links.get("toolchainEvidence", {}).get("target") != target:
        raise ValueError("actor compiler target differs from pinned symbolgraph target")
    usr = str(entity.get("usr", ""))
    mangled = "$s" + usr[2:] if usr.startswith("s:") else usr
    completed = subprocess.run([str(demangler), "--expand", mangled], check=True,
                               capture_output=True, text=True)
    if completed.stderr:
        raise ValueError("actor swift-demangle emitted unexpected stderr")
    if artifacts.file_hash(Path(inputs["linkEvidence"]["path"])) != LINK_SHA256:
        raise ValueError("actor link evidence changed after validation")
    interface_text = interface_path.read_text(encoding="utf-8")
    row_for_validator = {**source_link, "sourceHash": source_link["sourceHash"],
                         "expectedAccess": source_link["expectedAccess"]}
    actor_result = _evaluate_actor_candidate(row_for_validator, candidates,
        interface_text=interface_text, interface_sha256=module_record["sha256"],
        demangle_text=completed.stdout)
    return {"declaration": declaration, "link": source_link, "entity": entity,
            "actorResult": actor_result,
            "demangleReceipt": {"toolPath": str(demangler), "toolSha256": demangle_receipt["tool"]["sha256"],
                                "stdoutSha256": "sha256:" + hashlib.sha256(completed.stdout.encode("utf-8")).hexdigest(),
                                "stderrBytes": 0, "target": target},
            "requestPath": str(request_path.relative_to(root)),
            "requestSha256": v7_record["indexRequestSha256"],
            "responsePath": str(response_path.relative_to(root)),
            "responseSha256": v7_record["indexOutputSha256"]}


def _module_validator(root: Path):
    relative = "factory/catalogue/module-provenance-spike/exact_validator.py"
    path = root / relative
    _require_hash(path, MODULE_VALIDATOR_SHA256, "module-origin validator")
    spec = importlib.util.spec_from_file_location("_sr1_v10_module_origin", path)
    if spec is None or spec.loader is None:
        raise ValueError("cannot load pinned module-origin validator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _validate_module_bridge(v9: dict[str, Any], *, root: Path,
                            module_evidence_path: Path) -> dict[str, Any]:
    evidence_path = Path(module_evidence_path)
    _require_hash(evidence_path, MODULE_EVIDENCE_SHA256, "module-origin evidence")
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    pinned_files = {
        "factory/catalogue/module-provenance-spike/exact_validator.py": MODULE_VALIDATOR_SHA256,
        "factory/catalogue/module-provenance-spike/test_module_provenance.py": MODULE_TEST_SHA256,
        "factory/catalogue/module-provenance-spike/investigate_module_provenance.py": MODULE_INVESTIGATOR_SHA256,
        "factory/catalogue/module-provenance-spike/swift-demangle-module-expand-v2.txt": MODULE_TREES_SHA256,
        "factory/catalogue/compiler-cursor-spike/link-evidence.json": LINK_SHA256,
    }
    for relative, expected in pinned_files.items():
        _require_hash(root / relative, expected, relative)
    if (evidence.get("kind") != "f1-module-provenance-investigation" or evidence.get("version") != 2
            or evidence.get("status") != "review-only-qualified-module-resolution"):
        raise ValueError("module-origin evidence identity/status differs from reviewed freeze")
    resolution = evidence.get("resolution", {})
    if (resolution.get("rows") != 33 or resolution.get("exactCrossModuleExtensionProof") != 33
            or resolution.get("exactOriginallyDefinedInAliasProof") != 33
            or resolution.get("strictBridgePromotion") != 0 or len(evidence.get("rows", [])) != 33):
        raise ValueError("module-origin evidence is not exact reviewed 33-row hold set")
    inputs = evidence.get("inputs", {})
    if inputs.get("immutable836", {}).get("sha256") != LINK_SHA256:
        raise ValueError("module-origin immutable compiler-link lineage changed")
    if inputs.get("validator", {}).get("sha256") != MODULE_VALIDATOR_SHA256:
        raise ValueError("module-origin evidence names a different validator")
    if inputs.get("test", {}).get("sha256") != MODULE_TEST_SHA256:
        raise ValueError("module-origin evidence names different validator tests")
    if inputs.get("investigator", {}).get("sha256") != MODULE_INVESTIGATOR_SHA256:
        raise ValueError("module-origin evidence names a different investigator")
    if inputs.get("trees", {}).get("sha256") != MODULE_TREES_SHA256:
        raise ValueError("module-origin evidence names different expanded demangle bytes")

    validator_module = _module_validator(root)
    validator = validator_module.Validator()
    reconstructed = validator.validate()
    evidence_rows = evidence["rows"]
    if reconstructed != evidence_rows:
        raise ValueError("fresh module-origin validator replay differs from frozen evidence rows")
    if len({tuple(row.get("key", [])) for row in reconstructed}) != 33:
        raise ValueError("module-origin bridge has duplicate declaration keys")
    if any(row.get("status") != "qualified-cross-module-extension-hold" for row in reconstructed):
        raise ValueError("module-origin validator emitted an unsupported row status")

    link_path = root / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
    links = json.loads(link_path.read_text(encoding="utf-8"))
    promotions = []
    seen: set[tuple[str, str, int, str]] = set()
    for bridge_row in reconstructed:
        key = tuple(bridge_row["key"])
        if key in seen:
            raise ValueError("module-origin bridge repeats a source declaration")
        seen.add(key)
        module, interface, line, name = key
        if module != "SwiftUI":
            raise ValueError("module-origin bridge exceeds exact SwiftUI member allowlist")
        link_matches = [row for row in links["rows"] if (
            row.get("module"), row.get("interface"), row.get("line"), row.get("name")) == key]
        if len(link_matches) != 1:
            raise ValueError("module-origin row does not join uniquely to immutable 836 link row")
        link = link_matches[0]
        if (link.get("linkHoldReason") != "enclosing-context-mismatch"
                or link.get("linkEligibility") is not False
                or link.get("sourceHash") != inputs["SwiftUI:source"]["sha256"]
                or link.get("signature") != bridge_row.get("signature")
                or link.get("context") != bridge_row.get("originFullPath")):
            raise ValueError("module-origin source link differs from exact context-held declaration")
        if (link.get("sameLineEntityCount") != 1 or link.get("sameLineNameEntityCount") != 1
                or link.get("sameLineKindEntityCount") != 1 or link.get("sourcekitEntityCount") != 0):
            raise ValueError("module-origin raw occurrence counts differ from frozen link row")
        candidates = [row for row in v9["declarations"] if (
            row.get("module"), row.get("interface"), row.get("line"), row.get("name")) == key]
        if len(candidates) != 1:
            raise ValueError("module-origin bridge does not resolve to one v9 declaration")
        declaration = candidates[0]
        if (declaration.get("classification") != "unexplained"
                or declaration.get("sourceKitEvidence", {}).get("reason") != "raw-sourcekit-context-does-not-match-interface-context"
                or declaration.get("signature") != bridge_row.get("signature")
                or declaration.get("context") != bridge_row.get("originFullPath")
                or declaration.get("sourceKitEvidence", {}).get("interfaceSha256") != inputs["SwiftUI:source"]["sha256"]):
            raise ValueError("module-origin bridge does not match exact unresolved v9 row")
        raw_candidates = declaration.get("sourceKitEvidence", {}).get("rawCandidateAssessments", [])
        matching_usr = [item for item in raw_candidates if item.get("usr") == bridge_row["member"].get("usr")
                        and item.get("line") == line and item.get("name") == bridge_row["member"].get("name")]
        if (len(matching_usr) != 1 or bridge_row["member"].get("effective_access") != "source.decl.effective_access.public"
                or matching_usr[0].get("kind") != bridge_row["member"].get("kind")
                or matching_usr[0].get("effectiveAccess") != bridge_row["member"].get("effective_access")):
            raise ValueError("module-origin compiler member does not match exact public raw v9 assessment")
        promotions.append({"declaration": declaration, "bridgeRow": bridge_row, "link": link})
    if len(promotions) != 33:
        raise ValueError("module-origin bridge did not supply exact 33 reviewed rows")
    return {"promotions": promotions, "evidencePath": evidence_path,
            "evidenceSha256": MODULE_EVIDENCE_SHA256,
            "validatorSha256": MODULE_VALIDATOR_SHA256,
            "testSha256": MODULE_TEST_SHA256,
            "investigatorSha256": MODULE_INVESTIGATOR_SHA256,
            "treesSha256": MODULE_TREES_SHA256}


def build_audit_v10(v9_path: Path, *, root: Path, edge_evidence_path: Path,
                    module_evidence_path: Path) -> dict[str, Any]:
    root = Path(root)
    v9 = _load_v9(Path(v9_path), root=root)
    actor = _validate_actor_bridge(v9, root=root, edge_evidence_path=Path(edge_evidence_path))
    module = _validate_module_bridge(v9, root=root, module_evidence_path=Path(module_evidence_path))
    declarations = copy.deepcopy(v9["declarations"])
    actor_target = next(row for row in declarations if (
        row.get("module"), row.get("interface"), row.get("line"), row.get("name"),
        tuple(row.get("context", [])), row.get("signature")) == (
        actor["declaration"].get("module"), actor["declaration"].get("interface"),
        actor["declaration"].get("line"), actor["declaration"].get("name"),
        tuple(actor["declaration"].get("context", [])), actor["declaration"].get("signature")))
    actor_usr = actor["entity"]["usr"]
    actor_target["symbol"] = {"usr": actor_usr, "source": "SourceKit index + actor-marker/compiler-USR bridge"}
    actor_target["sourceKitEvidence"].pop("reason", None)
    actor_target["sourceKitEvidence"]["compilerUsr"] = actor_usr
    actor_target["sourceKitEvidence"]["actorBridge"] = {
        "path": str(Path(edge_evidence_path).relative_to(root)), "sha256": EDGE_EVIDENCE_SHA256,
        "validatorSha256": ACTOR_VALIDATOR_SHA256, "method": "exact actor source marker + SourceKit entity + expanded USR tree",
        "expectedAccess": "public", "effectiveAccess": actor["entity"]["effective_access"],
        "requestPath": actor["requestPath"], "requestSha256": actor["requestSha256"],
        "responsePath": actor["responsePath"], "responseSha256": actor["responseSha256"],
        "demangle": actor["demangleReceipt"],
    }
    promotions = [{"declaration": actor["declaration"], "entity": actor["entity"], "kind": "actor"}]
    for entry in module["promotions"]:
        promotions.append({"declaration": entry["declaration"], "entity": entry["bridgeRow"]["member"],
                           "kind": "module-origin", "bridgeRow": entry["bridgeRow"]})
    v7 = audit_v8._load_pinned_v7(root / "factory/catalogue/evidence/interface-audit-v7.json")
    catalogue_path = root / v7["sourceKitAuthority"]["pinnedInputs"]["symbolCatalogue"]
    if artifacts.file_hash(catalogue_path) != v7["sourceKitAuthority"]["pinnedInputs"]["symbolCatalogueHash"]:
        raise ValueError("v7-pinned symbol catalogue bytes changed")
    catalogue = json.loads(catalogue_path.read_text(encoding="utf-8"))
    graph_by_usr: dict[str, list[dict[str, Any]]] = {}
    for symbol in catalogue.get("symbols", []):
        if symbol.get("usr") != symbol.get("precise"):
            raise ValueError("pinned symbol catalogue has inconsistent USR/precise fields")
        graph_by_usr.setdefault(str(symbol["usr"]), []).append(symbol)
    promoted_present = promoted_absent = 0
    for entry in promotions:
        declaration, entity = entry["declaration"], entry["entity"]
        target = next(row for row in declarations if (
            row.get("module"), row.get("interface"), row.get("line"), row.get("name"),
            tuple(row.get("context", [])), row.get("signature")) == (
            declaration.get("module"), declaration.get("interface"), declaration.get("line"),
            declaration.get("name"), tuple(declaration.get("context", [])), declaration.get("signature")))
        usr = entity["usr"]
        matches = graph_by_usr.get(usr, [])
        target["sourceKitEvidence"]["symbolGraphMatches"] = matches
        target["classification"] = ("matched-sourcekit-usr-in-symbolgraph" if matches
                                     else "matched-sourcekit-usr-absent-from-symbolgraph")
        if matches:
            promoted_present += 1
        else:
            promoted_absent += 1
        target["symbol"] = {"usr": usr, "source": "SourceKit index + exact actor/source-origin compiler bridge"}
        target["sourceKitEvidence"]["compilerUsr"] = usr
        target["sourceKitEvidence"].pop("reason", None)
        if entry["kind"] == "module-origin":
            bridge = entry["bridgeRow"]
            target["sourceKitEvidence"]["crossModuleOriginBridge"] = {
                "path": str(Path(module_evidence_path).relative_to(root)),
                "sha256": MODULE_EVIDENCE_SHA256, "validatorSha256": MODULE_VALIDATOR_SHA256,
                "interfaceKey": bridge["key"], "target": bridge["target"],
                "compilerOwner": bridge["compilerOwner"], "memberUsr": bridge["member"]["usr"],
                "originUsr": bridge["origin"]["usr"], "originModule": bridge["originModule"],
                "originFullPath": bridge["originFullPath"],
                "originallyDefinedIn": bridge["originallyDefinedIn"],
            }
    from collections import Counter
    counts = Counter(row["classification"] for row in declarations)
    held_reasons = Counter(row.get("sourceKitEvidence", {}).get("reason") for row in declarations
                            if row.get("classification") in audit_v8.RESIDUAL_CLASSIFICATIONS
                            and row.get("sourceKitEvidence", {}).get("reason"))
    remaining = sum(counts[name] for name in audit_v8.RESIDUAL_CLASSIFICATIONS)
    payload = copy.deepcopy(v9)
    payload.pop("auditHash", None)
    payload.update({
        "version": 10,
        "status": "incomplete-v10-actor-and-module-origin-consumer-validated",
        "method": v9["method"] + " V10 adds exactly one public actor-kind edge and 33 SwiftUI declarations extended from SwiftUICore nominal origins, each through independently pinned raw compiler, source, request, access, owner, and expanded-USR revalidation.",
        "parentAudit": {"path": str(Path(v9_path).relative_to(root)), "fileSha256": V9_FILE_SHA256,
                        "auditHash": V9_AUDIT_HASH},
        "declarations": declarations,
        "summary": {
            **v9["summary"],
            "newlyPromotedRows": v9["summary"]["newlyPromotedRows"] + len(promotions),
            "exactSourceKitUsrLinks": v9["summary"]["exactSourceKitUsrLinks"] + len(promotions),
            "heldSourceKitRows": v9["summary"]["heldSourceKitRows"] - len(promotions),
            "sourceKitUsrPresentInSymbolGraph": v9["summary"]["sourceKitUsrPresentInSymbolGraph"] + promoted_present,
            "sourceKitUsrAbsentFromSymbolGraph": v9["summary"]["sourceKitUsrAbsentFromSymbolGraph"] + promoted_absent,
            "heldSourceKitReasons": dict(sorted(held_reasons.items())),
            "remainingActiveUnmappedAmbiguousOrUnexplained": remaining,
            "byClassification": dict(sorted(counts.items())),
        },
        "actorBridgeEvidence": {"path": str(Path(edge_evidence_path).relative_to(root)),
                                "sha256": EDGE_EVIDENCE_SHA256,
                                "validatorSha256": ACTOR_VALIDATOR_SHA256,
                                "promotedRows": 1, "state": "consumer-validated"},
        "moduleOriginBridgeEvidence": {"path": str(Path(module_evidence_path).relative_to(root)),
                                       "sha256": MODULE_EVIDENCE_SHA256,
                                       "validatorSha256": MODULE_VALIDATOR_SHA256,
                                       "promotedRows": len(module["promotions"]),
                                       "originNominalCount": 6, "state": "consumer-validated"},
        "pendingEvidence": [
            {"kind": "remaining-active-unmapped-ambiguous-or-unexplained", "path": None,
             "expectedRows": remaining, "state": "unresolved"},
        ],
    })
    payload["provenance"] = artifacts.provenance(V9_AUDIT_HASH,
        [{"path": str(Path(v9_path).relative_to(root)), "hash": V9_FILE_SHA256},
         {"path": str(Path(edge_evidence_path).relative_to(root)), "hash": EDGE_EVIDENCE_SHA256},
         {"path": "factory/catalogue/compiler-edge-spike/actor_bridge_validator.py", "hash": ACTOR_VALIDATOR_SHA256},
         {"path": str(Path(module_evidence_path).relative_to(root)), "hash": MODULE_EVIDENCE_SHA256},
         {"path": "factory/catalogue/module-provenance-spike/exact_validator.py", "hash": MODULE_VALIDATOR_SHA256},
         {"path": "factory/catalogue/module-provenance-spike/test_module_provenance.py", "hash": MODULE_TEST_SHA256},
         {"path": "factory/catalogue/module-provenance-spike/investigate_module_provenance.py", "hash": MODULE_INVESTIGATOR_SHA256},
         {"path": "factory/catalogue/module-provenance-spike/swift-demangle-module-expand-v2.txt", "hash": MODULE_TREES_SHA256},
         {"path": "factory/catalogue/audit_v10.py", "hash": artifacts.file_hash(Path(__file__))}],
        producer="sr1-factory.catalogue.audit-v10-candidate")
    payload["auditHash"] = artifacts.canonical_hash(payload)
    return payload


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    value = build_audit_v10(root / "factory/catalogue/evidence/interface-audit-v9-candidate.json",
                            root=root,
                            edge_evidence_path=root / "factory/catalogue/compiler-edge-spike/edge-evidence.json",
                            module_evidence_path=root / "factory/catalogue/module-provenance-spike/module-provenance-evidence.json")
    artifacts.write_artifact(root / "factory/catalogue/evidence/interface-audit-v10-candidate.json", value)


if __name__ == "__main__":
    main()
