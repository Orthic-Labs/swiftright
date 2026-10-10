"""Candidate v7 audit using exact SourceKit indexsource USR links.

The adapter rechecks interface identities against raw indexsource output. It
does not infer hiddenness from a missing symbol-graph entry.
"""
from __future__ import annotations

import json
import hashlib
import re
import subprocess
from collections import Counter
from pathlib import Path
from typing import Any

from factory.core import artifacts
from . import audit_v6, audit_v2

_RESIDUALS = {"active-compiler-conditional-unmapped", "ambiguous-context-signature", "unexplained"}
_DECLARATION_KIND = re.compile(r"^source\.lang\.swift\.decl\.")
_MODULE_NAMES = {"Swift", "SwiftUI", "SwiftUICore", "Foundation", "AppKit", "CoreFoundation",
                 "CoreGraphics", "Combine", "Observation", "UniformTypeIdentifiers"}


def _index_entities(path: Path) -> list[dict[str, Any]]:
    """Read declaration records from SourceKit-LSP's sourcekitd YAML-like response."""
    stack: list[dict[str, Any]] = []
    result: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        opened = re.match(r"^(\s*)\{$", line)
        if opened:
            stack.append({"indent": len(opened.group(1)), "fields": {}})
            continue
        closed = re.match(r"^(\s*)\}(?:,)?$", line)
        if closed:
            indent = len(closed.group(1))
            while stack and stack[-1]["indent"] >= indent:
                record = stack.pop()["fields"]
                if (_DECLARATION_KIND.match(str(record.get("kind", "")))
                        and all(key in record for key in ("name", "usr", "line"))):
                    containers = []
                    for parent in stack:
                        fields = parent["fields"]
                        kind = str(fields.get("kind", ""))
                        if (kind.startswith("source.lang.swift.decl.extension") or
                                kind in {"source.lang.swift.decl.struct", "source.lang.swift.decl.enum",
                                         "source.lang.swift.decl.protocol", "source.lang.swift.decl.class",
                                         "source.lang.swift.decl.actor"}):
                            containers.append({"kind": kind, "name": fields.get("name"),
                                               "usr": fields.get("usr")})
                    record["sourcekitContext"] = containers
                    result.append(record)
            continue
        field = re.match(r"^(\s*)key\.(kind|name|usr|line|column|is_implicit|effective_access): (.*?)(?:,)?$", line)
        if field and stack:
            indent, key, value = len(field.group(1)), field.group(2), field.group(3)
            if stack[-1]["indent"] + 2 != indent:
                continue
            if value.startswith('"'):
                value = json.loads(value)
            elif value == "null":
                value = None
            elif value in ("0", "1"):
                value = value == "1"
            elif value.isdigit():
                value = int(value)
            stack[-1]["fields"][key] = value
    if stack:
        raise ValueError(f"unterminated SourceKit response object in {path}")
    return result


def _name_matches(sourcekit_name: str, audit_name: str) -> bool:
    return sourcekit_name.strip("`").split("(", 1)[0] == audit_name.strip("`")


def _expected_sourcekit_name(row: dict[str, Any]) -> str:
    """Recover property name from interface signature when v6 lexer kept `var`/`let`."""
    if row.get("kind") in {"var", "let"}:
        match = re.search(r"\b(?:var|let)\s+(`[^`]+`|[A-Za-z_$][A-Za-z_0-9$]*)\s*:",
                          str(row.get("signature", "")))
        if match:
            return match.group(1).strip("`")
    return str(row.get("name", "")).strip("`")


def _kind_matches(sourcekit_kind: str, interface_kind: str) -> bool:
    prefixes = {
        "func": ("source.lang.swift.decl.function.",),
        "init": ("source.lang.swift.decl.function.constructor",),
        "subscript": ("source.lang.swift.decl.function.subscript",),
        "var": ("source.lang.swift.decl.var.",), "let": ("source.lang.swift.decl.var.",),
        "case": ("source.lang.swift.decl.enumelement",),
        "typealias": ("source.lang.swift.decl.typealias",),
        "struct": ("source.lang.swift.decl.struct",), "enum": ("source.lang.swift.decl.enum",),
        "protocol": ("source.lang.swift.decl.protocol",), "class": ("source.lang.swift.decl.class",),
        "actor": ("source.lang.swift.decl.actor",), "macro": ("source.lang.swift.decl.macro",),
    }
    return any(sourcekit_kind.startswith(prefix) for prefix in prefixes.get(interface_kind, ()))


def _expected_access(row: dict[str, Any]) -> str | None:
    match = re.search(r"\b(public|open|package|internal|fileprivate|private)\b",
                      str(row.get("signature", "")))
    return match.group(1) if match else None


