"""Add reviewed public-source USRs to a versioned copy of the base catalogue.

This module deliberately separates compiler-proof replay from catalogue merging.
The production entry point must call the pinned proof validator first, then pass
its independently reconstructed resolution to :func:`merge_catalogue`.
"""
from __future__ import annotations

from copy import deepcopy
from collections import Counter
from datetime import datetime, timezone
import hashlib
import importlib.util
import inspect
import json
import os
import re
from pathlib import Path
import sys
import tempfile
from typing import Any, Iterable, Mapping

from factory.core.artifacts import canonical_hash, provenance
from factory.tools.canonical_json import dump_bytes
from factory.tools.schema_validate import load_registry, validate_artifact


BASE_CATALOGUE_SHA256 = "sha256:740f000fd0b389d0c0fee5455f9f3b4285da75c50f9e3f0ba01a5963ca7f5270"
BASE_SOURCE_SHA256 = "sha256:48a54bd1cb7afdb3b878f95c2fcc6f07b45f629862a3f97911079b36b17259bf"
BASE_CATALOGUE_ID = "sdk.macos27.swiftui"
IMMUTABLE_LINK_SHA256 = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
GRAPH_USR_SET_KEY = "rawGraphUsrSetSha256"
EXPECTED_PROOF_STATUS = "complete-source-public-api-accounting"
SOURCE_MODULES = {"SwiftUI", "SwiftUICore"}
SOURCE_INTERFACE = "arm64e-apple-macos.swiftinterface"
SOURCE_ROW_STATUSES = {
    "eligible-compiler-mapped",
    "excluded-inactive-source-branch",
    "excluded-local-declaration",
    "excluded-nonpublic-source",
    "held-special-family-access",
    "held-unresolved",
    "held-v12-start-not-reconstructed",
    "public-compiler-mapped-attributed-unavailable",
    "public-compiler-mapped-documentation-hidden",
}
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
BASE_PATH = ROOT / "factory/catalogue/evidence/catalogue.json"
LINK_PATH = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
GUARD_PATH = ROOT / "factory/catalogue/public-ancestor-spike/exact_public_ancestor.py"
# Filled only after proof source & evidence reach independent final clearance.
FINAL_GUARD_SHA256: str | None = None
FINAL_PROOF_PATH: Path | None = None
FINAL_PROOF_SHA256: str | None = None
OUTPUT_PATH = HERE / "catalogue-public-source-v1.json"

_HASH_RE = re.compile(r"sha256:[0-9a-f]{64}\Z")
_RAW_GRAPH_USR = re.compile(rb'"precise"\s*:\s*"([^"\\]*)"')


class ConsumerError(ValueError):
    """Proof or base catalogue cannot safely produce an additive catalogue."""


def _require(ok: bool, message: str) -> None:
    if not ok:
        raise ConsumerError(message)


def _digest(raw: bytes) -> str:
    return "sha256:" + hashlib.sha256(raw).hexdigest()


def raw_graph_usr_closure(link: Mapping[str, Any], root: str) -> set[str]:
    """Read exact pinned symbol graphs from immutable 836 & verify closure digest."""
    _require(link.get("kind") == "sourcekit-interface-index-link-spike", "unexpected immutable graph link kind")
    descriptors = link.get("rawGraphInputs")
    closure = link.get("rawGraphUsrClosure")
    _require(isinstance(descriptors, list) and isinstance(closure, dict), "immutable graph closure is incomplete")
    root_path = Path(root)
    usrs: set[str] = set()
    for descriptor in descriptors:
        _require(isinstance(descriptor, dict), "malformed raw graph descriptor")
        path = root_path / descriptor["path"]
        raw = path.read_bytes()
        _require(_digest(raw) == descriptor.get("sha256"), "actual raw graph bytes changed")
        usrs.update(match.group(1).decode("utf-8") for match in _RAW_GRAPH_USR.finditer(raw))
    canonical = json.dumps(sorted(usrs), separators=(",", ":")).encode()
    _require(len(usrs) == closure.get("rawGraphUsrCount"), "actual raw graph USR count changed")
    _require(_digest(canonical) == closure.get(GRAPH_USR_SET_KEY), "actual raw graph USR set changed")
    return usrs


