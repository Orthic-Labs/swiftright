#!/usr/bin/env python3
"""Compare one exact F1 catalogue against frozen v1 USR membership."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.metadata
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
V1 = ROOT / "factory/registry/public-source-binding-v1"
V2 = ROOT / "factory/registry/public-source-binding-v2"
FROZEN_MANIFEST_SHA = "sha256:7a2e80bf7ce132955e46b676c4818f96bfaebde279f5d5a4868da5d3bb482cf1"
FROZEN_EXPECTED_SHA = "sha256:f1d482a89d7d09d741cb3dc0d49fc6532cb06a758a28c27efd09836f17728af3"
EXPECTED_PYTHON = "sha256:4f00ea2ad53d62437a6a3946b73c73614a97e8accdc5b96dc095ea1a0d9c6a56"
PINNED_FILES = {
    "factory/registry/__init__.py": "sha256:d667b883cc9f684936734f6c22cf2e4fe89db86c94e366967ee0545be0c95303",
    "factory/registry/registry.py": "sha256:247095ac42999371eae5505fff1a2aedbb5fe9d3381b22f127dc69c10e104650",
    "factory/core/__init__.py": "sha256:990ea4b72244daf1096c456cc17e5247c52c2be8493859caedd50dc1acc76bd7",
    "factory/core/artifacts.py": "sha256:09adfc326184bf40628160138aa58ba3a23285937739f8b0cb3849378bc134b5",
    "factory/tools/__init__.py": "sha256:fef7e1e1d528fd0edad1a29d57036c54e27cb4ff533d7fd4addb23a59edc9ff1",
    "factory/tools/canonical_json.py": "sha256:af8e5f4e1c0ba38e701120d70417f4beec769c6f9a82694ebb63c92283050267",
    "factory/tools/schema_validate.py": "sha256:5e24c0afd026f7189b32cb948c529ff6244dc1dac41aede071aff3b5f3d53246",
    "factory/spec/schema/block-registry.schema.json": "sha256:a2bfc9ce81c210a7f0ad08b4c3569c54e36cd2354f32140756621b671d98a75c",
    "factory/spec/schema/capability-obligations.schema.json": "sha256:fdbd5b81897bc7dcbf66b75cb1582c3073fe0787077dfa251e55be55e313a9b9",
    "factory/spec/schema/capture.schema.json": "sha256:ed5bd1604a4e5cf6c913035c94ad2daaac9ccd152421f01a449959a80d59eee2",
    "factory/spec/schema/case.schema.json": "sha256:a83c56b8d30a6311be0e66c57421d64f39d03c56436e463b5345be736c92106f",
    "factory/spec/schema/catalogue.schema.json": "sha256:afe47e75eba9ef89c6a2b4f3cd9b29c1d07038e54a82c3cc7bed0f558043b499",
    "factory/spec/schema/common.schema.json": "sha256:d319f074f346ab0bbf15a91ff0d860aff80eeaa78ceb9486154f74faea60e6a6",
    "factory/spec/schema/receipt.schema.json": "sha256:566d0af0f2d4d8671f848eb5667d0d4abfcb2227877e815abd5d07134083dca6",
    "factory/spec/schema/recipe.schema.json": "sha256:f40e83f7b2f07ed251a74cd79b858764fe9e1ac634d4a3d6dc47bed97e58df51",
    "factory/spec/schema/ticket.schema.json": "sha256:4d8f4430f7506530ff4f4ecd09ab8c1747145118d47096ad864514a81363b986",
    "factory/spec/schema/verdict.schema.json": "sha256:87d2441f61689126835a1dd3634923598c71754fe9693b0fd515dfc52b9eeba5",
    "factory/spec/schema/waiver.schema.json": "sha256:5f8778e07e657b9f3348b5fb9f42e92d063556bb377a2d64b95146b7f3ff59df",
}

def digest_bytes(value: bytes) -> str:
    return "sha256:" + hashlib.sha256(value).hexdigest()

def digest_file(path: Path) -> str:
    return digest_bytes(path.read_bytes())

def repo_path(path: Path) -> str:
    path = path.resolve()
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)

def verify_dependencies() -> None:
    executable = Path(sys.executable).resolve()
    if digest_file(executable) != EXPECTED_PYTHON:
        raise SystemExit(f"python executable hash mismatch: {executable}")
    for relative, expected in PINNED_FILES.items():
        path = ROOT / relative
        if not path.is_file() or digest_file(path) != expected:
            raise SystemExit(f"pinned dependency mismatch: {relative}")
    if digest_file(V1 / "manifest-usr-v1.json") != FROZEN_MANIFEST_SHA:
        raise SystemExit("frozen manifest bytes mismatch")
    if digest_file(V1 / "expected-registry-membership.json") != FROZEN_EXPECTED_SHA:
        raise SystemExit("frozen expected membership bytes mismatch")
    if importlib.metadata.version("jsonschema") != "4.25.1":
        raise SystemExit("jsonschema version mismatch")
    if importlib.metadata.version("referencing") != "0.37.0":
        raise SystemExit("referencing version mismatch")

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("catalogue", type=Path)
    parser.add_argument("--output", type=Path, required=True,
                        help="new non-existing versioned receipt")
    args = parser.parse_args()
    verify_dependencies()
    candidate = args.catalogue.resolve()
    output = args.output.resolve()
    reserved = {
        V1 / "final-candidate-resolution.json",
        V1 / "archive-manifest.json",
        V2 / "archive-manifest.json",
    }
    if output.exists():
        raise SystemExit(f"output must not already exist: {output}")
    if output in reserved:
        raise SystemExit(f"reserved output path: {output}")
    if output == candidate:
        raise SystemExit("output cannot replace candidate")
    raw = candidate.read_bytes()
    candidate_hash = digest_bytes(raw)
    try:
        catalogue = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SystemExit(f"candidate is not UTF-8 JSON: {exc}") from exc
    if not isinstance(catalogue, dict) or catalogue.get("kind") != "catalogue" or catalogue.get("version") != "0.1":
        raise SystemExit("candidate must be a v0.1 catalogue")
    if not isinstance(catalogue.get("symbols"), list):
        raise SystemExit("candidate must contain symbols array")

    sys.path.insert(0, str(ROOT))
    from factory.tools.schema_validate import load_registry, validate_artifact
    schema_registry, schema_documents = load_registry(ROOT / "factory/spec/schema")
    errors = validate_artifact(
        catalogue, schema_registry, schema_documents,
        "https://swiftright.dev/factory/spec/v0.1/catalogue.schema.json",
    )
    if errors:
        raise SystemExit("candidate catalogue schema errors: " + "; ".join(errors))
    from factory.registry.registry import build_registry

    manifest_path = V1 / "manifest-usr-v1.json"
    expected_path = V1 / "expected-registry-membership.json"
    manifest_raw = manifest_path.read_bytes()
    expected_raw = expected_path.read_bytes()
    manifest = json.loads(manifest_raw.decode("utf-8"))
    expected = json.loads(expected_raw.decode("utf-8"))
    selectors = [selector for block in manifest.get("blocks", []) for selector in block.get("symbols", [])]
    expected_rows = [
        {"blockId": block["id"], "symbolIndex": index, "usr": selector[4:]}
        for block in manifest["blocks"] for index, selector in enumerate(block["symbols"])
    ]
    if manifest.get("version") != "0.1" or len(manifest["blocks"]) != 10 or len(selectors) != 65:
        raise SystemExit("frozen manifest must contain exact ten blocks & 65 selectors")
    if any(not isinstance(selector, str) or not selector.startswith("usr:") for selector in selectors):
        raise SystemExit("frozen manifest selectors must all be exact USRs")
    if expected.get("kind") != "f2-public-source-binding-membership" or expected.get("version") != 1:
        raise SystemExit("frozen expected membership schema mismatch")
    if len(expected.get("blocks", [])) != 65 or expected["blocks"] != expected_rows:
        raise SystemExit("frozen expected membership expansion mismatch")
    artifact = build_registry(
        catalogue, manifest=manifest, created_at="2026-10-11T00:00:00Z",
        producer="factory/registry/public-source-binding-v2/comparator-guard-v1",
    )
    got = [
        {"blockId": block["id"], "symbolIndex": index, "usr": usr}
        for block in artifact["blocks"] for index, usr in enumerate(block["symbols"])
    ]
    want = expected["blocks"]
    block_count = len(artifact["blocks"]) == len(manifest["blocks"])
    membership = got == want
    status = "stable-membership" if block_count and membership else "membership-drift-held"
    receipt = {
        "kind": "f2-public-source-binding-final-candidate-comparison",
        "version": 2,
        "status": status,
        "candidate": {"path": repo_path(candidate), "absolutePath": str(candidate), "sha256": candidate_hash,
                       "kind": catalogue["kind"], "schemaVersion": catalogue["version"],
                       "rawBytes": len(raw), "symbolCount": len(catalogue["symbols"])},
        "manifest": {"path": repo_path(manifest_path), "sha256": digest_bytes(manifest_raw),
                     "selectorCount": sum(len(block["symbols"]) for block in manifest["blocks"]),
                     "blockCount": len(manifest["blocks"])},
        "expectedMembershipPath": repo_path(expected_path),
        "expectedMembershipSha256": digest_bytes(expected_raw),
        "frozenInputs": {"manifestRawBytes": len(manifest_raw), "expectedMembershipRawBytes": len(expected_raw), "manifestSha256": FROZEN_MANIFEST_SHA, "expectedMembershipSha256": FROZEN_EXPECTED_SHA},
        "actualBlockCount": len(artifact["blocks"]), "expectedBlockCount": len(manifest["blocks"]),
        "actualMembershipCount": len(got), "expectedMembershipCount": len(want),
        "membershipEqual": membership, "blockCountEqual": block_count,
        "dependencyPins": {"python": EXPECTED_PYTHON, "files": PINNED_FILES,
                            "jsonschema": "4.25.1", "referencing": "0.37.0"},
        "createdAt": datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z"),
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(receipt, indent=2))
    return 0 if status == "stable-membership" else 2

if __name__ == "__main__":
    raise SystemExit(main())
