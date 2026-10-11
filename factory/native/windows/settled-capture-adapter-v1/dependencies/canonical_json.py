#!/usr/bin/env python3
"""Canonical JSON for hash-critical factory artifacts.

Convention: UTF-8, compact separators, unescaped Unicode & Unicode code-point
key order.  Floats are forbidden: finite decimal measurements use a tagged
object and non-finite values use a different tag.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any


class CanonicalJSONError(ValueError):
    """Input cannot be represented by factory canonical JSON."""


_DECIMAL = re.compile(r"-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$")
_SPECIALS = frozenset(("NaN", "+Infinity", "-Infinity"))


def _reject_constant(value: str) -> None:
    raise CanonicalJSONError(f"JSON constant {value!r} is not allowed")


def _reject_float(value: str) -> None:
    raise CanonicalJSONError(
        f"bare JSON float {value!r} is not allowed; use a $decimal object"
    )


def _duplicate_key(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise CanonicalJSONError(f"duplicate object key {key!r}")
        result[key] = value
    return result


def loads(text: str | bytes) -> Any:
    """Read strict canonical-compatible JSON, rejecting ambiguous syntax."""
    try:
        value = json.loads(
            text,
            object_pairs_hook=_duplicate_key,
            parse_float=_reject_float,
            parse_constant=_reject_constant,
        )
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise CanonicalJSONError(str(exc)) from exc
    return normalize(value)


def load(path: str | Path) -> Any:
    return loads(Path(path).read_bytes())


def _string(value: str, where: str) -> None:
    if any(0xD800 <= ord(character) <= 0xDFFF for character in value):
        raise CanonicalJSONError(f"Unicode surrogate in {where}")


def _canonical_decimal(value: str) -> str:
    if not _DECIMAL.fullmatch(value):
        raise CanonicalJSONError(f"invalid $decimal {value!r}")
    try:
        decimal = Decimal(value)
    except InvalidOperation as exc:  # Defensive; grammar above is restrictive.
        raise CanonicalJSONError(f"invalid $decimal {value!r}") from exc
    if not decimal.is_finite():
        raise CanonicalJSONError(f"invalid $decimal {value!r}")
    if decimal.is_zero():
        return "0"
    plain = format(decimal, "f")
    if "." in plain:
        plain = plain.rstrip("0").rstrip(".")
    return plain


def normalize(value: Any) -> Any:
    """Validate a JSON value & normalize tagged decimal spelling."""
    if value is None or isinstance(value, bool) or isinstance(value, int):
        return value
    if isinstance(value, float):
        raise CanonicalJSONError("bare JSON float is not allowed")
    if isinstance(value, str):
        _string(value, "string")
        return value
    if isinstance(value, list):
        return [normalize(item) for item in value]
    if not isinstance(value, dict):
        raise CanonicalJSONError(f"unsupported JSON value {type(value).__name__}")

    for key in value:
        if not isinstance(key, str):
            raise CanonicalJSONError("object key is not a string")
        _string(key, "object key")

    tag_keys = {"$decimal", "$number"}.intersection(value)
    if tag_keys:
        if set(value) == {"$decimal"}:
            decimal = value["$decimal"]
            if not isinstance(decimal, str):
                raise CanonicalJSONError("$decimal must be a string")
            return {"$decimal": _canonical_decimal(decimal)}
        if set(value) == {"$number"}:
            number = value["$number"]
            if not isinstance(number, str) or number not in _SPECIALS:
                raise CanonicalJSONError("invalid $number")
            return {"$number": number}
        raise CanonicalJSONError("ambiguous or invalid tagged object")
    return {key: normalize(item) for key, item in value.items()}


def dumps(value: Any) -> str:
    """Return canonical compact JSON text, without an output newline."""
    return json.dumps(
        normalize(value),
        ensure_ascii=False,
        allow_nan=False,
        sort_keys=True,
        separators=(",", ":"),
    )


def dump_bytes(value: Any) -> bytes:
    return dumps(value).encode("utf-8")


def sha256(value: Any) -> str:
    return "sha256:" + hashlib.sha256(dump_bytes(value)).hexdigest()


def _read_argument(path: str | None) -> Any:
    return loads(sys.stdin.buffer.read() if path is None else Path(path).read_bytes())


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="canonical JSON encoder & SHA-256")
    parser.add_argument("mode", choices=("canonical", "hash"))
    parser.add_argument("path", nargs="?", help="JSON file; defaults to stdin")
    arguments = parser.parse_args(argv)
    try:
        value = _read_argument(arguments.path)
        output = dumps(value) if arguments.mode == "canonical" else sha256(value)
    except (CanonicalJSONError, OSError) as exc:
        print(f"canonical-json: {exc}", file=sys.stderr)
        return 2
    print(output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