def _source_classification(record: Mapping[str, Any]) -> tuple[str, str | None]:
    """Return strict-catalogue status & proof-provided hidden reason."""
    declarations = record.get("sourceDeclarations")
    _require(isinstance(declarations, list) and declarations, "compiler USR lacks source-declaration coverage")
    _require(all(isinstance(row, dict) for row in declarations), "malformed source declaration classification")
    _require(all(row.get("compilerPath") == record.get("path") for row in declarations),
             "same USR source declaration path disagrees with compiler owner path")
    source_statuses = {row.get("status") for row in declarations}
    _require(len(source_statuses) == 1 and None not in source_statuses,
             "same USR has mixed or missing source classifications")
    source_status = next(iter(source_statuses))
    status = record.get("status")
    if status == "inventory" and source_status == "eligible-compiler-mapped":
        return "inventory", None
    if status == "hidden" and source_status == "public-compiler-mapped-attributed-unavailable":
        reason = record.get("hiddenReason")
        _require(isinstance(reason, str) and reason, "target-unavailable row lacks proof-provided hiddenReason")
        return "hidden", reason
    if status == "hidden" and source_status == "public-compiler-mapped-documentation-hidden":
        reason = record.get("hiddenReason")
        _require(isinstance(reason, str) and reason, "documentation-private row lacks proof-provided hiddenReason")
        return "hidden", reason
    raise ConsumerError(f"unqualified compiler USR status cannot be merged: {status!r}")


