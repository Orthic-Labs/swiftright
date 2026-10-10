from __future__ import annotations

import json
import re
import subprocess
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable

from factory.core import artifacts

MODULES = ("SwiftUI", "SwiftUICore")
HIDDEN_ATTRIBUTES = (
    (re.compile(r"@_documentation\s*\(\s*visibility\s*:\s*(internal|private)\s*\)"), "documentation visibility"),
    (re.compile(r"@_spi(?:\s*\([^)]*\))?"), "SPI-only declaration"),
    (re.compile(r"@_spiOnly"), "SPI-only declaration"),
)
DECL = re.compile(r"\b(public|open)\s+(?:(?:nonisolated|static|class|final|mutating|nonmutating|override|prefix|postfix|infix|indirect|lazy|weak|unowned|isolated|distributed|consuming|borrowing|sending|async|throws|rethrows)\s+)*(func|var|let|subscript|init|deinit|struct|class|enum|protocol|actor|typealias|associatedtype|operator|macro|case)\s+?([A-Za-z_][A-Za-z_0-9]*)?")


def sha_file(path: Path) -> str:
    return artifacts.file_hash(path)


def _owner(usr: str, fallback: str) -> str:
    # Swift mangling starts with the defining module; do not mistake nested type references for it.
    match = re.match(r"s:(?:e:)?\d+([A-Za-z_]+)", usr)
    if not match:
        return fallback
    return match.group(1)


def run_extraction(sdk: Path, target: str, out: Path, developer_dir: Path) -> list[Path]:
    out.mkdir(parents=True, exist_ok=True)
    # Keep versioned SDK symlink spelling intact so invocation evidence pins the SDK version.
    sdk = sdk.absolute()
    developer_dir = developer_dir.resolve()
    env = {**__import__("os").environ, "DEVELOPER_DIR": str(developer_dir)}
    produced: list[Path] = []
    for module in MODULES:
        module_out = out / module.lower()
        module_out.mkdir(parents=True, exist_ok=True)
        command = ["xcrun", "swift-symbolgraph-extract", "-module-name", module,
                   "-sdk", str(sdk), "-target", target, "-output-dir", str(module_out),
                   "-emit-extension-block-symbols"]
        subprocess.run(command, check=True, env=env)
        produced.extend(sorted(module_out.glob("*.symbols.json")))
    if not produced:
        raise RuntimeError("symbolgraph extraction produced no graphs")
    return produced


