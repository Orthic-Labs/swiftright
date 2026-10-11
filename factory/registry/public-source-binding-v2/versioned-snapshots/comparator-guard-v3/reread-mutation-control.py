#!/usr/bin/env python3
"""Deterministically exercise verify-to-consumption frozen-input replacement."""
from __future__ import annotations

import hashlib
import importlib.util
import io
import json
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
COMPARATOR = Path(__file__).with_name("compare_final_candidate.py")
MANIFEST = ROOT / "factory/registry/public-source-binding-v1/manifest-usr-v1.json"
EXPECTED = ROOT / "factory/registry/public-source-binding-v1/expected-registry-membership.json"
CATALOGUE = ROOT / "factory/registry/public-source-binding-v1/archive/inputs/catalogue.json"


def sha(value: bytes) -> str:
    return "sha256:" + hashlib.sha256(value).hexdigest()


def mutate_manifest(raw: bytes) -> bytes:
    value = json.loads(raw.decode("utf-8"))
    value["blocks"][0]["symbols"][0] = "usr:verify-to-consumption-mutation"
    return (json.dumps(value, indent=2) + "\n").encode("utf-8")


def main() -> int:
    original_read = Path.read_bytes
    reads = {str(MANIFEST.resolve()): 0, str(EXPECTED.resolve()): 0}
    original_manifest = original_read(MANIFEST)
    original_expected = original_read(EXPECTED)

    def hooked_read(path: Path) -> bytes:
        key = str(path.resolve())
        if key == str(MANIFEST.resolve()):
            reads[key] += 1
            return original_manifest if reads[key] == 1 else mutate_manifest(original_manifest)
        if key == str(EXPECTED.resolve()):
            reads[key] += 1
            return original_expected
        return original_read(path)

    spec = importlib.util.spec_from_file_location("guard_v3", COMPARATOR)
    if spec is None or spec.loader is None:
        raise RuntimeError("unable to load comparator")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    with tempfile.TemporaryDirectory(prefix="f2-guard-v3-reread-") as temp:
        output = Path(temp) / "should-not-exist.json"
        sys.argv = [str(COMPARATOR), str(CATALOGUE), "--output", str(output)]
        Path.read_bytes = hooked_read
        captured = io.StringIO()
        try:
            with redirect_stdout(captured), redirect_stderr(captured):
                try:
                    module.main()
                    return_code = 0
                except SystemExit as exc:
                    return_code = int(exc.code) if isinstance(exc.code, int) else 1
                    if isinstance(exc.code, str):
                        print(exc.code)
        finally:
            Path.read_bytes = original_read
        output_created = output.exists()
    passed = (
        return_code != 0
        and reads[str(MANIFEST.resolve())] >= 2
        and "consumed frozen manifest bytes mismatch" in captured.getvalue()
        and not output_created
    )
    report = {
        "kind": "f2-public-source-binding-reread-mutation-control",
        "version": 1,
        "status": "controls-pass" if passed else "controls-failed",
        "comparatorPath": str(COMPARATOR.relative_to(ROOT)),
        "comparatorSha256": sha(COMPARATOR.read_bytes()),
        "manifestReads": reads[str(MANIFEST.resolve())],
        "expectedReads": reads[str(EXPECTED.resolve())],
        "mutatedConsumedManifestSha256": sha(mutate_manifest(original_manifest)),
        "frozenManifestSha256": sha(original_manifest),
        "returnCode": return_code,
        "outputCreated": output_created,
        "capturedError": captured.getvalue(),
    }
    out = Path(__file__).with_name("reread-mutation-control.json")
    out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