def merge_catalogue(
    base: Mapping[str, Any],
    resolution: Mapping[str, Any],
    *,
    raw_graph_usrs: set[str],
    proof_hash: str,
    guard_hash: str,
    link_hash: str,
    proof_input_refs: list[dict[str, str]],
    created_at: str,
) -> dict[str, Any]:
    """Build strict-v0.1 additive catalogue from already replayed proof result.

    `resolution` is trusted only after production proof hydration/acceptance by
    the pinned guard adapter. This function still rechecks coverage, status,
    paths, graph membership, source hash, uniqueness, and unchanged base rows.
    """
    _require(_HASH_RE.fullmatch(proof_hash) is not None, "proof hash is malformed")
    _require(_HASH_RE.fullmatch(guard_hash) is not None, "guard hash is malformed")
    _require(link_hash == IMMUTABLE_LINK_SHA256, "immutable source-link artifact hash changed")
    _require(all(isinstance(row, dict) and isinstance(row.get("id"), str)
                 and _HASH_RE.fullmatch(row.get("hash", "")) for row in proof_input_refs),
             "proof input hash references are malformed")
    _require(len({row["id"] for row in proof_input_refs}) == len(proof_input_refs),
             "proof input IDs are not unique")
    _require(base.get("kind") == "catalogue" and base.get("version") == "0.1", "base is not strict catalogue v0.1")
    _require(base.get("id") == BASE_CATALOGUE_ID, "unexpected base catalogue identity")
    _require(base.get("provenance", {}).get("sourceHash") == BASE_SOURCE_SHA256, "base raw source hash changed")
    _require(canonical_hash(base) == BASE_CATALOGUE_SHA256, "base catalogue canonical hash changed")
    _require(isinstance(base.get("symbols"), list) and bool(base["symbols"]), "base catalogue has no symbols")
    _require(resolution.get("status") == EXPECTED_PROOF_STATUS, "source-accounting proof is not final/complete")
    source_rows = resolution.get("rows")
    _require(isinstance(source_rows, list), "proof has no complete source-start rows")
    _require(len(source_rows) == resolution.get("fullSourceDeclarationStarts"),
             "source-start denominator does not match source rows")
    for row in source_rows:
        _require(isinstance(row, dict), "source-start row is malformed")
        key = row.get("key")
        _require(isinstance(key, list) and len(key) == 4, "source-start key must have exactly four fields")
        _require(isinstance(key[0], str) and key[0] in SOURCE_MODULES
                 and isinstance(key[1], str) and key[1] == SOURCE_INTERFACE,
                 "source-start key has unknown module/interface")
        _require(type(key[2]) is int and key[2] > 0 and isinstance(key[3], str) and bool(key[3]),
                 "source-start key has invalid line/name")
        _require(type(row.get("lineageV12")) is bool, "source lineage marker must be boolean")
        _require(row.get("status") in SOURCE_ROW_STATUSES, "source-start status is unknown")
    counted_statuses = Counter(row.get("status") for row in source_rows if isinstance(row, dict))
    _require(len(counted_statuses) > 0 and sum(counted_statuses.values()) == len(source_rows),
             "source-start rows are malformed or unclassified")
    _require(dict(sorted(counted_statuses.items())) == resolution.get("byStatus"),
             "source-start status totals do not match full denominator")
    _require(not any(str(status).startswith("held-") or status == "held-unresolved" for status in counted_statuses),
             "source-accounting proof retains held source starts")
    _require(resolution.get("unreconstructedV12Starts") == 0, "proof has unreconstructed v12 declaration starts")
    _require(resolution.get("v12DeclarationStarts") == 12635, "v12 declaration denominator changed")
    expected_lineage = sum(bool(row.get("lineageV12")) for row in source_rows)
    expected_additions = sum(not bool(row.get("lineageV12")) for row in source_rows)
    _require(expected_lineage == resolution.get("v12DeclarationStarts"), "v12 source-lineage coverage changed")
    _require(expected_additions == resolution.get("addedSourceDeclarationStarts"), "new source-start denominator changed")
    _require(len({tuple(row.get("key", [])) for row in source_rows}) == len(source_rows),
             "source-start keys are duplicated or malformed")
    public = resolution.get("publicCompilerCatalogue")
    _require(isinstance(public, list), "proof has no public compiler catalogue")
    _require(resolution.get("publicCompilerCatalogueUsrCount") == len(public), "proof USR denominator mismatch")

    base_symbols = base["symbols"]
    base_by_usr: dict[str, Mapping[str, Any]] = {}
    for symbol in base_symbols:
        _require(isinstance(symbol, dict), "base symbol is not an object")
        usr = symbol.get("usr")
        _require(isinstance(usr, str) and usr, "base symbol lacks USR")
        _require(usr not in base_by_usr, f"base catalogue repeats USR {usr!r}")
        base_by_usr[usr] = symbol

    proof_by_usr: dict[str, Mapping[str, Any]] = {}
    expected_public: dict[str, list[dict[str, Any]]] = {}
    public_source_statuses = {
        "eligible-compiler-mapped",
        "public-compiler-mapped-attributed-unavailable",
        "public-compiler-mapped-documentation-hidden",
    }
    for source_row in source_rows:
        usr = source_row.get("usr")
        if usr is None:
            continue
        _require(isinstance(usr, str) and usr, "source row has a malformed compiler USR")
        _require(source_row.get("status") in public_source_statuses,
                 "compiler USR occurs on an unqualified source classification")
        projected = {
            "sourceKey": source_row.get("key"),
            "compilerPath": source_row.get("compilerPath"),
            "status": source_row.get("status"),
            "kind": source_row.get("kind"),
            "ancestor": source_row.get("owner"),
            "accessRule": source_row.get("accessRule"),
            "restrictions": source_row.get("attributedRestrictions", []),
        }
        _require(isinstance(projected["compilerPath"], str) and projected["compilerPath"],
                 "compiler-backed source row lacks canonical compiler path")
        expected_public.setdefault(usr, []).append(projected)

    additions: list[dict[str, str]] = []
    for row in public:
        _require(isinstance(row, dict), "proof catalogue row is malformed")
        usr, path = row.get("usr"), row.get("path")
        _require(isinstance(usr, str) and usr and isinstance(path, str) and path,
                 "proof row lacks exact compiler USR/path")
        _require(usr not in proof_by_usr, f"proof repeats compiler USR {usr!r}")
        proof_by_usr[usr] = row
        _require(row.get("compilerEvidencePresent") is True, "proof row lacks compiler evidence")
        _require(row.get("precise", usr) == usr, "proof USR/precise identity mismatch")
        _require(row.get("sourceDeclarations") == expected_public.get(usr),
                 f"public USR source coverage differs from complete source rows: {usr}")
        _require(row.get("path") == row["sourceDeclarations"][0].get("compilerPath"),
                 f"public USR path differs from compiler source rows: {usr}")
        graph_present = usr in raw_graph_usrs
        _require(row.get("graphPresent") is graph_present, f"proof/raw graph membership mismatch for {usr}")
        if graph_present:
            _require(usr in base_by_usr, f"graph-present proof USR missing from immutable base: {usr}")
            continue
        _require(usr not in base_by_usr, f"graph-absent proof USR already occurs in base: {usr}")
        status, hidden_reason = _source_classification(row)
        entry = {"usr": usr, "precise": usr, "path": path, "status": status}
        if hidden_reason is not None:
            entry["hiddenReason"] = hidden_reason
        additions.append(entry)

    _require(resolution.get("graphAbsentPublicCompilerUsrCount") == len(additions),
             "graph-absent addition count does not match full proof accounting")
    expected_graph_overlap = sum(1 for row in public if row["usr"] in raw_graph_usrs)
    if "graphPresentPublicCompilerUsrCount" in resolution:
        _require(resolution.get("graphPresentPublicCompilerUsrCount") == expected_graph_overlap,
                 "graph-present proof count does not match raw graph closure")
    _require(len(proof_by_usr) == len(public), "proof USR coverage is not unique")
    _require(set(proof_by_usr) == set(expected_public), "public compiler USR coverage has omissions or extra entries")

    # Copy base dictionaries exactly; append only new compiler-backed USRs.
    symbols = deepcopy(base_symbols) + sorted(additions, key=lambda row: row["usr"])
    _require(symbols[:len(base_symbols)] == base_symbols, "base symbol rows changed during merge")
    artifact = {
        "kind": "catalogue",
        "version": "0.1",
        "id": "sdk.macos27.swiftui.public-source-v1",
        "provenance": provenance(
            canonical_hash(resolution),
            [
                {"id": BASE_CATALOGUE_ID, "hash": BASE_CATALOGUE_SHA256},
                {"id": "public-ancestor-proof-v1", "hash": proof_hash},
                {"id": "public-ancestor-guard-v1", "hash": guard_hash},
                {"id": "immutable-sourcekit-links-836", "hash": link_hash},
                *proof_input_refs,
            ],
            producer="factory/catalogue/public-ancestor-consumer",
            created_at=created_at,
        ),
        "symbolGraph": deepcopy(base["symbolGraph"]),
        "symbols": symbols,
    }
    _require(artifact["symbolGraph"] == base["symbolGraph"], "base graph metadata changed")
    errors = validate_artifact(artifact, *load_registry(Path(__file__).resolve().parents[2] / "spec" / "schema"))
    _require(not errors, "merged catalogue failed schema validation: " + "; ".join(errors))
    return artifact


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def proof_hash_refs(value: Any) -> list[dict[str, str]]:
    """Retain every sha256-valued proof dependency field in output provenance."""
    refs: list[dict[str, str]] = []

    def visit(item: Any, pointer: str) -> None:
        if isinstance(item, dict):
            for key, child in item.items():
                child_pointer = f"{pointer}/{key.replace('~', '~0').replace('/', '~1')}"
                if isinstance(child, str) and _HASH_RE.fullmatch(child):
                    token = hashlib.sha256(child_pointer.encode()).hexdigest()[:20]
                    refs.append({"id": "proof-input-" + token, "hash": child})
                else:
                    visit(child, child_pointer)
        elif isinstance(item, list):
            for index, child in enumerate(item):
                visit(child, f"{pointer}/{index}")

    visit(value, "proof")
    return refs