def merge_graphs(graph_paths: Iterable[Path]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    by_usr: dict[str, dict[str, Any]] = {}
    graph_counts: list[dict[str, Any]] = []
    for path in sorted(map(Path, graph_paths)):
        graph = json.loads(path.read_text(encoding="utf-8"))
        fallback = graph.get("module", {}).get("name", path.name.split("@")[0])
        graph_counts.append({"file": path.name, "module": fallback, "symbols": len(graph.get("symbols", [])), "relationships": len(graph.get("relationships", []))})
        for symbol in graph.get("symbols", []):
            identifier = symbol.get("identifier", {})
            usr = identifier.get("precise")
            parts = symbol.get("pathComponents", [])
            if not usr or not parts:
                continue
            module = _owner(usr, fallback)
            entry = {"usr": usr, "precise": usr, "path": module + "." + ".".join(parts), "status": "inventory"}
            prior = by_usr.get(usr)
            if prior is None or (entry["path"], path.name) < (prior["path"], prior.get("_source", "")):
                entry["_source"] = path.name
                by_usr[usr] = entry
    symbols = [{k: v for k, v in entry.items() if k != "_source"} for entry in sorted(by_usr.values(), key=lambda x: x["usr"])]
    return symbols, {"graphs": graph_counts, "symbolCountByUsr": len(symbols), "graphSymbolCount": sum(g["symbols"] for g in graph_counts), "duplicateUsrCount": sum(g["symbols"] for g in graph_counts) - len(symbols)}


def _interface_declarations(path: Path) -> list[dict[str, Any]]:
    declarations: list[dict[str, Any]] = []
    attributes: list[str] = []
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    for number, line in enumerate(lines, 1):
        stripped = line.strip()
        inline_attributes = re.findall(r"@_?[A-Za-z][A-Za-z0-9_]*(?:\([^)]*\))?", stripped)
        if stripped.startswith("@"):
            attributes.append(stripped)
        match = DECL.search(stripped)
        if stripped.startswith("@") and not match:
            continue
        if match:
            # Ignore declarations explicitly scoped to private/fileprivate access even if another public token appears.
            context = " ".join(attributes[-10:] + inline_attributes + [stripped])
            hidden = next(((reason, attr) for pattern, reason in HIDDEN_ATTRIBUTES for attr in [pattern.search(context)] if attr), None)
            token = match.group(3) or match.group(2)
            declarations.append({"interface": path.name, "line": number, "kind": match.group(2), "name": token,
                                "declaration": stripped[:600], "attributes": list(dict.fromkeys(attributes[-10:] + inline_attributes)),
                                "classification": "hidden-attribute" if hidden else "unmatched", "hiddenReason": hidden[0] if hidden else None})
        if stripped and not stripped.startswith("//"):
            attributes = []
    return declarations


def _interface_target(path: Path) -> str | None:
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines()[:12]:
        match = re.search(r"//\s*swift-module-flags:\s+.*?-target\s+(\S+)", line)
        if match:
            return match.group(1)
    return None


def audit_interfaces(interface_paths: Iterable[Path], symbols: list[dict[str, Any]], symbolgraph_target: str | None = None) -> dict[str, Any]:
    # Name-level matching is intentionally conservative: overloaded declarations and extension context
    # cannot be mapped to USRs without a Swift parser. Such rows remain visible as ambiguous/unmatched.
    all_names: set[str] = set()
    for symbol in symbols:
        name = symbol["path"].rsplit(".", 1)[-1].split("(", 1)[0]
        all_names.add(name)
    rows: list[dict[str, Any]] = []
    hashes = []
    for path in sorted(map(Path, interface_paths)):
        hashes.append({"file": path.name, "module": "SwiftUICore" if "SwiftUICore.framework" in str(path) else "SwiftUI", "target": _interface_target(path), "hash": sha_file(path)})
        module = "SwiftUICore" if "SwiftUICore.framework" in str(path) else "SwiftUI"
        for row in _interface_declarations(path):
            if row["classification"] != "hidden-attribute" and row["name"] in all_names:
                row["classification"] = "name-present-ambiguous"
                row["hiddenReason"] = None
            rows.append(row)
    status_counts = defaultdict(int)
    for row in rows:
        status_counts[row["classification"]] += 1
    payload = {
        "kind": "swift-interface-audit", "version": 1,
        "status": "incomplete-name-level-audit",
        "method": "Enumerates public/open interface declaration starts; attributes are retained; symbolgraph reconciliation uses names only. Overloads, multiline declarations, conditional compilation, and extension ownership need compiler-aware parsing before completeness can be claimed.",
        "interfaces": hashes,
        "summary": {"publicDeclarationStarts": len(rows), "byClassification": dict(sorted(status_counts.items())), "symbolgraphSymbols": len(symbols), "symbolgraphTarget": symbolgraph_target, "interfaceTargets": sorted({item["target"] for item in hashes if item["target"]})},
        "declarations": rows,
    }
    payload["auditHash"] = artifacts.canonical_hash(payload)
    return payload


def make_catalogue(graph_paths: Iterable[Path], interface_paths: Iterable[Path], *, sdk: str, compiler: str, target: str, flags: list[str], catalogue_id: str) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    symbols, graph_summary = merge_graphs(graph_paths)
    audit = audit_interfaces(interface_paths, symbols, target)
    flags_hash = artifacts.canonical_hash(flags)
    source_items = sorted([*map(Path, graph_paths), *map(Path, interface_paths)])
    source_hash = artifacts.canonical_hash([{"path": p.name, "hash": sha_file(p)} for p in source_items])
    artifact = {
        "kind": "catalogue", "version": "0.1", "id": catalogue_id,
        "provenance": artifacts.provenance(source_hash, producer="factory.catalogue/0.1"),
        "symbolGraph": {"sdk": sdk, "compiler": compiler, "target": target, "flagsHash": flags_hash, "interfaceAuditHash": audit["auditHash"]},
        "symbols": symbols,
    }
    return artifact, audit, graph_summary


def write_canonical(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    artifacts.write_artifact(path, value)
