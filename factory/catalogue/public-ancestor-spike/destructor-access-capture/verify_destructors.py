#!/usr/bin/env python3
"""Strict verifier for destructor cursor receipts; missing access stays unknown."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
EVIDENCE = HERE / "destructor-access-evidence.json"
FROZEN = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
RECON = Path("/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/f1-residuals/public-ancestor-v1/preliminary-reconstruction.json")
EXPECTED_LINK = "836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
EXPECTED_RECON = "58cfe1155ea19358637ca43c9ab90dfc183e78ea07f48248111ca22f72a9e65d"
EXPECTED_SOURCE = {
    "SwiftUI": "155b00c7d8fa9e9696b96b4bd3291b4c910207b480025d13ba6482f7b9940d38",
    "SwiftUICore": "4fb89ff3d972d507faee2bde0a7e81761a2cb9c744eaf94df810235918c7ac13",
}
REASON = "destructor source access semantics require explicit eligibility definition"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate(data: dict, root: Path = ROOT) -> list[str]:
    errors: list[str] = []
    if sha(FROZEN) != EXPECTED_LINK or data.get("inputs", {}).get("frozenLinkEvidence", {}).get("sha256") != "sha256:" + EXPECTED_LINK:
        errors.append("frozen link pin")
    if sha(RECON) != EXPECTED_RECON or data.get("inputs", {}).get("reconstruction", {}).get("sha256") != "sha256:" + EXPECTED_RECON:
        errors.append("reconstruction pin")
    if data.get("status") != "review-only" or data.get("promotionsMade") != 0 or data.get("heldReason") != REASON:
        errors.append("status/promotion")
    rows = data.get("rows")
    if not isinstance(rows, list) or len(rows) != 42:
        return errors + ["row count"]
    seen = set()
    for row in rows:
        module, line = row.get("module"), row.get("line")
        key = (module, line)
        if key in seen or module not in EXPECTED_SOURCE or not isinstance(line, int):
            errors.append(f"row key {key}"); continue
        seen.add(key)
        source = Path(row.get("source", {}).get("path", ""))
        try:
            source_bytes = source.read_bytes()
            lines = source_bytes.decode("utf-8").splitlines(keepends=True)
            source_line = lines[line - 1].rstrip("\r\n")
        except (OSError, UnicodeError, IndexError):
            errors.append(f"source read {key}"); continue
        if hashlib.sha256(source_bytes).hexdigest() != EXPECTED_SOURCE[module] or row.get("source", {}).get("sha256") != "sha256:" + EXPECTED_SOURCE[module]:
            errors.append(f"source hash {key}")
        if row.get("sourceLine") != source_line or "deinit" not in source_line or row.get("name") != "deinit":
            errors.append(f"source identity {key}")
        line_start = sum(len(s.encode("utf-8")) for s in lines[: line - 1])
        offset = line_start + len(source_line[: source_line.index("deinit")].encode("utf-8"))
        if row.get("lineStartByteOffset") != line_start or row.get("deinitByteOffset") != offset:
            errors.append(f"source offset {key}")
        cursor = row.get("cursor", {})
        fields = cursor.get("fields", {})
        if fields.get("kind") != "source.lang.swift.decl.function.destructor" or fields.get("name") != "deinit" or fields.get("line") != line or fields.get("modulename") != module or not fields.get("usr"):
            errors.append(f"cursor identity {key}")
        # SourceKit emitted no effective_access/accessibility field. Preserve unknown; reject inferred values.
        if cursor.get("accessibility") != {"status": "unknown", "keys": [], "values": {}}:
            errors.append(f"accessibility inference {key}")
        receipt = row.get("receipt", {})
        if receipt.get("exitCode") != 0 or receipt.get("stderr", {}).get("bytes") != 0:
            errors.append(f"receipt {key}")
        for entry_key in ("request", "response"):
            entry = row.get(entry_key, {})
            path = root / entry.get("path", "")
            expected = entry.get("sha256", "").removeprefix("sha256:")
            if not path.is_file() or sha(path) != expected or path.stat().st_size != entry.get("bytes"):
                errors.append(f"{entry_key} bytes {key}")
        response_path = root / row.get("response", {}).get("path", "")
        if response_path.is_file():
            raw = response_path.read_text(encoding="utf-8")
            for field in ("kind", "name", "usr", "modulename"):
                value = fields.get(field)
                needle = f'key.{field}: {value},' if field == "kind" else f'key.{field}: "{value}"'
                if needle not in raw:
                    errors.append(f"raw field binding {key} {field}")
            if f"key.line: {line}," not in raw:
                errors.append(f"raw field binding {key} line")
    if len(seen) != 42:
        errors.append("missing rows")
    tree = data.get("rawSymbolTree", {}).get("receipt", {})
    if tree.get("exitCode") != 0 or tree.get("stdin", {}).get("bytes", 0) == 0 or tree.get("stdout", {}).get("bytes", 0) == 0:
        errors.append("demangle receipt")
    return errors


def main() -> int:
    errors = validate(json.loads(EVIDENCE.read_text(encoding="utf-8")))
    if errors:
        raise SystemExit("; ".join(errors))
    print("destructor access capture valid; accessibility unknown for all rows")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