def _load_pinned_guard(path: Path, expected_sha256: str):
    _require(_HASH_RE.fullmatch(expected_sha256) is not None, "guard pin is missing or malformed")
    _require(_digest(path.read_bytes()) == expected_sha256, "frozen production proof guard changed")
    sys.dont_write_bytecode = True
    inserted = str(path.parent)
    sys.path.insert(0, inserted)
    try:
        parser_path = path.parent / "lexical_model_v2.py"
        parser_sha = _digest(parser_path.read_bytes())
        parser_spec = importlib.util.spec_from_file_location("lexical_model_v2", parser_path)
        _require(parser_spec is not None and parser_spec.loader is not None,
                 "cannot load final proof guard's exact lexical parser")
        parser_module = importlib.util.module_from_spec(parser_spec)
        sys.modules["lexical_model_v2"] = parser_module
        parser_spec.loader.exec_module(parser_module)
        spec = importlib.util.spec_from_file_location("public_ancestor_final_proof_guard", path)
        _require(spec is not None and spec.loader is not None, "cannot load final production proof guard")
        module = importlib.util.module_from_spec(spec)
        sys.modules[spec.name] = module
        spec.loader.exec_module(module)
        _require(getattr(module, "LEXICAL_HASH", None) == parser_sha,
                 "proof guard/parser source bytes disagree")
        _require(callable(getattr(module, "load_artifact", None)), "production proof guard has no pinned loader")
        return module
    finally:
        if sys.path and sys.path[0] == inserted:
            sys.path.pop(0)


