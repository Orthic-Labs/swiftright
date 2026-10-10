"""V12 bounded inactive-conditional exclusion layered over immutable v11."""
from __future__ import annotations

import copy
import hashlib
import importlib.util
import json
import sys
from functools import lru_cache
from pathlib import Path
from typing import Any

from factory.core import artifacts
from .audit_v11 import _require_hash

ROOT = Path(__file__).resolve().parents[2]
V11_PATH = "factory/catalogue/evidence/interface-audit-v11-candidate.json"
V11_FILE_SHA256 = "sha256:c1af919cab46ad5d23f608dc0e13353dee938e39fbbfba8ea89e326128ff21c0"
V11_AUDIT_HASH = "sha256:750a14d394870740722f4de9db9e624a2263737d12215a735f77b49d1b9ab0c8"
V11_SOURCE_SHA256 = "sha256:6a83860188552f7af38e14181f57d3577b3f1937bd60d4ea5b5636a3d839db32"
V11_TEST_SHA256 = "sha256:393a43547404e97967410cb70ba80bc19dd0f48b4748cfa6d0c06969f2d69b80"
INACTIVE_DIR = "factory/catalogue/inactive-branch-spike"
INACTIVE_GUARD_SHA256 = "sha256:e5712b0f0f265e350f27fc3ab13416028c1494f55dd1e465f1ce1dc72c583ff5"
INACTIVE_GENERATOR_SHA256 = "sha256:aa4f40c20ee779e7f442508d3bf11f2cf3978db178a689c56e223f407b58adcd"
INACTIVE_TEST_SHA256 = "sha256:b86716108f6ee6d0ca68b89d75d010cfb2218edf1ad95205d8db1b48bcdaefe1"
INACTIVE_EVIDENCE_SHA256 = "sha256:b060ebb3789fa5685e80341fcf8ad2f92fb518bda4c1e3202f1e063066a01474"
PROCESS_SHA256 = "sha256:080c27afbf7ee3cb43a4b1426ee4b4cc9ffcd32d16f29e05dfd8c8e47c8aa484"
TREES_SHA256 = "sha256:04922a8787fabca47ba720cca11b34952f459c0c9373c171ee1ac183f8cc951c"
HELPER_SHA256 = "sha256:83c3500b32658fdb3b075a2a96f5e0d781711e802e29c620e50aa6f3a73883a5"
LINK_SHA256 = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
INACTIVE_KEY = ["SwiftUI", "arm64e-apple-macos.swiftinterface", 28491, "buildLimitedAvailability"]


def _load_v11(root: Path) -> dict[str, Any]:
    _require_hash(root / "factory/catalogue/audit_v11.py", V11_SOURCE_SHA256, "v11 source")
    _require_hash(root / "factory/catalogue/test_audit_v11.py", V11_TEST_SHA256, "v11 test")
    path = root / V11_PATH
    _require_hash(path, V11_FILE_SHA256, "v11 candidate")
    value = json.loads(path.read_text(encoding="utf-8"))
    body = dict(value)
    declared = body.pop("auditHash", None)
    if declared != V11_AUDIT_HASH or artifacts.canonical_hash(body) != declared:
        raise ValueError("v11 canonical audit hash differs from frozen candidate")
    return value


def _inactive_paths(root: Path) -> dict[str, str]:
    base = root / INACTIVE_DIR
    return {
        "exact_inactive_validator.py": INACTIVE_GUARD_SHA256,
        "investigate_inactive_branch.py": INACTIVE_GENERATOR_SHA256,
        "test_inactive_branch.py": INACTIVE_TEST_SHA256,
        "inactive-branch-evidence.json": INACTIVE_EVIDENCE_SHA256,
        "actual-process-results-v2.json": PROCESS_SHA256,
        "swift-demangle-inactive-expand-v2.txt": TREES_SHA256,
        "inline-always-conditional-probe.swift": "sha256:969621f5a426e0c512f83e9b25cfb2cdb0193b32e7b75fa0faae7fecdf4a5ec7",
    }


@lru_cache(maxsize=1)
def _load_inactive_guard(root_text: str):
    root = Path(root_text)
    folder = root / INACTIVE_DIR
    guard_path = folder / "exact_inactive_validator.py"
    _require_hash(guard_path, INACTIVE_GUARD_SHA256, "inactive production validator")
    helper_path = root / "factory/catalogue/module-provenance-spike/exact_validator.py"
    _require_hash(helper_path, HELPER_SHA256, "frozen inactive parser helper")
    sys.path.insert(0, str(folder))
    try:
        spec = importlib.util.spec_from_file_location("_sr1_v12_inactive_guard", guard_path)
        if spec is None or spec.loader is None:
            raise ValueError("cannot load pinned inactive-branch validator")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        sys.path.remove(str(folder))


