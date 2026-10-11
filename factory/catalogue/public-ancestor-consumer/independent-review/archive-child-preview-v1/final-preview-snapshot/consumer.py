"""Add reviewed public-source USRs to a versioned copy of the base catalogue.

This module deliberately separates compiler-proof replay from catalogue merging.
The production entry point must call the pinned proof validator first, then pass
its independently reconstructed resolution to :func:`merge_catalogue`.
"""
from __future__ import annotations

from copy import deepcopy
from collections import Counter
from contextlib import contextmanager, ExitStack
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
BASE_SYMBOL_COUNT = 108272
IMMUTABLE_LINK_SHA256 = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
GRAPH_ARCHIVE_READER_SHA256 = "sha256:2f6a07cd7c025449dfd9838a0b14fd71c10de94ed7f1254d5312e4c8243b8c06"
GRAPH_ARCHIVE_MANIFEST_SHA256 = "sha256:6ddc54fe90bffd954f415963450cfa04d19d94070631b88619635826ce9139e3"
GRAPH_USR_SET_KEY = "rawGraphUsrSetSha256"
EXPECTED_PROOF_STATUS = "complete-source-public-api-accounting"
SOURCE_MODULES = {"SwiftUI", "SwiftUICore"}
SOURCE_INTERFACE = "arm64e-apple-macos.swiftinterface"
SOURCE_ROW_STATUSES = {
    "eligible-compiler-mapped",
    "excluded-inactive-source-branch",
    "excluded-local-declaration",
    "excluded-nonpublic-source",
    "excluded-nonpublic-compiler-access",
    "held-special-family-access",
    "held-unresolved",
    "held-v12-start-not-reconstructed",
    "public-compiler-mapped-attributed-unavailable",
    "public-compiler-mapped-documentation-hidden",
}
COMPILER_RECORD_CATEGORIES = {
    "source-start-present",
    "source-extension-container",
    "source-generic-parameter",
    "source-property-initializer",
    "source-property-accessor",
    "held-compiler-record-without-source-start",
}
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
BASE_PATH = ROOT / "factory/catalogue/evidence/catalogue.json"
LINK_PATH = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
GRAPH_ARCHIVE_FOLDER = ROOT / "factory/catalogue/raw-symbolgraph-archive-v1"
GUARD_PATH = ROOT / "factory/catalogue/public-ancestor-spike/exact_public_ancestor.py"
# Filled only after proof source & evidence reach independent final clearance.
FINAL_GUARD_SHA256: str | None = None
FINAL_PROOF_PATH: Path | None = None
FINAL_PROOF_SHA256: str | None = None
OUTPUT_PATH = HERE / "catalogue-public-source-v1.json"
MANIFEST_PATH = HERE / "catalogue-public-source-v1.manifest.json"

_HASH_RE = re.compile(r"sha256:[0-9a-f]{64}\Z")
_RAW_GRAPH_USR = re.compile(rb'"precise"\s*:\s*"([^"\\]*)"')


class ConsumerError(ValueError):
    """Proof or base catalogue cannot safely produce an additive catalogue."""


def _require(ok: bool, message: str) -> None:
    if not ok:
        raise ConsumerError(message)


def _digest(raw: bytes) -> str:
    return "sha256:" + hashlib.sha256(raw).hexdigest()


@contextmanager
def _archive_graph_paths(link: Mapping[str, Any], root: Path):
    """Reconstruct absent original inputs with exact frozen archive reader & manifest."""
    reader_path = GRAPH_ARCHIVE_FOLDER / "archive.py"
    manifest_path = GRAPH_ARCHIVE_FOLDER / "archive-manifest.json"
    _require(_digest(reader_path.read_bytes()) == GRAPH_ARCHIVE_READER_SHA256,
             "frozen raw graph archive reader changed")
    _require(_digest(manifest_path.read_bytes()) == GRAPH_ARCHIVE_MANIFEST_SHA256,
             "frozen raw graph archive manifest changed")
    spec = importlib.util.spec_from_file_location("public_ancestor_raw_graph_archive", reader_path)
    _require(spec is not None and spec.loader is not None, "cannot load pinned raw graph archive reader")
    reader = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reader)
    link_raw = LINK_PATH.read_bytes()
    _require(_digest(link_raw) == IMMUTABLE_LINK_SHA256, "archive fallback link evidence changed")
    _require(json.loads(link_raw) == dict(link), "archive fallback link differs from immutable 836")
    Path(reader.INTERNAL_CACHE_ROOT).mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="consumer-replay-", dir=reader.INTERNAL_CACHE_ROOT) as temp_root:
        scratch = Path(temp_root) / "replay"
        paths = reader.load_archive(
            manifest_path,
            expected_manifest_sha256=GRAPH_ARCHIVE_MANIFEST_SHA256.removeprefix("sha256:"),
            link_path=LINK_PATH,
            workspace_root=root,
            scratch_root=scratch,
        )
        # Keep extraction alive while the caller consumes & hashes every path.
        yield paths


