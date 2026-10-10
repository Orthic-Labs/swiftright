#!/usr/bin/env python3
"""Validate factory artifacts with local Draft 2020-12 schemas only."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import re
import sys
from pathlib import Path
from typing import Any

from jsonschema import Draft202012Validator, FormatChecker
from jsonschema.exceptions import SchemaError
from referencing import Registry, Resource
from referencing.jsonschema import DRAFT202012

try:
    from .canonical_json import CanonicalJSONError, load
except ImportError:  # Direct script invocation.
    from canonical_json import CanonicalJSONError, load


class ValidationSetupError(ValueError):
    pass


_RFC3339 = re.compile(
    r"^\d{4}-\d{2}-\d{2}[Tt]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[Zz]|[+-]\d{2}:\d{2})$"
)
_FORMAT_CHECKER = FormatChecker()


@_FORMAT_CHECKER.checks("date-time")
def _is_rfc3339(value: object) -> bool:
    """Supply date-time checking when optional jsonschema extras are absent."""
    if not isinstance(value, str) or not _RFC3339.fullmatch(value):
        return False
    normalized = value.replace("t", "T").replace("z", "+00:00")
    try:
        datetime.fromisoformat(normalized)
    except ValueError:
        return False
    return True


def load_registry(schema_dir: str | Path) -> tuple[Registry, dict[str, dict[str, Any]]]:
    """Load every local schema; Registry has no remote retrieval callback."""
    documents: dict[str, dict[str, Any]] = {}
    registry = Registry()
    for path in sorted(Path(schema_dir).glob("*.schema.json")):
        try:
            contents = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise ValidationSetupError(f"cannot read schema {path}: {exc}") from exc
        identifier = contents.get("$id")
        if not isinstance(identifier, str) or not identifier:
            raise ValidationSetupError(f"schema {path} has no string $id")
        if identifier in documents:
            raise ValidationSetupError(f"duplicate schema $id {identifier}")
        try:
            Draft202012Validator.check_schema(contents)
        except SchemaError as exc:
            raise ValidationSetupError(f"invalid schema {path}: {exc.message}") from exc
        documents[identifier] = contents
        registry = registry.with_resource(identifier, Resource(contents, DRAFT202012))
    if not documents:
        raise ValidationSetupError(f"no schemas found in {schema_dir}")
    return registry, documents


def schema_for_artifact(
    artifact: Any, documents: dict[str, dict[str, Any]], requested: str | None = None
) -> str:
    if requested:
        identifier = requested
    else:
        if not isinstance(artifact, dict):
            raise ValidationSetupError("artifact root must be an object")
        kind = artifact.get("kind")
        version = artifact.get("version")
        if not isinstance(kind, str) or not isinstance(version, str):
            raise ValidationSetupError("artifact needs string kind and version")
        candidates = [
            candidate
            for candidate, contents in documents.items()
            if contents.get("properties", {}).get("kind", {}).get("const") == kind
            and contents.get("properties", {}).get("version", {}).get("const") == version
        ]
        if len(candidates) != 1:
            raise ValidationSetupError(f"no unique local root schema for {kind!r} version {version!r}")
        identifier = candidates[0]
        declared = artifact.get("$schema")
        if declared is not None:
            if not isinstance(declared, str):
                raise ValidationSetupError("artifact $schema must be a string")
            if declared != identifier:
                raise ValidationSetupError(
                    f"artifact $schema does not match local root schema {identifier}"
                )
    if identifier not in documents:
        raise ValidationSetupError(f"schema identifier is not local: {identifier}")
    return identifier


def validate_artifact(
    artifact: Any, registry: Registry, documents: dict[str, dict[str, Any]], schema_id: str | None = None
) -> list[str]:
    identifier = schema_for_artifact(artifact, documents, schema_id)
    validator = Draft202012Validator(
        documents[identifier], registry=registry, format_checker=_FORMAT_CHECKER
    )
    return [
        error.message
        for error in sorted(validator.iter_errors(artifact), key=lambda item: list(item.absolute_path))
    ]


def main(argv: list[str] | None = None) -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description="validate factory artifact JSON against local schemas")
    parser.add_argument("files", nargs="+", type=Path)
    parser.add_argument("--schema-dir", type=Path, default=root / "spec" / "schema")
    parser.add_argument("--schema", help="local schema $id, applied to every input")
    arguments = parser.parse_args(argv)
    try:
        registry, documents = load_registry(arguments.schema_dir)
    except (ValidationSetupError, OSError) as exc:
        print(f"schema-validate: {exc}", file=sys.stderr)
        return 2

    valid = True
    for path in arguments.files:
        try:
            errors = validate_artifact(load(path), registry, documents, arguments.schema)
        except (CanonicalJSONError, ValidationSetupError, OSError) as exc:
            errors = [str(exc)]
        if errors:
            valid = False
            for error in errors:
                print(f"{path}: {error}", file=sys.stderr)
        else:
            print(f"{path}: valid")
    return 0 if valid else 2


if __name__ == "__main__":
    raise SystemExit(main())