def _reconstruct_inactive_evidence(evidence: dict[str, Any], validator) -> dict[str, Any]:
    if evidence.get("version") != 2 or evidence.get("status") != "review-only-exact-inactive-compiler-branch":
        raise ValueError("inactive branch evidence version/status differs from reviewed snapshot")
    for descriptor in evidence.get("inputs", {}).values():
        input_path = Path(descriptor["path"])
        if artifacts.file_hash(input_path) != descriptor["sha256"]:
            raise ValueError("inactive evidence input bytes differ: " + str(input_path))
    reconstructed = validator.validate()
    if reconstructed != evidence.get("resolution"):
        raise ValueError("independent inactive resolution differs from frozen evidence")
    controls = evidence.get("controls", [])
    if len(controls) < 60 or any(not item.get("baselineAccepted") or not item.get("bytesDiffer")
                                 or not item.get("rejected")
                                 or item.get("beforeSha256") == item.get("afterSha256")
                                 for item in controls):
        raise ValueError("inactive artifact lacks reviewed nonvacuous production fault replay")
    return reconstructed


def _validate_inactive(root: Path, v11: dict[str, Any]) -> dict[str, Any]:
    folder = root / INACTIVE_DIR
    paths = _inactive_paths(root)
    for name, expected in paths.items():
        _require_hash(folder / name, expected, "inactive evidence input " + name)
    _require_hash(root / "factory/catalogue/compiler-cursor-spike/link-evidence.json", LINK_SHA256,
                  "immutable compiler-link evidence")
    helper_path = root / "factory/catalogue/module-provenance-spike/exact_validator.py"
    _require_hash(helper_path, HELPER_SHA256, "frozen inactive parser helper")

    payload_path = folder / "inactive-branch-evidence.json"
    evidence = json.loads(payload_path.read_text(encoding="utf-8"))
    guard = _load_inactive_guard(str(root))
    validator = guard.Validator()
    reconstructed = _reconstruct_inactive_evidence(evidence, validator)

    rows = [row for row in v11["declarations"] if
            (row.get("module"), row.get("interface"), row.get("line"), row.get("name")) == tuple(INACTIVE_KEY)]
    if len(rows) != 1:
        raise ValueError("inactive evidence does not join to exactly one v11 interface row")
    row = rows[0]
    if (row.get("classification") != "ambiguous-context-signature"
            or row.get("signature") != reconstructed["signature"]
            or row.get("context") != reconstructed["ownerPath"]
            or row.get("sourceKitEvidence", {}).get("reason") != "no-compiler-record-at-interface-line-and-name"
            or row.get("sourceKitEvidence", {}).get("interfaceSha256") != validator.pins["source"]
            or row.get("sourceKitEvidence", {}).get("linkEligibility") is not False):
        raise ValueError("inactive branch evidence does not join to exact held v11 source row")
    if (reconstructed.get("key") != INACTIVE_KEY
            or reconstructed.get("status") != "exact-inactive-compiler-branch"
            or reconstructed.get("inactiveRawEntityCount") != 0
            or reconstructed.get("activeLine") != 28484
            or reconstructed.get("decision") != "bounded inactive-else exclusion for exact source/compiler/target only; graph overloads remain ambiguous"):
        raise ValueError("inactive compiler resolution identity/decision changed")
    return {"evidence": evidence, "resolution": reconstructed, "row": row,
            "validator": validator, "inputHashes": paths}


