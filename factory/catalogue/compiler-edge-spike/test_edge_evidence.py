#!/usr/bin/env python3
"""Fail-closed assertions for edge-evidence.json."""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
EVIDENCE = HERE / "edge-evidence.json"
EXPECTED = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
sys.path.insert(0, str(HERE))
from actor_bridge_validator import actor_bridge_accepts  # noqa: E402


def digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def resolve(path: str) -> Path:
    value = Path(path)
    return value if value.is_absolute() else ROOT / value


def main() -> None:
    payload = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    assert payload["status"] == "review-only-seven-held-cases"
    assert payload["inputs"]["linkEvidence"]["sha256"] == EXPECTED
    assert payload["inputs"]["linkEvidence"]["expectedSha256"] == EXPECTED
    assert digest(resolve(payload["inputs"]["linkEvidence"]["path"])) == EXPECTED
    assert len(payload["rows"]) == 7
    assert payload["summary"] == {
        "actorBridgeReviewCandidate": 1,
        "actorKindMismatch": 1,
        "conditionalNoIndexEntity": 1,
        "duplicateSourceKitUsr": 5,
        "explicitHolds": 6,
        "heldCaseCount": 7,
        "promotionsMade": 0,
    }
    assert all(payload["controls"].values())
    duplicates = payload["rows"][:5]
    assert all(row["category"] == "duplicate-sourcekit-usr" for row in duplicates)
    assert all(row["decision"]["status"] == "held" for row in duplicates)
    assert all(row["raw"]["cardCount"] == 2 for row in duplicates)
    assert all(row["raw"]["distinctUsrCount"] == 1 for row in duplicates)
    assert all(row["raw"]["parsedCardsIdentical"] is True for row in duplicates)
    actor = payload["rows"][5]
    assert actor["category"] == "wrong-kind"
    assert actor["decision"]["status"] == "proposed-review-only"
    assert all(actor["controls"].values())
    assert callable(actor_bridge_accepts)
    assert all(actor["actorFaultControls"].values())
    for control in (
        "wrongLineRejected", "wrongNameRejected", "wrongContextRejected",
        "wrongAccessRejected", "wrongSourceHashRejected", "wrongModuleRejected",
        "classMarkerRejected", "wrongSourceMarkerRejected", "duplicateRawCardRejected",
        "changedInterfaceBytesRejected", "wrongUsrRejected",
        "wrongDemangleModuleRejected", "wrongDemangleNameRejected",
        "duplicateDemangleSectionRejected", "duplicateDemangleModuleRejected",
        "duplicateDemangleNameRejected",
    ):
        assert actor["actorFaultControls"][control] is True, control
    assert actor["compilerKindControl"]["actorRawKindMatchesProduction"] is True
    actor_raw = actor["raw"]["cards"]
    actor_interface = resolve(actor["interface"]["path"])
    actor_row = {
        "module": "SwiftUICore", "sourceHash": actor["interface"]["sha256"],
        "line": actor["interface"]["sourceLine"], "kind": "actor",
        "name": "_ImpossibleActor", "context": actor["interface"]["context"],
        "signature": actor["interface"]["signature"],
    }
    assert actor_bridge_accepts(
        actor_row, actor_raw, interface_text=actor_interface.read_text(encoding="utf-8"),
        interface_sha256=digest(actor_interface),
        demangle_text=resolve(actor["compilerKindControl"]["fixtureDemangle"]["path"]).read_text(encoding="utf-8"),
    ) is True
    import actor_bridge_validator
    tree = actor_bridge_validator.parse_demangle_tree(
        resolve(actor["compilerKindControl"]["fixtureDemangle"]["path"]).read_text(encoding="utf-8"),
        actor_raw[0]["usr"],
    )
    assert tree is not None
    demangle_root_kind = next(child["kind"] for child in tree["children"] if child["kind"] in {"Class", "Actor", "Structure", "Enum"})
    assert actor["compilerKindControl"]["actorAndClassDemangleRootKind"] == demangle_root_kind
    receipts = json.loads((HERE / "probe-receipts.json").read_text(encoding="utf-8"))
    assert actor["compilerKindControl"]["typecheckExitCode"] == receipts["actorTypecheck"]["exitCode"]
    assert actor["compilerKindControl"]["demangleExitCode"] == receipts["actorDemangle"]["exitCode"]
    build = payload["rows"][6]
    assert build["category"] == "conditional-no-index-entity"
    assert build["decision"]["status"] == "held"
    assert build["raw"]["indexExactLineNameCount"] == 0
    assert build["raw"]["cursorResult"] == "Unable to resolve cursor info."
    assert build["compilerConditionalControl"]["probeResult"] == "selected=active"
    def check_receipts(value):
        if isinstance(value, dict):
            if "path" in value and "sha256" in value:
                assert digest(resolve(value["path"])) == value["sha256"]
            if "exitCode" in value:
                assert isinstance(value["exitCode"], int)
            for nested in value.values():
                check_receipts(nested)
        elif isinstance(value, list):
            for nested in value:
                check_receipts(nested)
    check_receipts(payload["inputs"])
    check_receipts(payload["rows"])
    print("edge evidence assertions passed")


if __name__ == "__main__":
    main()