def _source_context(module: str, line: int, scope_cache: dict[str, dict[int, list[dict[str, Any]]]]) -> tuple[str, ...]:
    scopes = scope_cache.get(module, {}).get(line, [])
    parts: list[str] = []
    for scope in scopes:
        parts.extend(audit_v2._scope_target(scope["target"]))
    return tuple(part for part in parts if part not in _MODULE_NAMES)


def _sourcekit_context_names(entity: dict[str, Any]) -> tuple[str, ...]:
    """Normalize raw SourceKit container records using spike's strict rule."""
    names = []
    for container in entity.get("sourcekitContext", []):
        name = str(container.get("name", "")).split(".")[-1].split("<", 1)[0]
        if name:
            names.append(name)
    return tuple(names)


def _demangled_owner(demangled: str, name: str) -> tuple[str, ...] | None:
    """Read compiler-demangled owner path immediately preceding declaration name."""
    if " ---> " in demangled:
        demangled = demangled.split(" ---> ", 1)[1]
    bare_name = name.strip("`")
    marker = "." + bare_name
    stop = demangled.find(marker)
    if stop < 0:
        return None
    prefix = re.sub(r"^\(extension in [^)]+\):", "", demangled[:stop]).strip()
    prefix = re.sub(r"^(?:static|class|nonisolated|mutating|prefix|postfix|infix)\s+", "", prefix)
    path_chars: list[str] = []
    generic_depth = 0
    index = 0
    while index < len(prefix):
        if prefix.startswith("->", index):
            if generic_depth == 0:
                path_chars.extend(("-", ">"))
            index += 2
            continue
        char = prefix[index]
        if char == "<":
            generic_depth += 1
        elif char == ">" and generic_depth:
            generic_depth -= 1
        elif generic_depth == 0:
            path_chars.append(char)
        index += 1
    prefix = "".join(path_chars)
    owner: list[str] = []
    for component in prefix.split("."):
        component = component.strip()
        identifiers = re.findall(r"[A-Za-z_$][A-Za-z_0-9$]*", component)
        if identifiers:
            owner.append(identifiers[-1])
    return tuple(part for part in owner if part not in _MODULE_NAMES)


def _assess_exact_sourcekit_link(row: dict[str, Any], raw_entities: list[dict[str, Any]],
                                 demangled_by_usr: dict[str, str], context: tuple[str, ...]
                                 ) -> tuple[bool, str | None, dict[str, Any] | None]:
    """Require one raw compiler record, exact declaration kind/access & owner."""
    if len(raw_entities) != 1:
        return False, "raw-sourcekit-entity-cardinality-not-one", None
    entity = raw_entities[0]
    if not _kind_matches(str(entity.get("kind", "")), str(row.get("kind", ""))):
        return False, "sourcekit-kind-does-not-match-interface", entity
    expected_access = _expected_access(row)
    if expected_access not in {"public", "open"}:
        return False, "interface-signature-does-not-prove-public-or-open-access", entity
    if entity.get("effective_access") != f"source.decl.effective_access.{expected_access}":
        return False, "sourcekit-access-does-not-match-interface-access", entity
    if _sourcekit_context_names(entity) != context:
        return False, "raw-sourcekit-context-does-not-match-interface-context", entity
    usr = entity.get("usr")
    demangled = demangled_by_usr.get(str(usr))
    if not demangled:
        return False, "compiler-usr-lacks-demangle-receipt", entity
    owner = _demangled_owner(demangled, str(entity.get("name", row.get("name", ""))).split("(", 1)[0])
    if owner != context:
        return False, "demangled-owner-does-not-match-interface-context", entity
    return True, None, entity


