#!/usr/bin/env python3
"""Emit review-only evidence for the seven F1 compiler edge holds.

This script reads frozen inputs and writes only this directory.  It never
changes link evidence, audit evidence, or adapter code.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import re
import copy
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
SPIKE = ROOT / "factory/catalogue/compiler-cursor-spike"
LINK = SPIKE / "link-evidence.json"
AUDIT = ROOT / "factory/catalogue/evidence/interface-audit-v6.json"
RESIDUAL = ROOT / "factory/catalogue/residual-investigation/residual-evidence.json"
STRICT = SPIKE / "strict_match.py"
EXPECTED_LINK_SHA256 = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
SDK = "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"
TARGET = "arm64-apple-macosx27.0"
INTERFACES = {
    "SwiftUI": Path(SDK) / "System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface",
    "SwiftUICore": Path(SDK) / "System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface",
}


def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def load_module(path: Path, name: str) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def excerpt(path: Path, first: int, last: int) -> list[dict[str, Any]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    return [{"line": n, "text": lines[n - 1]} for n in range(first, last + 1)]


def request_receipt(path: Path) -> dict[str, str]:
    return {"path": rel(path), "sha256": sha(path)}


def response_receipt(path: Path) -> dict[str, str]:
    return {"path": rel(path), "sha256": sha(path)}


def raw_card(entity: dict[str, Any]) -> dict[str, Any]:
    return {key: entity.get(key) for key in (
        "kind", "name", "usr", "line", "column", "effective_access", "is_implicit",
    )} | {"sourcekitContext": entity.get("sourcekitContext", [])}


def stable_digest(value: Any) -> str:
    return "sha256:" + hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()


def main() -> None:
    link = json.loads(LINK.read_text(encoding="utf-8"))
    audit = json.loads(AUDIT.read_text(encoding="utf-8"))
    residual = json.loads(RESIDUAL.read_text(encoding="utf-8"))
    actual_link_sha = sha(LINK)
    if actual_link_sha != EXPECTED_LINK_SHA256:
        raise SystemExit(f"frozen link hash mismatch: {actual_link_sha}")

    inv = load_module(ROOT / "factory/catalogue/residual-investigation/investigate.py", "f1_inv")
    strict = load_module(STRICT, "f1_strict")
    bridge = load_module(HERE / "actor_bridge_validator.py", "actor_bridge_validator")
    probe_receipts = json.loads((HERE / "probe-receipts.json").read_text(encoding="utf-8"))
    raw_by_key: dict[tuple[str, int, str], list[dict[str, Any]]] = {}
    for module, path in inv.INDEX_OUTPUTS.items():
        for entity in inv.entities(path):
            key = (module, int(entity["line"]), inv.normalized_name(str(entity["name"])))
            raw_by_key.setdefault(key, []).append(entity)
    audit_by_key = {
        (row["module"], int(row["line"]), inv.normalized_name(str(row["name"]))): row
        for row in audit["declarations"]
    }
    residual_by_key = {
        (row["module"], int(row["line"]), inv.normalized_name(str(row["name"]))): row
        for row in residual["rows"]
    }

    def residual_row(module: str, line: int) -> dict[str, Any]:
        return next(row for row in residual["rows"]
                    if row["module"] == module and int(row["line"]) == line)

    duplicate_specs = [
        ("SwiftUI", 4080, "$isOn", 4065, 4082),
        ("SwiftUI", 5533, "$isExpanded", 5537, 5535),
        ("SwiftUI", 9717, "$document", 9699, 9719),
        ("SwiftUI", 23750, "$document", 23729, 23752),
        ("SwiftUI", 32822, "$selection", 32804, 32824),
    ]
    rows: list[dict[str, Any]] = []
    for module, line, source_name, first, last in duplicate_specs:
        key = (module, line, source_name)
        candidates = raw_by_key.get(key, [])
        audit_row = audit_by_key[(module, line, "var")]
        residual_item = residual_row(module, line)
        cards = [raw_card(item) for item in candidates]
        rows.append({
            "key": [module, "arm64e-apple-macos.swiftinterface", line, "var"],
            "category": "duplicate-sourcekit-usr",
            "classification": residual_item["classification"],
            "holdReason": link_row(link, module, line, "var")["linkHoldReason"],
            "interface": {
                "path": rel(INTERFACES[module]),
                "sha256": sha(INTERFACES[module]),
                "sourceLine": line,
                "sourceName": source_name,
                "signature": audit_row["signature"],
                "context": audit_row["context"],
                "conditionalResolution": audit_row.get("conditionalResolution"),
                "enclosingScopes": audit_row.get("v6Evidence", {}).get("enclosingScopes", []),
                "sourceExcerpt": excerpt(INTERFACES[module], first, last),
            },
            "request": request_receipt(SPIKE / "request-index-interface.yaml"),
            "raw": {
                "response": response_receipt(SPIKE / "index-interface-output.txt"),
                "cards": cards,
                "cardCount": len(cards),
                "distinctUsrCount": len({card.get("usr") for card in cards}),
                "cardDigests": [stable_digest(card) for card in cards],
                "parsedCardsIdentical": len(cards) == 2 and len({stable_digest(card) for card in cards}) == 1,
            },
            "symbolGraph": link_row(link, module, line, "var").get("indexMatches", [{}])[0].get("symbolGraphMatches", []),
            "decision": {
                "status": "held",
                "reason": "Two raw records remain two observations even though their full declaration cards and USR are identical; no blind deduplication is allowed.",
                "promotion": None,
            },
        })

    actor_key = ("SwiftUICore", 18132, "_ImpossibleActor")
    actor_link = link_row(link, "SwiftUICore", 18132, "_ImpossibleActor")
    actor_audit = audit_by_key[actor_key]
    actor_raw = raw_by_key[actor_key]
    actor_entity = actor_raw[0] if len(actor_raw) == 1 else None
    fixture_entities = inv.entities(HERE / "actor-kind-output.txt")
    fixture_actor = next(raw_card(x) for x in fixture_entities if x.get("name") == "ProbeActor")
    fixture_class = next(raw_card(x) for x in fixture_entities if x.get("name") == "ProbeClass")
    actor_row = {
        "module": "SwiftUICore", "sourceHash": actor_link["sourceHash"], "line": 18132,
        "kind": "actor", "name": "_ImpossibleActor", "context": [],
        "signature": actor_audit["signature"],
    }
    strict_before = (
        actor_entity is not None
        and strict.entity_matches(
            actor_row, actor_entity, module="SwiftUICore", live_interface_hash=actor_link["sourceHash"]
        )
    )
    class_row = dict(actor_row, kind="class")
    strict_class_shape = actor_entity is not None and strict.entity_matches(
        class_row, actor_entity, module="SwiftUICore", live_interface_hash=actor_link["sourceHash"]
    )
    actor_demangle_text = (HERE / "actor-kind-demangle.txt").read_text(encoding="utf-8")
    actor_validation = bridge.validate_actor_bridge(
        actor_row, actor_raw,
        interface_text=INTERFACES["SwiftUICore"].read_text(encoding="utf-8"),
        interface_sha256=sha(INTERFACES["SwiftUICore"]),
        demangle_text=actor_demangle_text,
    )
    actor_usr = actor_entity.get("usr") if actor_entity is not None else None
    actor_tree = bridge.parse_demangle_tree(
        actor_demangle_text, actor_usr
    ) if actor_usr else None
    actor_root_kind = next((node.get("kind") for node in (actor_tree or {}).get("children", [])
                            if node.get("kind") in {"Class", "Actor", "Structure", "Enum"}), None)
    actor_interface_text = INTERFACES["SwiftUICore"].read_text(encoding="utf-8")
    accepted_actor = bridge.actor_bridge_accepts(
        actor_row, actor_raw,
        interface_text=actor_interface_text,
        interface_sha256=sha(INTERFACES["SwiftUICore"]),
        demangle_text=actor_demangle_text,
    )
    def rejects(raw: list[dict[str, Any]] | None = None, row: dict[str, Any] | None = None,
                source: str | None = None, demangle: str | None = None) -> bool:
        return not bridge.actor_bridge_accepts(
            row or actor_row, raw if raw is not None else actor_raw,
            interface_text=source if source is not None else actor_interface_text,
            interface_sha256=sha(INTERFACES["SwiftUICore"]),
            demangle_text=demangle if demangle is not None else actor_demangle_text,
        )
    wrong_line = copy.deepcopy(actor_entity)
    wrong_line["line"] += 1
    wrong_name = copy.deepcopy(actor_entity)
    wrong_name["name"] = "OtherActor"
    wrong_context = copy.deepcopy(actor_entity)
    wrong_context["sourcekitContext"] = [{"kind": "source.lang.swift.decl.struct", "name": "OtherOwner"}]
    wrong_access = copy.deepcopy(actor_entity)
    wrong_access["effective_access"] = "source.decl.effective_access.internal"
    wrong_source_hash = dict(actor_row, sourceHash="sha256:" + "0" * 64)
    wrong_module = dict(actor_row, module="SwiftUI")
    wrong_class_marker = dict(actor_row, kind="class")
    wrong_source_marker = actor_interface_text.replace(
        "public actor _ImpossibleActor : Swift::Sendable {",
        "public class _ImpossibleActor : Swift::Sendable {",
        1,
    )
    wrong_usr = copy.deepcopy(actor_entity)
    wrong_usr["usr"] = fixture_class["usr"]
    target_marker = f"Demangling for $s{actor_entity['usr'][2:]}"
    target_start = actor_demangle_text.index(target_marker)
    next_section = actor_demangle_text.find("\nDemangling for ", target_start + 1)
    target_section = actor_demangle_text[target_start:next_section if next_section >= 0 else len(actor_demangle_text)]
    duplicate_demangle_section = actor_demangle_text + "\n" + target_section
    wrong_demangle_module = actor_demangle_text.replace(
        '    kind=Module, text="SwiftUICore"\n',
        '    kind=Module, text="OtherModule"\n', 1,
    )
    wrong_demangle_name = actor_demangle_text.replace(
        '    kind=Identifier, text="_ImpossibleActor"\n',
        '    kind=Identifier, text="OtherActor"\n', 1,
    )
    duplicate_demangle_module = actor_demangle_text.replace(
        '    kind=Module, text="SwiftUICore"\n',
        '    kind=Module, text="SwiftUICore"\n    kind=Module, text="OtherModule"\n', 1,
    )
    duplicate_demangle_name = actor_demangle_text.replace(
        '    kind=Identifier, text="_ImpossibleActor"\n',
        '    kind=Identifier, text="_ImpossibleActor"\n    kind=Identifier, text="OtherActor"\n', 1,
    )
    changed_interface_text = actor_interface_text.replace("  #endif", "  #endif ", 1)
    actor_fault_controls = {
        "acceptedBaseline": accepted_actor,
        "wrongLineRejected": rejects([wrong_line]),
        "wrongNameRejected": rejects([wrong_name]),
        "wrongContextRejected": rejects([wrong_context]),
        "wrongAccessRejected": rejects([wrong_access]),
        "wrongSourceHashRejected": rejects(row=wrong_source_hash),
        "wrongModuleRejected": rejects(row=wrong_module),
        "classMarkerRejected": rejects(row=wrong_class_marker),
        "wrongSourceMarkerRejected": rejects(source=wrong_source_marker),
        "duplicateRawCardRejected": rejects(raw=[copy.deepcopy(actor_entity), copy.deepcopy(actor_entity)]),
        "changedInterfaceBytesRejected": rejects(source=changed_interface_text),
        "wrongUsrRejected": rejects(raw=[wrong_usr]),
        "wrongDemangleModuleRejected": rejects(demangle=wrong_demangle_module),
        "wrongDemangleNameRejected": rejects(demangle=wrong_demangle_name),
        "duplicateDemangleSectionRejected": rejects(demangle=duplicate_demangle_section),
        "duplicateDemangleModuleRejected": rejects(demangle=duplicate_demangle_module),
        "duplicateDemangleNameRejected": rejects(demangle=duplicate_demangle_name),
    }
    fixture_typecheck = probe_receipts["actorTypecheck"]
    fixture_demangle = probe_receipts["actorDemangle"]
    sourcekit_receipt = probe_receipts["sourcekitActor"]
    rows.append({
        "key": ["SwiftUICore", "arm64e-apple-macos.swiftinterface", 18132, "_ImpossibleActor"],
        "category": "wrong-kind",
        "classification": residual_row("SwiftUICore", 18132)["classification"],
        "holdReason": actor_link["linkHoldReason"],
        "interface": {
            "path": rel(INTERFACES["SwiftUICore"]), "sha256": sha(INTERFACES["SwiftUICore"]),
            "sourceLine": 18132, "signature": actor_audit["signature"], "context": [],
            "sourceExcerpt": excerpt(INTERFACES["SwiftUICore"], 18130, 18135),
        },
        "request": request_receipt(SPIKE / "request-index-core.yaml"),
        "raw": {"response": response_receipt(SPIKE / "index-core-output.txt"), "cards": [raw_card(x) for x in actor_raw]},
        "compilerKindControl": {
            "fixtureSource": request_receipt(HERE / "actor-kind-probe.swift"),
            "fixtureRequest": request_receipt(HERE / "request-actor-kind.yaml"),
            "fixtureResponse": response_receipt(HERE / "actor-kind-output.txt"),
            "fixtureTypecheckStderr": response_receipt(HERE / "actor-kind-typecheck.stderr"),
            "fixtureDemangle": response_receipt(HERE / "actor-kind-demangle.txt"),
            "probeReceipts": response_receipt(HERE / "probe-receipts.json"),
            "sourcekitInvocationReceipt": sourcekit_receipt,
            "typecheckInvocationReceipt": fixture_typecheck,
            "demangleInvocationReceipt": fixture_demangle,
            "actorSourceFixtureRaw": fixture_actor,
            "classSourceFixtureRaw": fixture_class,
            "actorAndClassDemangleRootKind": actor_root_kind,
            "actorRawKindMatchesProduction": actor_entity is not None and fixture_actor["kind"] == actor_entity["kind"],
            "typecheckExitCode": fixture_typecheck["exitCode"],
            "demangleExitCode": fixture_demangle["exitCode"],
        },
        "actorBridgeValidation": actor_validation,
        "actorFaultControls": actor_fault_controls,
        "decision": {
            "status": "proposed-review-only",
            "reason": "Pinned SourceKit emits class for exact actor source; fixture actor reproduces same raw class kind while ordinary class fixture is also class. Mangled kind alone cannot distinguish them.",
            "promotion": None,
            "reviewProposal": "actor-kind-bridge-requires-interface-actor-marker-and-exact-line/name/context/access/module/source-hash/USR-tree; class interface rows remain ineligible",
        },
        "controls": {
            "productionStrictMatcherRejectsActorAsClass": strict_before is False,
            "productionStrictMatcherAcceptsExplicitClassShape": strict_class_shape is True,
            "actorMarkerRequired": actor_validation["accepted"] is True,
            "classShapeCannotUseActorBridge": not (class_row["kind"] == "actor" and re.search(r"\bactor\b", class_row["signature"]) is not None),
        },
    })

    build_key = ("SwiftUI", 28491, "buildLimitedAvailability")
    build_link = link_row(link, "SwiftUI", 28491, "buildLimitedAvailability")
    build_audit = audit_by_key[build_key]
    rows.append({
        "key": ["SwiftUI", "arm64e-apple-macos.swiftinterface", 28491, "buildLimitedAvailability"],
        "category": "conditional-no-index-entity",
        "classification": residual_row("SwiftUI", 28491)["classification"],
        "holdReason": build_link["linkHoldReason"],
        "interface": {
            "path": rel(INTERFACES["SwiftUI"]), "sha256": sha(INTERFACES["SwiftUI"]),
            "sourceLine": 28491, "signature": build_audit["signature"], "context": build_audit["context"],
            "conditions": build_audit["conditions"],
            "sourceExcerpt": excerpt(INTERFACES["SwiftUI"], 28480, 28494),
        },
        "request": request_receipt(SPIKE / "request-buildLimitedAvailability.yaml"),
        "raw": {
            "indexResponse": response_receipt(SPIKE / "index-interface-output.txt"),
            "indexExactLineNameCount": 0,
            "cursorResponse": response_receipt(SPIKE / "buildLimitedAvailability-output.txt"),
            "cursorResult": "Unable to resolve cursor info.",
            "cursorOffset": 1605000,
        },
        "compilerConditionalControl": {
            "probeSource": request_receipt(HERE / "tilde-sendable-branch-probe.swift"),
            "probeOutput": response_receipt(HERE / "tilde-sendable-branch-output.txt"),
            "probeResult": "selected=active",
            "inlineAlwaysControlSource": request_receipt(SPIKE / "inline-always-conditional-probe.swift"),
            "inlineAlwaysControlOutput": response_receipt(SPIKE / "inline-always-conditional-output.txt"),
            "inlineAlwaysResult": "selected=InlineAlways",
        },
        "symbolGraphCandidates": build_audit.get("v6Evidence", {}).get("candidates", []),
        "decision": {
            "status": "held",
            "reason": "Compiler selects #if compiler(>=5.3) && $InlineAlways; requested line 28491 is inactive #else. No raw SourceKit entity or cursor USR exists for inactive declaration, while two symbol-graph overloads remain signature-ambiguous.",
            "promotion": None,
        },
    })

    toolchain = link.get("toolchainEvidence", {})
    payload = {
        "kind": "f1-compiler-edge-spike",
        "version": 1,
        "status": "review-only-seven-held-cases",
        "method": "Read frozen link evidence by exact module/interface/line/name; verify interface source, SourceKit request/response, compiler conditional branch, and pinned toolchain. No adapter or frozen evidence is edited.",
        "inputs": {
            "linkEvidence": {"path": rel(LINK), "sha256": actual_link_sha, "expectedSha256": EXPECTED_LINK_SHA256},
            "v6Audit": {"path": rel(AUDIT), "sha256": sha(AUDIT)},
            "residualEvidence": {"path": rel(RESIDUAL), "sha256": sha(RESIDUAL)},
            "edgeInvestigator": request_receipt(HERE / "investigate_edges.py"),
            "actorBridgeValidator": request_receipt(HERE / "actor_bridge_validator.py"),
            "strictMatcherSource": request_receipt(STRICT),
            "residualInvestigatorSource": request_receipt(ROOT / "factory/catalogue/residual-investigation/investigate.py"),
            "actorFixtureSource": request_receipt(HERE / "actor-kind-probe.swift"),
        },
        "toolchain": toolchain,
        "summary": {
            "heldCaseCount": 7,
            "duplicateSourceKitUsr": 5,
            "actorKindMismatch": 1,
            "conditionalNoIndexEntity": 1,
            "promotionsMade": 0,
            "actorBridgeReviewCandidate": 1,
            "explicitHolds": 6,
        },
        "controls": {
            "frozenLinkHashVerified": actual_link_sha == EXPECTED_LINK_SHA256,
            "duplicateCardinalityRejectsAllFive": all(row["raw"]["cardCount"] == 2 and row["raw"]["distinctUsrCount"] == 1 and row["raw"]["parsedCardsIdentical"] for row in rows[:5]),
            "actorProductionGateRejectsBeforeBridge": rows[5]["controls"]["productionStrictMatcherRejectsActorAsClass"],
            "actorFixtureReproducesProductionKind": rows[5]["compilerKindControl"]["actorRawKindMatchesProduction"],
            "conditionalInactiveCursorUnresolved": rows[6]["raw"]["cursorResult"] == "Unable to resolve cursor info.",
            "conditionalBranchProbeActive": rows[6]["compilerConditionalControl"]["probeResult"] == "selected=active",
        },
        "rows": rows,
    }
    out = HERE / "edge-evidence.json"
    out.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {out}")


def link_row(link: dict[str, Any], module: str, line: int, name: str) -> dict[str, Any]:
    for row in link["rows"]:
        if row.get("module") == module and int(row.get("line")) == line and row.get("name") == name:
            return row
    raise KeyError((module, line, name))


if __name__ == "__main__":
    main()