def raw_graph_usr_closure(
    link: Mapping[str, Any], root: str, *, archive_loader=None,
) -> set[str]:
    """Read exact pinned symbol graphs from 836, using lossless archive if absent.

    Existing original inputs are authoritative: a changed present file fails
    closed instead of silently switching to archived bytes.
    """
    _require(link.get("kind") == "sourcekit-interface-index-link-spike", "unexpected immutable graph link kind")
    descriptors = link.get("rawGraphInputs")
    closure = link.get("rawGraphUsrClosure")
    _require(isinstance(descriptors, list) and isinstance(closure, dict), "immutable graph closure is incomplete")
    root_path = Path(root)
    _require(all(isinstance(descriptor, dict) and isinstance(descriptor.get("path"), str)
                 and descriptor.get("path") for descriptor in descriptors),
             "malformed raw graph descriptor")
    original_paths = {descriptor["path"]: root_path / descriptor["path"] for descriptor in descriptors}
    _require(len(original_paths) == len(descriptors), "raw graph descriptor paths are duplicated")
    for descriptor in descriptors:
        original = original_paths[descriptor["path"]]
        if original.is_file():
            _require(_digest(original.read_bytes()) == descriptor.get("sha256"),
                     "present original raw graph bytes changed")
    with ExitStack() as stack:
        paths = original_paths
        if any(not path.is_file() for path in original_paths.values()):
            paths = archive_loader(descriptors) if archive_loader is not None else stack.enter_context(
                _archive_graph_paths(link, root_path)
            )
        usrs: set[str] = set()
        for descriptor in descriptors:
            _require(isinstance(descriptor, dict), "malformed raw graph descriptor")
            _require(isinstance(descriptor.get("path"), str) and descriptor["path"] in paths,
                     "archive/original graph path coverage changed")
            path = paths[descriptor["path"]]
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
        _require("hiddenReason" not in record, "inventory compiler USR carries hiddenReason")
        return "inventory", None
    if status == "hidden" and source_status == "public-compiler-mapped-attributed-unavailable":
        reason = record.get("hiddenReason")
        _require(isinstance(reason, str) and reason.startswith("macOS-unavailable: "),
                 "target-unavailable row lacks exact proof-provided hiddenReason")
        _require(any(isinstance(r, dict) and r.get("category") == "macOS-unavailable"
                     for row in declarations for r in row.get("restrictions", [])),
                 "target-unavailable row lacks exact source attribute witness")
        return "hidden", reason
    if status == "hidden" and source_status == "public-compiler-mapped-documentation-hidden":
        reason = record.get("hiddenReason")
        _require(isinstance(reason, str) and reason.startswith("documentation-hidden: "),
                 "documentation-private row lacks exact proof-provided hiddenReason")
        _require(any(isinstance(r, dict) and r.get("category") == "documentation-hidden"
                     for row in declarations for r in row.get("restrictions", [])),
                 "documentation-private row lacks exact source attribute witness")
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
                 and isinstance(row.get("hash"), str) and _HASH_RE.fullmatch(row["hash"])
                 for row in proof_input_refs),
             "proof input hash references are malformed")
    _require(len({row["id"] for row in proof_input_refs}) == len(proof_input_refs),
             "proof input IDs are not unique")
    _require(base.get("kind") == "catalogue" and base.get("version") == "0.1", "base is not strict catalogue v0.1")
    _require(base.get("id") == BASE_CATALOGUE_ID, "unexpected base catalogue identity")
    base_provenance = base.get("provenance")
    _require(isinstance(base_provenance, dict) and base_provenance.get("sourceHash") == BASE_SOURCE_SHA256,
             "base raw source hash changed")
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
    _require(resolution.get("heldReasons") == {}, "proof retains held source reasons")
    _require(resolution.get("heldNominals") == [], "proof retains unresolved nominal owners")
    _require(resolution.get("heldNominalReasons") == {}, "proof retains nominal-owner reasons")
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
    compiler_inventory = resolution.get("compilerInventory")
    compiler_categories = resolution.get("compilerRecordCategories")
    _require(isinstance(compiler_inventory, list) and isinstance(compiler_categories, dict),
             "proof lacks complete compiler-record inventory")
    _require(len(compiler_inventory) == resolution.get("compilerRecordCount"),
             "compiler-record denominator does not match raw inventory")
    _require(all(isinstance(row, dict) and row.get("category") in COMPILER_RECORD_CATEGORIES
                 for row in compiler_inventory), "compiler-record category is unknown")
    source_by_key = {tuple(row["key"]): row for row in source_rows}
    source_by_position: dict[tuple[str, int, str], list[dict[str, Any]]] = {}
    for row in source_rows:
        key = row["key"]
        normalized = key[3].strip("`").split("(", 1)[0]
        source_by_position.setdefault((key[0], key[2], normalized), []).append(row)
    public_child_groups: dict[str, dict[str, Any]] = {}
    inventory_indexes: set[tuple[str, int]] = set()
    raw_records_by_identity: dict[tuple[str, int, str, str, str], list[dict[str, Any]]] = {}
    for candidate in compiler_inventory:
        if not isinstance(candidate, dict) or not isinstance(candidate.get("name"), str):
            continue
        candidate_identity = (
            candidate.get("module"), candidate.get("line"),
            candidate["name"].strip("`").split("(", 1)[0],
            candidate.get("usr"), candidate.get("kind"),
        )
        raw_records_by_identity.setdefault(candidate_identity, []).append(candidate)
    for record in compiler_inventory:
        module = record.get("module")
        line = record.get("line")
        name = record.get("name")
        raw_index = record.get("rawEntityIndex")
        _require(module in SOURCE_MODULES and type(line) is int and line > 0
                 and type(raw_index) is int and raw_index >= 0,
                 "compiler-record source identity is malformed")
        _require(isinstance(name, str) and isinstance(record.get("usr"), str)
                 and isinstance(record.get("kind"), str), "compiler-record identity lacks name/USR/kind")
        identity = (module, raw_index)
        _require(identity not in inventory_indexes, "compiler raw entity index is duplicated")
        inventory_indexes.add(identity)
        if record.get("category") == "source-start-present":
            normalized = name.strip("`").split("(", 1)[0]
            candidates = source_by_position.get((module, line, normalized), [])
            _require(len(candidates) == 1, "compiler record does not map to one exact source-start position")
            if candidates[0].get("usr") is not None:
                _require(record.get("usr") == candidates[0].get("usr"),
                         "compiler record USR differs from its exact source-start row")
        anchor = record.get("parentAnchor")
        if anchor is not None:
            _require(isinstance(anchor, dict), "compiler child parent anchor is malformed")
            anchor_key = anchor.get("sourceKey")
            _require(isinstance(anchor_key, list) and len(anchor_key) == 4
                     and tuple(anchor_key) in source_by_key,
                     "compiler child parent anchor is absent from exact source universe")
            parent_row = source_by_key[tuple(anchor_key)]
            anchor_identity = (
                anchor_key[0], anchor_key[2], anchor_key[3].strip("`").split("(", 1)[0],
                anchor.get("usr"), anchor.get("kind"),
            )
            raw_parents = raw_records_by_identity.get(anchor_identity, [])
            _require(type(anchor.get("rawCardinality")) is int
                     and anchor["rawCardinality"] == len(raw_parents) and bool(raw_parents),
                     "compiler child parent anchor differs from exact raw compiler parent identity/cardinality")
            if parent_row.get("usr") is not None:
                _require(anchor.get("usr") == parent_row.get("usr"),
                         "compiler child parent USR differs from qualified source parent")
        if record.get("category") in {"source-generic-parameter", "source-property-initializer",
                                      "source-property-accessor"}:
            _require(anchor is not None, "compiler child record lacks exact parent anchor")
            category = record["category"]
            if category == "source-generic-parameter":
                _require(record.get("kind") == "source.lang.swift.decl.generic_type_param",
                         "generic-parameter compiler record has wrong raw kind")
            elif category == "source-property-accessor":
                _require(record.get("kind") in {
                    "source.lang.swift.decl.function.accessor.getter",
                    "source.lang.swift.decl.function.accessor.setter",
                }, "property-accessor compiler record has wrong raw kind")
            else:
                _require(name.startswith("init:")
                         and record.get("kind") == "source.lang.swift.decl.function.method.instance",
                         "property-initializer compiler record has wrong raw name/kind family")
        child = record.get("childEvidence")
        if record.get("category") in {"source-generic-parameter", "source-property-initializer",
                                      "source-property-accessor"}:
            _require(isinstance(child, dict), "compiler child record lacks child evidence")
        if child is None:
            continue
        _require(isinstance(child, dict), "compiler child evidence is malformed")
        child_status = child.get("status")
        _require(isinstance(child_status, str), "compiler child evidence lacks exact status")
        if child_status.startswith("held"):
            raise ConsumerError("proof retains held compiler child/component evidence")
        if anchor is not None:
            _require(child.get("parentUsr") == anchor.get("usr")
                     and child.get("parentSourceKey") == anchor.get("sourceKey"),
                     "compiler child evidence parent differs from raw inventory anchor")
        if "typedAccess" not in child:
            if child_status == "attributed-typed-parent-component":
                _require("tree" in child, "compiler component evidence omits exact typed tree")
            elif child_status == "attributed-physical-parent-component-tree-disagreement":
                _require(all(name in child for name in ("childTree", "parentTree", "typedPhysicalParent")),
                         "physical compiler component disagreement omits exact paired trees/parent")
                _require(child.get("canonicalIdentityTransferred") is False,
                         "physical compiler component disagreement transferred canonical identity")
            else:
                raise ConsumerError("compiler component evidence has unknown exact status")
            continue
        _require(child.get("typedAccess") in {"public", "open", "internal", "package",
                                               "fileprivate", "private"},
                 "compiler child has unknown typed access")
        _require(child.get("usr") == record.get("usr")
                 and child.get("kind") == record.get("kind"),
                 "typed accessor child USR/kind differs from exact raw inventory occurrence")
        child_key = child.get("parentSourceKey")
        _require(isinstance(child_key, list) and len(child_key) == 4
                 and tuple(child_key) in source_by_key,
                 "compiler child parent key is absent from exact source universe")
        parent_row = source_by_key[tuple(child_key)]
        _require(child.get("parentSourceStatus") == parent_row.get("status"),
                 "compiler child classification differs from exact parent source status")
        if child.get("typedAccess") in {"public", "open"}:
            _require(child_status == parent_row.get("status")
                     and parent_row.get("usr") == child.get("parentUsr"),
                     "public compiler child is not qualified by the same public parent API")
            _require(child_status in {
                "eligible-compiler-mapped",
                "public-compiler-mapped-attributed-unavailable",
                "public-compiler-mapped-documentation-hidden",
            }, "public compiler child status differs from qualified parent API")
            usr = child.get("usr")
            _require(isinstance(usr, str) and usr, "public compiler child lacks exact USR")
            identity = (usr, child.get("parentUsr"), tuple(child_key), child.get("kind"))
            group = public_child_groups.setdefault(usr, {
                "identity": identity, "base": deepcopy(child), "rawOccurrences": [],
            })
            _require(group["identity"] == identity and group["base"] == child,
                     "duplicate public child USR has inconsistent parent/compiler evidence")
            group["rawOccurrences"].append({
                "module": module, "rawEntityIndex": raw_index, "parentAnchor": deepcopy(anchor),
            })
        else:
            _require(child_status == "excluded-nonpublic-compiler-access",
                     "nonpublic typed compiler child has an invalid classification")
    actual_categories = Counter(row.get("category") for row in compiler_inventory if isinstance(row, dict))
    _require(sum(actual_categories.values()) == len(compiler_inventory)
             and dict(sorted(actual_categories.items())) == compiler_categories,
             "compiler-record category totals do not match raw inventory")
    _require(all(isinstance(name, str) and type(count) is int and count >= 0
                 for name, count in compiler_categories.items()), "compiler-record category counts are malformed")
    _require("held-compiler-record-without-source-start" not in actual_categories,
             "proof retains compiler records without source-start reconciliation")
    public_children = resolution.get("publicCompilerChildren")
    _require(isinstance(public_children, list)
             and resolution.get("publicCompilerChildRecordCount") == len(public_children),
             "public compiler-child denominator does not match child records")
    _require(resolution.get("heldCompilerComponentCount") == 0
             and resolution.get("heldPublicCompilerChildCount") == 0,
             "proof retains held compiler component/child evidence")
    child_key = lambda child: (child.get("usr"), child.get("parentUsr"),
                               tuple(child.get("parentSourceKey", [])), child.get("kind"))
    _require(all(isinstance(child, dict) and isinstance(child.get("usr"), str)
                 and isinstance(child.get("parentUsr"), str) for child in public_children),
             "public compiler-child identity is malformed")
    _require(len({child_key(child) for child in public_children}) == len(public_children),
             "public compiler-child identities are duplicated")
    expected_children = []
    for usr in sorted(public_child_groups):
        group = public_child_groups[usr]
        projected = group["base"]
        projected["rawCardinality"] = len(group["rawOccurrences"])
        projected["rawOccurrences"] = group["rawOccurrences"]
        expected_children.append(projected)
    _require(public_children == expected_children,
             "public compiler-child groups differ from ordered raw inventory occurrences")

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
    _require(proof.get("status") == resolution.get("status"), "outer proof status disagrees with accepted resolution")
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
    manifest = build_derivation_manifest(
        artifact, resolution, candidate_path=OUTPUT_PATH, proof_hash=proof_hash,
        guard_hash=FINAL_GUARD_SHA256, link_hash=link_hash,
        proof_input_refs=refs,
    )
    actual_hash, _manifest_hash = write_candidate_bundle_atomic(
        OUTPUT_PATH, MANIFEST_PATH, artifact, manifest,
    )
    return artifact, actual_hash