def build_final_candidate(*, created_at: str | None = None) -> tuple[dict[str, Any], str]:
    """Replay frozen proof guard, then atomically write final versioned candidate.

    The three final pin constants remain unset until proof and guard freeze.
    Calling this before independent proof clearance fails closed.
    """
    _require(FINAL_GUARD_SHA256 is not None and FINAL_PROOF_PATH is not None and FINAL_PROOF_SHA256 is not None,
             "final proof/guard pins have not been cleared")
    _require(isinstance(created_at, str) and bool(created_at),
             "reviewed createdAt must be supplied explicitly for reproducible candidate bytes")
    _require(_digest(BASE_PATH.read_bytes()) == BASE_CATALOGUE_SHA256, "actual base catalogue bytes changed")
    base = json.loads(BASE_PATH.read_text(encoding="utf-8"))
    link_raw = LINK_PATH.read_bytes()
    link_hash = _digest(link_raw)
    _require(link_hash == IMMUTABLE_LINK_SHA256, "immutable source-link artifact changed")
    link = json.loads(link_raw)
    graph_usrs = raw_graph_usr_closure(link, str(ROOT))

    proof_raw = FINAL_PROOF_PATH.read_bytes()
    proof_hash = _digest(proof_raw)
    _require(proof_hash == FINAL_PROOF_SHA256, "final proof artifact bytes changed")
    guard = _load_pinned_guard(GUARD_PATH, FINAL_GUARD_SHA256)
    loader = guard.load_artifact
    signature = inspect.signature(loader)
    pin_parameters = [name for name in ("trusted_final_sha256", "expected_sha256") if name in signature.parameters]
    _require(len(pin_parameters) == 1, "production proof loader has no unique trusted final hash parameter")
    replay = loader(FINAL_PROOF_PATH, **{pin_parameters[0]: FINAL_PROOF_SHA256})
    _require(isinstance(replay, tuple) and len(replay) == 2, "production proof loader result shape changed")
    _validator, proof = replay  # load_artifact independently accepts the full source proof before returning.
    _require(isinstance(proof, dict) and isinstance(proof.get("resolution"), dict),
             "production proof loader returned no accepted resolution")
    resolution = proof["resolution"]
    refs = proof_hash_refs(proof)
    artifact = merge_catalogue(
        base,
        resolution,
        raw_graph_usrs=graph_usrs,
        proof_hash=proof_hash,
        guard_hash=FINAL_GUARD_SHA256,
        link_hash=link_hash,
        proof_input_refs=refs,
        created_at=created_at,
    )
    actual_hash = write_candidate_atomic(OUTPUT_PATH, artifact)
    return artifact, actual_hash


def write_candidate_atomic(path: str | Path, artifact: Mapping[str, Any]) -> str:
    """Schema-check & atomically replace a candidate in this owned folder."""
    destination = Path(path)
    folder = Path(__file__).resolve().parent
    _require(destination.resolve().is_relative_to(folder), "candidate output must remain in consumer-owned folder")
    value = dict(artifact)
    errors = validate_artifact(value, *load_registry(Path(__file__).resolve().parents[2] / "spec" / "schema"))
    _require(not errors, "candidate failed schema validation: " + "; ".join(errors))
    payload = dump_bytes(value)
    destination.parent.mkdir(parents=True, exist_ok=True)
    fd, temp_name = tempfile.mkstemp(prefix=f".{destination.name}.", suffix=".tmp", dir=destination.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(payload)
            stream.flush()
            os.fsync(stream.fileno())
        reparsed = json.loads(Path(temp_name).read_text(encoding="utf-8"))
        _require(reparsed == value, "temporary artifact readback changed candidate")
        errors = validate_artifact(reparsed, *load_registry(Path(__file__).resolve().parents[2] / "spec" / "schema"))
        _require(not errors, "temporary artifact failed schema validation: " + "; ".join(errors))
        os.replace(temp_name, destination)
        return _digest(payload)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)
