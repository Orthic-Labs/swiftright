#!/usr/bin/env python3
"""Text-only wrapper over frozen same-group producer with local Text harness."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

PACKET = Path(__file__).resolve().parent
FROZEN_PRODUCER = PACKET / "capture_origin_text_r1.py"
FIXED_HARNESS = PACKET / "CaptureHost.swift"
FIXED_AX = PACKET / "AXClient.swift"
FROZEN_PRODUCER_SHA = "sha256:fe0a40047c6b87223ce092b8cc59d15af423d0f1551332cc56623e08bd72de94"
FIXED_HARNESS_SHA = "sha256:1309352243475b03196a93d3529d6d8e588d7ae076b2fc2f1ee0ddf44b4cc54f"
FIXED_AX_SHA = "sha256:9514c4ed6964a9a078058fc909ea72a89ad6363fd0662ed2e9369788af59c404"
TEXT_BLOCK = "swiftui.text.layout.baseline"


def bounded_hash(path: Path, limit: int = 64 * 1024 * 1024) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > limit:
        raise ValueError(f"bounded regular source required: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def bounded_json(path: Path) -> dict:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > 2 * 1024 * 1024:
        raise ValueError(f"bounded manifest required: {path}")
    return json.loads(path.read_bytes())


def load_frozen_producer():
    if bounded_hash(FROZEN_PRODUCER) != FROZEN_PRODUCER_SHA:
        raise ValueError("frozen Text producer drift")
    if bounded_hash(FIXED_HARNESS) != FIXED_HARNESS_SHA:
        raise ValueError("Text harness drift")
    if bounded_hash(FIXED_AX) != FIXED_AX_SHA:
        raise ValueError("Text AX helper drift")
    spec = importlib.util.spec_from_file_location("text_same_group_frozen", FROZEN_PRODUCER)
    if spec is None or spec.loader is None:
        raise ValueError("frozen Text producer import unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    # Frozen producer resolves harness & AX source beside __file__; point both
    # to this packet while preserving producer code bytes.
    module.__file__ = str(__file__)
    if TEXT_BLOCK not in tuple(module.PILOTS):
        raise ValueError("Text block missing from producer allowlist")
    return module


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--manifest", action="append", required=True)
    parser.add_argument("--expected-host-hash", required=True)
    known, _ = parser.parse_known_args(argv)
    if not known.expected_host_hash.startswith("sha256:") or len(known.expected_host_hash) != 71:
        raise ValueError("expected host hash must be full sha256 reference")
    for item in known.manifest:
        manifest = bounded_json(Path(item))
        if manifest.get("block") != TEXT_BLOCK or manifest.get("witnessType") != "Witness_swiftui_text_layout_baseline":
            raise ValueError("Text wrapper accepts only Text baseline manifests")
    return load_frozen_producer().main(argv)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, json.JSONDecodeError) as error:
        print(json.dumps({"status": "rejected", "reason": str(error), "nativeActions": 0}, sort_keys=True), file=sys.stderr)
        raise SystemExit(2)