def build_derivation_manifest(
    artifact: Mapping[str, Any], resolution: Mapping[str, Any], *,
    candidate_path: str | Path, proof_hash: str, guard_hash: str,
    link_hash: str, proof_input_refs: list[dict[str, str]],
) -> dict[str, Any]:
    """Bind augmented catalogue bytes to base, proof, guard, tool/input receipts."""
    candidate_payload = dump_bytes(dict(artifact))
    source_statuses = Counter(row["status"] for row in resolution["rows"])
    compiler_categories = Counter(row["category"] for row in resolution["compilerInventory"])
    public_children = resolution["publicCompilerChildren"]
    child_occurrences = sum(row["rawCardinality"] for row in public_children)
    source_hash = artifact["provenance"]["sourceHash"]
    _require(source_hash == canonical_hash(resolution),
             "catalogue sourceHash does not bind accepted public-source proof resolution")
    return {
        "kind": "catalogue-derivation-manifest",
        "version": 1,
        "createdAt": artifact["provenance"]["createdAt"],
        "candidate": {
            "path": Path(candidate_path).name,
            "sha256": _digest(candidate_payload),
            "canonicalHash": canonical_hash(dict(artifact)),
            "catalogueId": artifact["id"],
        },
        "base": {
            "catalogueId": BASE_CATALOGUE_ID,
            "catalogueCanonicalHash": BASE_CATALOGUE_SHA256,
            "rawSourceHash": BASE_SOURCE_SHA256,
            "symbolCount": len(artifact["symbols"]) - resolution["graphAbsentPublicCompilerUsrCount"],
        },
        "proof": {
            "status": resolution["status"],
            "artifactSha256": proof_hash,
            "guardSha256": guard_hash,
            "immutableLinkSha256": link_hash,
            "acceptedResolutionCanonicalHash": source_hash,
            "inputRefs": deepcopy(proof_input_refs),
        },
        "coverage": {
            "sourceDeclarationStarts": resolution["fullSourceDeclarationStarts"],
            "sourceStatusCounts": dict(sorted(source_statuses.items())),
            "compilerRecordCount": resolution["compilerRecordCount"],
            "compilerRecordCategoryCounts": dict(sorted(compiler_categories.items())),
            "publicCompilerChildGroups": resolution["publicCompilerChildRecordCount"],
            "publicCompilerChildOccurrences": child_occurrences,
            "publicCompilerUsrs": resolution["publicCompilerCatalogueUsrCount"],
            "graphAbsentPublicCompilerUsrs": resolution["graphAbsentPublicCompilerUsrCount"],
            "addedSymbolCount": resolution["graphAbsentPublicCompilerUsrCount"],
            "outputSymbolCount": len(artifact["symbols"]),
        },
    }