def build_audit_v12(*, root: Path = ROOT) -> dict[str, Any]:
    root = Path(root)
    v11 = _load_v11(root)
    inactive = _validate_inactive(root, v11)
    declarations = copy.deepcopy(v11["declarations"])
    target_rows = [row for row in declarations if
                   (row.get("module"), row.get("interface"), row.get("line"), row.get("name")) == tuple(INACTIVE_KEY)]
    if len(target_rows) != 1:
        raise ValueError("inactive exclusion row cardinality changed during v11 copy")
    target = target_rows[0]
    target["classification"] = "inactive-compiler-conditional"
    target["sourceKitEvidence"]["reason"] = "exact-inactive-compiler-conditional"
    target["inactiveCompilerEvidence"] = {
        "path": f"{INACTIVE_DIR}/inactive-branch-evidence.json",
        "sha256": INACTIVE_EVIDENCE_SHA256,
        "validatorSha256": INACTIVE_GUARD_SHA256,
        "generatorSha256": INACTIVE_GENERATOR_SHA256,
        "frozenParserHelperSha256": HELPER_SHA256,
        "immutableLinkEvidenceSha256": LINK_SHA256,
        "decision": inactive["resolution"]["decision"],
        "inactiveRawEntityCount": 0,
        "activeLine": inactive["resolution"]["activeLine"],
        "compilerSelection": inactive["resolution"]["processResults"]["run"]["stdout"].strip(),
        "graphCandidateUsrs": sorted(symbol["identifier"]["precise"]
                                      for symbol in inactive["resolution"]["symbolGraphCandidates"]),
        "graphCandidateStatus": "remains-ambiguous-not-linked",
    }

    from collections import Counter
    counts = Counter(row["classification"] for row in declarations)
    residual_classes = {"unexplained", "ambiguous-context-signature", "active-compiler-conditional-unmapped"}
    active_remaining = sum(counts[name] for name in residual_classes)
    if active_remaining != 0:
        raise ValueError("v12 expected one reviewed inactive row, but active unexplained rows remain")

    payload = copy.deepcopy(v11)
    payload.pop("auditHash", None)
    payload.update({
        "version": 12,
        "status": "incomplete-v12-one-inactive-branch-excluded-public-ancestor-eligibility-unproven",
        "method": v11["method"] + " V12 classifies exactly one compiler-proven inactive #else declaration as inactive-compiler-conditional; it is neither an exact USR link nor a hidden-attribute row. All 2,548 prior exact compiler links remain unchanged. This bounded exclusion does not certify public-ancestor eligibility or global SDK catalogue completeness.",
        "parentAudit": {"path": V11_PATH, "fileSha256": V11_FILE_SHA256, "auditHash": V11_AUDIT_HASH},
        "declarations": declarations,
        "summary": {
            **v11["summary"],
            "exactSourceKitUsrLinks": v11["summary"]["exactSourceKitUsrLinks"],
            "heldSourceKitRows": v11["summary"]["heldSourceKitRows"] - 1,
            "inactiveExcludedInterfaceRows": 1,
            "remainingActiveUnmappedAmbiguousOrUnexplained": active_remaining,
            "heldSourceKitReasons": {},
            "byClassification": dict(sorted(counts.items())),
        },
        "inactiveCompilerExclusionEvidence": {
            "path": f"{INACTIVE_DIR}/inactive-branch-evidence.json",
            "sha256": INACTIVE_EVIDENCE_SHA256,
            "validatorSha256": INACTIVE_GUARD_SHA256,
            "generatorSha256": INACTIVE_GENERATOR_SHA256,
            "testSha256": INACTIVE_TEST_SHA256,
            "frozenParserHelperSha256": HELPER_SHA256,
            "immutableLinkEvidenceSha256": LINK_SHA256,
            "processSnapshotSha256": PROCESS_SHA256,
            "demangleTreesSha256": TREES_SHA256,
            "controls": len(inactive["evidence"]["controls"]),
            "exclusions": 1,
            "exactLinksAdded": 0,
            "status": "independently-reconstructed-bounded-inactive-branch-exclusion",
        },
        "pendingEvidence": [{
            "kind": "public-ancestor-eligibility-and-global-interface-completeness",
            "state": "unproven",
            "detail": "The 2,548 exact compiler links plus one exact inactive-branch exclusion reconcile this v11 residual set only; they do not establish that every interface declaration has a public/open enclosing ancestor or certify complete public SDK declaration coverage.",
        }],
    })
    input_hashes = [
        {"path": V11_PATH, "hash": V11_FILE_SHA256},
        {"path": "factory/catalogue/audit_v11.py", "hash": V11_SOURCE_SHA256},
        {"path": "factory/catalogue/test_audit_v11.py", "hash": V11_TEST_SHA256},
        {"path": "factory/catalogue/audit_v12.py", "hash": artifacts.file_hash(Path(__file__))},
    ]
    input_hashes.extend({"path": item["path"], "hash": item["sha256"]}
                        for item in inactive["evidence"]["inputs"].values())
    input_hashes.extend([
        {"path": "factory/catalogue/module-provenance-spike/exact_validator.py", "hash": HELPER_SHA256},
        {"path": "factory/catalogue/compiler-cursor-spike/link-evidence.json", "hash": LINK_SHA256},
    ])
    payload["provenance"] = artifacts.provenance(V11_AUDIT_HASH, input_hashes,
        producer="sr1-factory.catalogue.audit-v12-candidate")
    payload["auditHash"] = artifacts.canonical_hash(payload)
    return payload


def digest(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    candidate = build_audit_v12()
    artifacts.write_artifact(ROOT / "factory/catalogue/evidence/interface-audit-v12-candidate.json", candidate)


if __name__ == "__main__":
    main()
