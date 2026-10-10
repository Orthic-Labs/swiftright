"""Exact, fail-closed matching rules for SourceKit interface index evidence."""
from __future__ import annotations

import re

KIND_MATCHERS = {
    "func": lambda k: k.startswith("source.lang.swift.decl.function."),
    "var": lambda k: k.startswith("source.lang.swift.decl.var."),
    "let": lambda k: k.startswith("source.lang.swift.decl.var."),
    "case": lambda k: k == "source.lang.swift.decl.enumelement",
    "typealias": lambda k: k == "source.lang.swift.decl.typealias",
    "struct": lambda k: k == "source.lang.swift.decl.struct",
    "enum": lambda k: k == "source.lang.swift.decl.enum",
    "protocol": lambda k: k == "source.lang.swift.decl.protocol",
    "class": lambda k: k == "source.lang.swift.decl.class",
    "actor": lambda k: k == "source.lang.swift.decl.actor",
    "macro": lambda k: k == "source.lang.swift.decl.macro",
}


def declaration_name(row: dict) -> str:
    match = re.search(
        r"\b(?:func|var|let|typealias|struct|enum|class|protocol|actor|init|subscript)\s+`?([A-Za-z_$][A-Za-z0-9_$]*)",
        row["signature"],
    )
    return (match.group(1) if match else row["name"].strip("`")).split("(", 1)[0]


def context_names(sourcekit_context: list[dict]) -> list[str]:
    return [str(x.get("name", "")).split(".")[-1].split("<", 1)[0] for x in sourcekit_context]


def access_level(signature: str) -> str | None:
    match = re.search(r"\b(public|open|package|internal|fileprivate|private)\b", signature)
    return match.group(1) if match else None


def entity_kind_matches(row: dict, entity: dict) -> bool:
    matcher = KIND_MATCHERS.get(row["kind"])
    return matcher is not None and matcher(str(entity.get("kind", "")))


def entity_context_matches(row: dict, entity: dict) -> bool:
    expected_context = [str(x).split(".")[-1].split("<", 1)[0] for x in row["context"]]
    return context_names(entity.get("sourcekitContext", [])) == expected_context


def entity_access_matches(row: dict, entity: dict) -> bool:
    expected_access = access_level(row["signature"])
    if expected_access is None:
        return False
    actual_access = str(entity.get("effective_access", "")).rsplit(".", 1)[-1]
    return actual_access == expected_access


def entity_matches(row: dict, entity: dict, *, module: str, live_interface_hash: str) -> bool:
    """Match one raw SourceKit entity to one audited row without USR de-duplication."""
    if row["module"] != module or row["sourceHash"] != live_interface_hash:
        return False
    if entity.get("line") != row["line"] or entity.get("is_implicit", False):
        return False
    if entity.get("name", "").strip("`").split("(", 1)[0] != declaration_name(row):
        return False
    if not entity_kind_matches(row, entity):
        return False
    if not entity_context_matches(row, entity) or not entity_access_matches(row, entity):
        return False
    return True


def unique_entity_usr(entities: list[dict]) -> str | None:
    """Return a link only for exactly one raw entity record; duplicates stay held."""
    if len(entities) != 1:
        return None
    usr = entities[0].get("usr")
    return usr if isinstance(usr, str) and usr else None


def cursor_result_usr(response_text: str) -> str | None:
    # Cursor responses and call-site responses use a root `key.usr` followed
    # by a comma; nested receiver records are more deeply indented. Match only
    # the root field and allow its dictionary separator.
    match = re.search(r'^  key\.usr: "([^"]+)"\s*,?$', response_text, re.M)
    return match.group(1) if match else None


def parse_compilerargs(request_text: str) -> list[str]:
    section = re.search(r"key\.compilerargs:\s*\[(.*?)\]", request_text, re.S)
    if not section:
        return []
    return [bytes(value, "utf-8").decode("unicode_escape") for value in re.findall(r'"((?:\\.|[^"\\])*)"', section.group(1))]


def request_identity_matches(request_text: str, *, interface: str, sdk: str, target: str, module: str,
                             request_kind: str = "source.request.indexsource") -> bool:
    def fields(name: str) -> list[str]:
        return re.findall(rf'^\s*key\.{name}: "([^"]*)"\s*,?\s*$', request_text, re.M)

    sourcefiles, names, request_kinds = fields("sourcefile"), fields("name"), re.findall(
        r"^\s*key\.request:\s*([^,\s]+)", request_text, re.M)
    compilerargs_sections = re.findall(r"^\s*key\.compilerargs:", request_text, re.M)
    if len(sourcefiles) != 1 or len(names) > 1 or len(request_kinds) != 1 or len(compilerargs_sections) != 1:
        return False

    args = parse_compilerargs(request_text)
    def option_value(option: str) -> str | None:
        positions = [i for i, value in enumerate(args) if value == option]
        if len(positions) != 1 or positions[0] + 1 >= len(args):
            return None
        return args[positions[0] + 1]

    try:
        return (
            request_kinds[0] == request_kind
            and sourcefiles[0] == interface
            and (not names or names[0] == interface)
            and args[0] == interface
            and option_value("-sdk") == sdk
            and option_value("-target") == target
            and option_value("-module-name") == module
        )
    except (ValueError, IndexError):
        return False