def _validate_derivation_manifest(
    manifest: Mapping[str, Any], artifact: Mapping[str, Any], candidate_payload: bytes,
    candidate_name: str,
) -> None:
    _require(manifest.get("kind") == "catalogue-derivation-manifest"
             and type(manifest.get("version")) is int and manifest["version"] == 1,
             "candidate derivation manifest kind/version changed")
    candidate = manifest.get("candidate")
    _require(isinstance(candidate, dict)
             and candidate.get("sha256") == _digest(candidate_payload)
             and candidate.get("canonicalHash") == canonical_hash(dict(artifact))
             and candidate.get("catalogueId") == artifact.get("id")
             and candidate.get("path") == candidate_name,
             "candidate derivation manifest does not bind exact candidate bytes")
    base = manifest.get("base")
    _require(isinstance(base, dict) and base.get("catalogueId") == BASE_CATALOGUE_ID
             and base.get("catalogueCanonicalHash") == BASE_CATALOGUE_SHA256
             and base.get("rawSourceHash") == BASE_SOURCE_SHA256
             and base.get("symbolCount") == BASE_SYMBOL_COUNT,
             "candidate derivation manifest base provenance is malformed")
    proof = manifest.get("proof")
    _require(isinstance(proof, dict) and proof.get("status") == EXPECTED_PROOF_STATUS
             and proof.get("acceptedResolutionCanonicalHash") == artifact["provenance"].get("sourceHash")
             and proof.get("immutableLinkSha256") == IMMUTABLE_LINK_SHA256
             and all(isinstance(proof.get(name), str) and _HASH_RE.fullmatch(proof[name])
                     for name in ("artifactSha256", "guardSha256", "immutableLinkSha256")),
             "candidate derivation manifest proof provenance is malformed")
    _require(manifest.get("createdAt") == artifact["provenance"].get("createdAt"),
             "candidate & manifest createdAt differ")
    _require(isinstance(proof.get("inputRefs"), list)
             and all(isinstance(row, dict) and set(row) == {"id", "hash"}
                     and isinstance(row["id"], str) and _HASH_RE.fullmatch(row["hash"])
                     for row in proof["inputRefs"]),
             "candidate derivation manifest input refs are malformed")
    _require(len({row["id"] for row in proof["inputRefs"]}) == len(proof["inputRefs"]),
             "candidate derivation manifest input IDs are duplicated")
    artifact_inputs = artifact.get("provenance", {}).get("inputs", [])
    _require(isinstance(artifact_inputs, list), "candidate provenance input list is malformed")
    artifact_pairs = {(row.get("id"), row.get("hash")) for row in artifact_inputs if isinstance(row, dict)}
    required_pairs = {
        ("public-ancestor-proof-v1", proof["artifactSha256"]),
        ("public-ancestor-guard-v1", proof["guardSha256"]),
        ("immutable-sourcekit-links-836", proof["immutableLinkSha256"]),
        *((row["id"], row["hash"]) for row in proof["inputRefs"]),
    }
    _require(required_pairs <= artifact_pairs,
             "candidate provenance omits manifest proof/guard/compiler input references")
    coverage = manifest.get("coverage")
    _require(isinstance(coverage, dict), "candidate derivation manifest coverage is missing")
    source_counts = coverage.get("sourceStatusCounts")
    record_counts = coverage.get("compilerRecordCategoryCounts")
    _require(isinstance(source_counts, dict) and all(type(value) is int and value >= 0
                                                     for value in source_counts.values())
             and sum(source_counts.values()) == coverage.get("sourceDeclarationStarts"),
             "candidate derivation manifest source coverage is inconsistent")
    _require(isinstance(record_counts, dict) and all(type(value) is int and value >= 0
                                                     for value in record_counts.values())
             and sum(record_counts.values()) == coverage.get("compilerRecordCount"),
             "candidate derivation manifest compiler-record coverage is inconsistent")
    for name in ("publicCompilerChildGroups", "publicCompilerChildOccurrences",
                 "publicCompilerUsrs", "graphAbsentPublicCompilerUsrs", "addedSymbolCount",
                 "outputSymbolCount"):
        _require(type(coverage.get(name)) is int and coverage[name] >= 0,
                 "candidate derivation manifest count is malformed: " + name)
    _require(coverage["publicCompilerChildOccurrences"] >= coverage["publicCompilerChildGroups"]
             and coverage["graphAbsentPublicCompilerUsrs"] <= coverage["publicCompilerUsrs"]
             and coverage["addedSymbolCount"] == coverage["graphAbsentPublicCompilerUsrs"]
             and coverage["outputSymbolCount"] == BASE_SYMBOL_COUNT + coverage["addedSymbolCount"]
             and len(artifact["symbols"]) == coverage["outputSymbolCount"],
             "candidate derivation manifest output/supplement counts disagree")