def _relative(root: Path, value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else root / path


def _parse_index_request(path: Path) -> dict[str, Any]:
    """Parse sourcekitd YAML-like request and retain duplicate argument counts."""
    text = path.read_text(encoding="utf-8")
    request_values = re.findall(r"(?m)^\s*key\.request:\s*([^,\s]+)\s*,?\s*$", text)
    source_values = re.findall(r"(?m)^\s*key\.sourcefile:\s*(\"(?:[^\"\\]|\\.)*\")\s*,?\s*$", text)
    arrays = re.findall(r"(?s)^\s*key\.compilerargs:\s*\[(.*?)\]", text, flags=re.MULTILINE)
    if len(request_values) != 1 or len(source_values) != 1 or len(arrays) != 1:
        raise ValueError(f"indexsource request lacks unique request/sourcefile/compilerargs fields: {path}")
    try:
        sourcefile = json.loads(source_values[0])
        arguments = json.loads("[" + arrays[0] + "]")
    except json.JSONDecodeError as error:
        raise ValueError(f"indexsource request arguments are not valid JSON strings: {path}") from error
    if not isinstance(arguments, list) or any(not isinstance(item, str) for item in arguments):
        raise ValueError(f"indexsource compilerargs must be a string list: {path}")
    return {"request": request_values[0], "sourcefile": sourcefile, "compilerargs": arguments}


def _validate_request_identity(path: Path, *, interface: str, sdk: str, target: str,
                               module: str) -> dict[str, Any]:
    parsed = _parse_index_request(path)
    args = parsed["compilerargs"]
    if parsed["request"] != "source.request.indexsource":
        raise ValueError(f"SourceKit request has wrong kind: {path}")
    if parsed["sourcefile"] != interface or args.count(interface) != 1 or not args or args[0] != interface:
        raise ValueError(f"SourceKit request sourcefile does not exactly match pinned interface: {path}")
    for flag, expected in (("-sdk", sdk), ("-target", target), ("-module-name", module)):
        positions = [index for index, value in enumerate(args) if value == flag]
        if len(positions) != 1 or positions[0] + 1 >= len(args) or args[positions[0] + 1] != expected:
            raise ValueError(f"SourceKit request has missing, duplicate, or conflicting {flag}: {path}")
    return parsed


def _demangle_map_from_stdout(raw_text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in raw_text.splitlines():
        if " ---> " not in line:
            raise ValueError("swift-demangle stdout contains an unstructured line")
        mangled, demangled = line.split(" ---> ", 1)
        normalized_usr = "s:" + mangled[2:] if mangled.startswith("$s") else ""
        if not normalized_usr or not demangled or normalized_usr in result:
            raise ValueError("swift-demangle stdout has invalid or duplicate USR result")
        result[normalized_usr] = demangled
    return result


def _validate_demangle_mapping(raw_text: str, mapping: dict[str, str]) -> None:
    if _demangle_map_from_stdout(raw_text) != mapping:
        raise ValueError("demangled USR map does not exactly reproduce retained swift-demangle stdout")


def _verified_link_claim(external_eligibility: bool, *, local_candidate_count: int,
                         occurrence_count: int, summary_consistent: bool,
                         occurrence_crosscheck: bool) -> bool:
    locally_valid = (local_candidate_count == 1 and occurrence_count == 1
                     and summary_consistent and occurrence_crosscheck)
    if external_eligibility and not locally_valid:
        raise ValueError("compiler link eligibility conflicts with local exact guards")
    return external_eligibility and locally_valid


def _sha(value: str) -> str:
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", value):
        raise ValueError(f"invalid SHA-256 reference: {value!r}")
    return value


def produce_demangle_evidence(v6_path: Path, link_path: Path, *, root: Path,
                              output_path: Path) -> dict[str, Any]:
    """Run pinned Xcode swift-demangle over SourceKit USRs; retain raw stdout."""
    v6_path, link_path, root, output_path = map(Path, (v6_path, link_path, root, output_path))
    v6 = json.loads(v6_path.read_text(encoding="utf-8"))
    links = json.loads(link_path.read_text(encoding="utf-8"))
    if links["pinnedInputs"]["auditHash"] != v6["auditHash"]:
        raise ValueError("SourceKit evidence pins a different v6 audit hash")
    tool = Path(subprocess.run(["xcrun", "--toolchain", "Xcode-27-RC", "--find", "swift-demangle"],
                               text=True, capture_output=True, check=True).stdout.strip())
    version = subprocess.run([str(tool), "--version"], text=True, capture_output=True, check=True).stdout.strip()
    interfaces = {entry["module"]: entry for entry in links.get("interfaces", [])}
    entities = {module: _index_entities(root / entry["indexOutput"])
                for module, entry in interfaces.items()}
    candidate_usrs = {
        str(entity["usr"])
        for row in links["rows"]
        for entity in entities[row["module"]]
        if entity.get("line") == row["line"]
        and entity.get("is_implicit") is not True
        and _name_matches(str(entity.get("name", "")), _expected_sourcekit_name(row))
    }
    usrs = sorted(candidate_usrs | {item["usr"] for row in links["rows"]
                                   for item in row.get("indexMatches", [])})
    if not usrs or any(not usr.startswith("s:") for usr in usrs):
        raise ValueError("SourceKit evidence contains missing or unsupported USR encoding")
    raw_lines: list[str] = []
    by_usr: dict[str, str] = {}
    chunk_size = 96
    for start in range(0, len(usrs), chunk_size):
        group = usrs[start:start + chunk_size]
        inputs = ["$s" + usr[2:] for usr in group]
        result = subprocess.run([str(tool), *inputs], text=True, capture_output=True, check=True)
        lines = result.stdout.splitlines()
        if len(lines) != len(group):
            raise ValueError(f"swift-demangle returned {len(lines)} rows for {len(group)} USRs")
        for usr, line in zip(group, lines):
            if " ---> " not in line:
                raise ValueError(f"swift-demangle did not return a structured result for {usr}")
            left, demangled = line.split(" ---> ", 1)
            if left != "$s" + usr[2:] or demangled == left:
                raise ValueError(f"swift-demangle left an input undecoded: {usr}")
            by_usr[usr] = demangled
            raw_lines.append(line)
    raw_bytes = ("\n".join(raw_lines) + "\n").encode("utf-8")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(raw_bytes)
    payload: dict[str, Any] = {
        "kind": "swift-usr-demangle-evidence", "version": 1,
        "status": "compiler-output-retained-context-not-yet-audited",
        "method": "Xcode swift-demangle on every unique SourceKit indexsource USR; inputs use Swift mangling spelling derived reversibly from exact SourceKit USR bytes. Raw stdout is retained and SHA-256 pinned.",
        "v6AuditHash": v6["auditHash"],
        "linkEvidence": {"path": str(link_path.relative_to(root)), "sha256": artifacts.file_hash(link_path)},
        "tool": {"path": str(tool), "sha256": artifacts.file_hash(tool), "version": version,
                 "arguments": ["swift-demangle"], "chunkSize": chunk_size,
                 "invocationCount": (len(usrs) + chunk_size - 1) // chunk_size},
        "usrCount": len(usrs), "rawOutput": str(output_path.relative_to(root)),
        "rawOutputSha256": "sha256:" + hashlib.sha256(raw_bytes).hexdigest(),
        "demangledByUsr": by_usr,
    }
    payload["evidenceHash"] = artifacts.canonical_hash(payload)
    return payload


def build_audit_v7(v6_path: Path, link_path: Path, demangle_path: Path, *, root: Path) -> dict[str, Any]:
    """Build candidate only if every SourceKit link is reproducibly exact.

    This function validates one-to-one residual coverage, source and request
    hashes, exact source lines/names, compiler-emitted USRs and graph presence.
    Missing graph entries remain explicit and are never called hidden.
    """
    v6_path, link_path, demangle_path, root = map(Path, (v6_path, link_path, demangle_path, root))
    v6 = json.loads(v6_path.read_text(encoding="utf-8"))
    links = json.loads(link_path.read_text(encoding="utf-8"))
    demangle = json.loads(demangle_path.read_text(encoding="utf-8"))
    inputs = links.get("pinnedInputs", {})
    if inputs.get("auditHash") != v6.get("auditHash"):
        raise ValueError("SourceKit evidence pins a different v6 audit hash")
    if inputs.get("auditFileByteSha256") != artifacts.file_hash(v6_path):
        raise ValueError("SourceKit evidence pins different v6 audit bytes")
    if demangle.get("v6AuditHash") != v6.get("auditHash"):
        raise ValueError("demangler evidence pins a different v6 audit hash")
    if demangle.get("linkEvidence", {}).get("sha256") != artifacts.file_hash(link_path):
        raise ValueError("demangler evidence pins different SourceKit link evidence")
    if demangle.get("rawOutputSha256") != artifacts.file_hash(root / demangle["rawOutput"]):
        raise ValueError("retained swift-demangle stdout bytes differ from evidence")
    raw_demangle_text = (root / demangle["rawOutput"]).read_text(encoding="utf-8")
    _validate_demangle_mapping(raw_demangle_text, demangle.get("demangledByUsr", {}))
    demangle_body = dict(demangle)
    claimed_demangle_hash = demangle_body.pop("evidenceHash", None)
    if claimed_demangle_hash != artifacts.canonical_hash(demangle_body):
        raise ValueError("swift-demangle evidence object hash is invalid")

    extraction_path = root / inputs["extractionSummary"]
    catalogue_path = root / inputs["symbolCatalogue"]
    if artifacts.file_hash(extraction_path) != inputs["extractionSummarySha256"]:
        raise ValueError("extraction summary bytes differ from SourceKit evidence")
    if artifacts.file_hash(catalogue_path) != inputs["symbolCatalogueHash"]:
        raise ValueError("symbol catalogue bytes differ from SourceKit evidence")
    catalogue = json.loads(catalogue_path.read_text(encoding="utf-8"))
    if catalogue.get("symbolGraph", {}).get("target") != inputs.get("symbolGraphTarget"):
        raise ValueError("catalogue target differs from pinned symbolgraph target")
    graph_by_usr: dict[str, list[dict[str, Any]]] = {}
    for symbol in catalogue.get("symbols", []):
        if symbol.get("usr") != symbol.get("precise"):
            raise ValueError("catalogue symbol USR/precise fields disagree")
        graph_by_usr.setdefault(str(symbol["usr"]), []).append(symbol)
    extraction = json.loads(extraction_path.read_text(encoding="utf-8"))
    if inputs.get("sdk") != extraction.get("toolchain", {}).get("sdkPath"):
        raise ValueError("SourceKit SDK path differs from pinned extraction SDK")
    if extraction["toolchain"]["target"] != inputs["symbolGraphTarget"]:
        raise ValueError("SourceKit evidence target differs from current symbolgraph target")
    if v6.get("symbolgraphTarget") != inputs["symbolGraphTarget"]:
        raise ValueError("v6 graph target differs from SourceKit evidence target")
    if v6.get("graphTargetEvidence", {}).get("sourceHash") != artifacts.file_hash(extraction_path):
        raise ValueError("v6 target evidence does not pin current extraction summary")
    toolchain_evidence = links.get("toolchainEvidence", {})
    compiler_evidence = toolchain_evidence.get("compiler", {})
    sourcekit_target = toolchain_evidence.get("target")
    if toolchain_evidence.get("sdk") != inputs.get("sdk"):
        raise ValueError("SourceKit toolchain receipt SDK differs from pinned SDK path")
    if sourcekit_target != extraction.get("toolchain", {}).get("target"):
        raise ValueError("SourceKit target differs from pinned extraction target")
    extraction_compiler = str(extraction.get("toolchain", {}).get("compiler", ""))
    compiler_build = re.search(r"\b\d+\.\d+\.\d+\.\d+\b", str(inputs.get("compiler", "")))
    if (not compiler_build or "Apple Swift" not in extraction_compiler
            or compiler_build.group(0) not in extraction_compiler
            or compiler_build.group(0) not in str(compiler_evidence.get("version", ""))):
        raise ValueError("SourceKit compiler identity differs from pinned extraction compiler")
    if compiler_evidence.get("sha256") != artifacts.file_hash(compiler_evidence.get("executablePath", "")):
        raise ValueError("SourceKit compiler executable bytes differ from toolchain receipt")
    for binary_key in ("sourcekitLsp", "sourcekitd"):
        binary = toolchain_evidence.get(binary_key, {})
        if binary.get("sha256") != artifacts.file_hash(binary.get("path", "")):
            raise ValueError(f"{binary_key} bytes differ from SourceKit toolchain receipt")
    xcodebuild_version = toolchain_evidence.get("xcodebuildVersion", "")
    xcode_identity = re.fullmatch(r"(Xcode \S+) \(([^)]+)\)", str(inputs.get("xcode", "")))
    if xcode_identity and not all(part in xcodebuild_version for part in xcode_identity.groups()):
        raise ValueError("Xcode build receipt does not match pinned Xcode identity")
    if demangle["tool"]["sha256"] != artifacts.file_hash(demangle["tool"]["path"]):
        raise ValueError("swift-demangle executable bytes differ from evidence")
    expected_graph_hashes = {Path(item["file"]).name: item["sha256"] for item in v6["symbolGraphs"]}
    raw_graphs = links.get("rawGraphInputs", [])
    if len(raw_graphs) != len(expected_graph_hashes):
        raise ValueError("SourceKit graph closure does not cover all v6 symbolgraph files")
    for graph in raw_graphs:
        graph_path = root / graph["path"]
        if artifacts.file_hash(graph_path) != graph["sha256"]:
            raise ValueError(f"raw symbolgraph bytes differ from SourceKit crosslink receipt: {graph_path}")
        if expected_graph_hashes.get(graph_path.name) != graph["sha256"]:
            raise ValueError(f"SourceKit graph closure does not match v6 graph bytes: {graph_path}")

    interfaces: dict[str, dict[str, Any]] = {entry["module"]: entry for entry in links.get("interfaces", [])}
    entities_by_module: dict[str, list[dict[str, Any]]] = {}
    scope_cache: dict[str, dict[int, list[dict[str, Any]]]] = {}
    for module, entry in interfaces.items():
        interface_path = Path(entry["path"])
        if artifacts.file_hash(interface_path) != entry["sha256"]:
            raise ValueError(f"{module} interface bytes differ from SourceKit evidence")
        response_path = root / entry["indexOutput"]
        if artifacts.file_hash(response_path) != entry["indexOutputSha256"]:
            raise ValueError(f"{module} sourcekit index response bytes differ from evidence")
        request_path = root / entry["indexRequest"]
        if artifacts.file_hash(request_path) != entry["indexRequestSha256"]:
            raise ValueError(f"{module} indexsource request bytes differ from evidence")
        identity = entry["requestIdentity"]
        _validate_request_identity(request_path, interface=entry["path"], sdk=inputs["sdk"],
                                   target=sourcekit_target, module=module)
        if identity != {"sourcefile": entry["path"], "sdk": Path(inputs["sdk"]).name,
                       "target": sourcekit_target, "moduleName": module}:
            raise ValueError(f"{module} parsed request identity differs from pinned identity object")
        entities_by_module[module] = _index_entities(response_path)
        scope_cache[module] = audit_v6._line_scopes(interface_path)
        if not sourcekit_target:
            raise ValueError("SourceKit evidence lacks its toolchain target")

    evidence_rows: dict[tuple[Any, ...], dict[str, Any]] = {}
    for row in links.get("rows", []):
        key = (row.get("module"), row.get("interface"), row.get("line"), row.get("name"), row.get("sourceHash"))
        if key in evidence_rows:
            raise ValueError(f"duplicate SourceKit audit-row key: {key}")
        evidence_rows[key] = row
    residual_rows = [row for row in v6["declarations"] if row.get("classification") in _RESIDUALS]
    residual_keys = {(row.get("module"), row.get("interface"), row.get("line"), row.get("name"),
                      next((item["sha256"] for item in v6["interfaces"] if item["module"] == row["module"]), None))
                     for row in residual_rows}
    if residual_keys != set(evidence_rows):
        raise ValueError(f"SourceKit coverage does not exactly equal v6 residual rows: {len(residual_keys)} vs {len(evidence_rows)}")

    rows = json.loads(json.dumps(v6["declarations"]))
    seen_linked = 0
    graph_present = 0
    graph_absent = 0
    held_reasons: Counter[str] = Counter()
    for row in rows:
        if row.get("classification") not in _RESIDUALS:
            continue
        interface_hash = next(item["sha256"] for item in v6["interfaces"] if item["module"] == row["module"])
        key = (row["module"], row["interface"], row["line"], row["name"], interface_hash)
        link = evidence_rows[key]
        if link.get("signature") != row.get("signature") or link.get("context") != row.get("context"):
            raise ValueError(f"SourceKit row does not match exact v6 declaration at {key}")
        if link.get("sourceHash") != interface_hash:
            raise ValueError(f"SourceKit row source hash differs from v6 interface at {key}")
        module = row["module"]
        interface_entry = interfaces.get(module)
        if not interface_entry or interface_entry["sha256"] != interface_hash:
            raise ValueError(f"SourceKit interface hash differs from v6 interface for {module}")

        sourcekit_name = _expected_sourcekit_name(row)
        raw_entities = [entity for entity in entities_by_module[module]
                        if entity.get("line") == row["line"] and not entity.get("is_implicit", False)
                        and _name_matches(str(entity.get("name", "")), sourcekit_name)]
        exact = link.get("indexMatches", [])
        flattened = [occurrence for item in exact for occurrence in item.get("occurrences", [])]
        summary_consistent = (link.get("indexMatchCount") == len(exact)
                              and {e.get("usr") for e in flattened} == {item.get("usr") for item in exact}
                              and link.get("sourcekitEntityCount") == len(flattened))
        if not summary_consistent and link.get("linkEligibility") is True:
            raise ValueError(f"eligible SourceKit link summary differs from raw occurrence records at {key}")
        identity_fields = ("line", "column", "kind", "name", "usr", "effective_access", "is_implicit")
        projection = lambda entity: tuple(entity.get(field) for field in identity_fields)
        raw_counts = Counter(projection(item) for item in raw_entities)
        unmatched_occurrences = 0
        for occurrence in flattened:
            identity = projection(occurrence)
            if raw_counts[identity] <= 0:
                unmatched_occurrences += 1
            else:
                raw_counts[identity] -= 1
        occurrence_crosscheck = unmatched_occurrences == 0
        if not occurrence_crosscheck and link.get("linkEligibility") is True:
            raise ValueError(f"eligible SourceKit occurrence is absent from raw response at {key}")

        request = root / link["compilerEvidence"]["request"]
        response = root / link["compilerEvidence"]["response"]
        if request != root / interface_entry["indexRequest"]:
            raise ValueError(f"SourceKit row points at wrong module request for {key}")
        if link["compilerEvidence"]["requestSha256"] != interface_entry["indexRequestSha256"]:
            raise ValueError(f"SourceKit row request hash differs from module receipt for {key}")
        if artifacts.file_hash(request) != link["compilerEvidence"]["requestSha256"]:
            raise ValueError(f"SourceKit request bytes differ from evidence for {key}")
        if artifacts.file_hash(response) != link["compilerEvidence"]["responseSha256"]:
            raise ValueError(f"SourceKit response bytes differ from evidence for {key}")
        if response != root / interface_entry["indexOutput"]:
            raise ValueError(f"SourceKit row points at wrong module response for {key}")
        if link["compilerEvidence"].get("validatedTarget") != sourcekit_target:
            raise ValueError(f"SourceKit row target differs from pinned indexsource target at {key}")
        if link["compilerEvidence"].get("compilerIdentity") != "toolchainEvidence.compiler":
            raise ValueError(f"SourceKit row compiler receipt reference differs at {key}")
        demangled_by_usr = demangle.get("demangledByUsr", {})
        expected_context = _source_context(module, row["line"], scope_cache)
        assessed = [_assess_exact_sourcekit_link(row, [candidate], demangled_by_usr, expected_context)
                    for candidate in raw_entities]
        local_eligible = [candidate for candidate, (ok, _, _) in zip(raw_entities, assessed) if ok]
        eligible = len(local_eligible) == 1
        reasons = [reason for ok, reason, _ in assessed if not ok and reason]
        if not raw_entities:
            hold_reason = "no-compiler-record-at-interface-line-and-name"
        elif len(local_eligible) > 1:
            hold_reason = "multiple-public-exact-context-compiler-records"
        elif reasons:
            hold_reason = Counter(reasons).most_common(1)[0][0]
        elif link.get("sameLineContextEntityCount", 0) == 0:
            hold_reason = "compiler-context-control-found-no-exact-interface-context"
        else:
            hold_reason = "compiler-index-link-not-eligible-after-local-context-kind-access-checks"
        unique_entity = local_eligible[0] if eligible else None
        eligible = _verified_link_claim(link.get("linkEligibility") is True,
                                        local_candidate_count=len(local_eligible),
                                        occurrence_count=len(flattened),
                                        summary_consistent=summary_consistent,
                                        occurrence_crosscheck=occurrence_crosscheck)
        if eligible:
            selected = projection(unique_entity)
            if sum(projection(item) == selected for item in flattened) != 1:
                raise ValueError(f"qualified raw SourceKit entity lacks exactly one preserved occurrence at {key}")
        if not eligible and hold_reason is None:
            hold_reason = ("sourcekit-record-does-not-match-audit-row" if not occurrence_crosscheck
                           else "sourcekit-occurrence-summary-inconsistent" if not summary_consistent
                           else "compiler-evidence-did-not-qualify-row")

        row["sourceKitPriorClassification"] = row["classification"]
        row["sourceKitEvidence"] = {
            "method": "sourcekit-indexsource-exact-interface-line-and-name",
            "interface": row["interface"], "line": row["line"], "name": row["name"],
            "compilerDeclarationName": sourcekit_name,
            "interfaceSha256": interface_hash,
            "compiler": inputs["compiler"],
            "target": sourcekit_target,
            "request": link["compilerEvidence"]["request"],
            "requestSha256": link["compilerEvidence"]["requestSha256"],
            "response": link["compilerEvidence"]["response"],
            "responseSha256": link["compilerEvidence"]["responseSha256"],
            "interfaceContext": list(expected_context),
            "demangleEvidenceHash": demangle["evidenceHash"],
            "rawLineNameCandidateCount": len(raw_entities),
            "locallyQualifiedRawEntityCount": len(local_eligible),
            "rawExactEntityCount": len(flattened),
            "rawOccurrenceCrosscheck": occurrence_crosscheck,
            "unmatchedRawOccurrenceCount": unmatched_occurrences,
            "rawCandidateAssessments": [
                {"line": entity.get("line"), "column": entity.get("column"),
                 "name": entity.get("name"), "usr": entity.get("usr"),
                 "kind": entity.get("kind"), "effectiveAccess": entity.get("effective_access"),
                 "passedLocalExactGuards": ok, "reason": reason}
                for entity, (ok, reason, _) in zip(raw_entities, assessed)
            ],
            "linkEligibility": link.get("linkEligibility") is True,
            "exactIndexMatches": exact,
        }
        if eligible and unique_entity is not None:
            usr = str(unique_entity["usr"])
            graph_matches = graph_by_usr.get(usr, [])
            spike_matches = next((item.get("symbolGraphMatches", []) for item in exact
                                  if item.get("usr") == usr), [])
            if spike_matches and spike_matches != graph_matches:
                raise ValueError(f"SourceKit crosslink differs from pinned catalogue for {key}")
            row["symbol"] = {"usr": usr, "source": "SourceKit indexsource"}
            row["sourceKitEvidence"]["symbolGraphMatches"] = graph_matches
            if graph_matches:
                row["classification"] = "matched-sourcekit-usr-in-symbolgraph"
                graph_present += 1
            else:
                row["classification"] = "matched-sourcekit-usr-absent-from-symbolgraph"
                graph_absent += 1
            seen_linked += 1
        else:
            reason = hold_reason or "compiler-source-identity-check-failed"
            row["sourceKitEvidence"]["reason"] = reason
            held_reasons[reason] += 1

    counts = Counter(row["classification"] for row in rows)
    provenance_inputs = [
        {"path": str(v6_path.relative_to(root)), "hash": v6["auditHash"]},
        {"path": str(link_path.relative_to(root)), "hash": artifacts.file_hash(link_path)},
        {"path": str(demangle_path.relative_to(root)), "hash": artifacts.file_hash(demangle_path)},
        {"path": demangle["rawOutput"], "hash": demangle["rawOutputSha256"]},
        {"path": demangle["tool"]["path"], "hash": demangle["tool"]["sha256"]},
        {"path": inputs["extractionSummary"], "hash": inputs["extractionSummarySha256"]},
        {"path": inputs["symbolCatalogue"], "hash": inputs["symbolCatalogueHash"]},
    ]
    for entry in links["interfaces"]:
        provenance_inputs.extend([
            {"path": entry["path"], "hash": entry["sha256"]},
            {"path": entry["indexOutput"], "hash": entry["indexOutputSha256"]},
        ])
    provenance_inputs.extend({"path": entry["path"], "hash": entry["sha256"]}
                             for entry in raw_graphs)
    remaining = sum(counts[name] for name in _RESIDUALS)
    payload: dict[str, Any] = {
        "kind": "swift-interface-audit", "version": 7,
        "status": "incomplete-sourcekit-index-linked-with-symbolgraph-gaps",
        "method": "Candidate v7 adds compiler-emitted SourceKit indexsource USRs only when pinned raw index output contains exactly one non-implicit declaration record at exact interface line/name, with matching declaration-kind family, public/open effective access, demangled owner equal to interface lexical context, and independently generated linkEligibility true. Graph presence is rechecked from pinned catalogue bytes; absent graph entries remain explicit and are never called hidden. Rejected rows retain prior unresolved classification with per-row reason.",
        "parentAudit": {"path": str(v6_path.relative_to(root)), "auditHash": v6["auditHash"],
                        "status": v6["status"], "symbolgraphTarget": v6["symbolgraphTarget"]},
        "sourceKitAuthority": {
            "method": links["method"], "pinnedInputs": inputs,
            "interfaces": links["interfaces"],
            "evidencePath": str(link_path.relative_to(root)),
            "evidenceSha256": artifacts.file_hash(link_path),
        },
        "summary": {
            "v6ResidualRows": len(residual_rows), "exactSourceKitUsrLinks": seen_linked,
            "sourceKitUsrPresentInSymbolGraph": graph_present,
            "sourceKitUsrAbsentFromSymbolGraph": graph_absent,
            "heldSourceKitRows": sum(held_reasons.values()),
            "heldSourceKitReasons": dict(sorted(held_reasons.items())),
            "remainingActiveUnmappedAmbiguousOrUnexplained": remaining,
            "graphSymbolCount": v6["summary"]["graphSymbolCount"],
            "graphUsrCount": v6["summary"]["graphUsrCount"],
            "byClassification": dict(sorted(counts.items())),
        },
        "interfaces": v6["interfaces"], "symbolGraphs": v6["symbolGraphs"],
        "symbolgraphTarget": v6["symbolgraphTarget"],
        "graphTargetEvidence": v6["graphTargetEvidence"],
        "compilerConditionalEvidence": v6["compilerConditionalEvidence"],
        "declarations": rows,
        "provenance": artifacts.provenance(v6["auditHash"], provenance_inputs,
                                            producer="sr1-factory.catalogue.audit-v7"),
    }
    payload["auditHash"] = artifacts.canonical_hash(payload)
    return payload


def main() -> None:
    root = Path(__file__).resolve().parents[2]
    evidence = root / "factory/catalogue/evidence"
    payload = build_audit_v7(evidence / "interface-audit-v6.json",
                             root / "factory/catalogue/compiler-cursor-spike/link-evidence.json",
                             evidence / "sourcekit-usr-demangle-v7-final.json",
                             root=root)
    artifacts.write_artifact(evidence / "interface-audit-v7.json", payload)


if __name__ == "__main__":
    main()