def write_candidate_bundle_atomic(
    candidate_path: str | Path, manifest_path: str | Path,
    artifact: Mapping[str, Any], manifest: Mapping[str, Any],
) -> tuple[str, str]:
    """Atomically replace versioned candidate & derivation sidecar as a pair."""
    folder = Path(__file__).resolve().parent
    candidate_destination, manifest_destination = Path(candidate_path), Path(manifest_path)
    _require(candidate_destination.resolve().is_relative_to(folder)
             and manifest_destination.resolve().is_relative_to(folder),
             "candidate & manifest must remain in consumer-owned folder")
    _require(candidate_destination.parent.resolve() == manifest_destination.parent.resolve()
             and candidate_destination != manifest_destination,
             "candidate & manifest must be distinct siblings")
    candidate_value = dict(artifact)
    errors = validate_artifact(candidate_value, *load_registry(Path(__file__).resolve().parents[2] / "spec" / "schema"))
    _require(not errors, "candidate failed schema validation: " + "; ".join(errors))
    candidate_payload = dump_bytes(candidate_value)
    manifest_value = dict(manifest)
    _validate_derivation_manifest(manifest_value, candidate_value, candidate_payload,
                                  candidate_destination.name)
    manifest_payload = dump_bytes(manifest_value)
    candidate_destination.parent.mkdir(parents=True, exist_ok=True)
    destinations = (candidate_destination, manifest_destination)
    payloads = (candidate_payload, manifest_payload)
    original = tuple(path.read_bytes() if path.exists() else None for path in destinations)
    temporaries: list[str] = []
    try:
        for destination, payload in zip(destinations, payloads, strict=True):
            fd, temp_name = tempfile.mkstemp(prefix=f".{destination.name}.", suffix=".tmp",
                                             dir=destination.parent)
            temporaries.append(temp_name)
            with os.fdopen(fd, "wb") as stream:
                stream.write(payload)
                stream.flush()
                os.fsync(stream.fileno())
            _require(Path(temp_name).read_bytes() == payload, "candidate bundle temp bytes changed")
        _require(json.loads(Path(temporaries[0]).read_text(encoding="utf-8")) == candidate_value
                 and json.loads(Path(temporaries[1]).read_text(encoding="utf-8")) == manifest_value,
                 "candidate bundle temporary JSON readback changed")
        replaced = 0
        try:
            for temp_name, destination in zip(temporaries, destinations, strict=True):
                os.replace(temp_name, destination)
                replaced += 1
        except Exception:
            for index in range(replaced):
                destination = destinations[index]
                prior = original[index]
                if prior is None:
                    destination.unlink(missing_ok=True)
                else:
                    fd, restore_name = tempfile.mkstemp(prefix=f".{destination.name}.rollback.",
                                                         suffix=".tmp", dir=destination.parent)
                    with os.fdopen(fd, "wb") as stream:
                        stream.write(prior)
                        stream.flush()
                        os.fsync(stream.fileno())
                    os.replace(restore_name, destination)
            raise
        return _digest(candidate_payload), _digest(manifest_payload)
    finally:
        for temp_name in temporaries:
            if os.path.exists(temp_name):
                os.unlink(temp_name)


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
