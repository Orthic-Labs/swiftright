#!/usr/bin/env python3
"""Rectangle producer wrapper bound to fixed viewport CaptureHost source."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
FROZEN_PRODUCER = REPO / "factory/pipeline/pilot-next-source-v1/mac-capture-same-group-v1/capture_origin_rectangle_r1.py"
V2_CONTEXT = Path(__file__).with_name("v2")
MODULE_CONTEXT = V2_CONTEXT / "producer-context.py"
FIXED_HARNESS = V2_CONTEXT / "CaptureHost.swift"
FIXED_AX_CLIENT = V2_CONTEXT / "AXClient.swift"
FROZEN_PRODUCER_SHA = "sha256:2772b71ec0b8bd2a8abb56d45b9ac592b29f29557487f229e74ab6d5689e2f39"
FIXED_HARNESS_SHA = "sha256:6a6dda83909673528e0c627e4dcba3a8512ee1994ba058fe0a8884fdcde7e7f4"


def bounded_hash(path: Path, limit: int = 64 * 1024 * 1024) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > limit:
        raise ValueError(f"bounded regular source required: {path}")
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return "sha256:" + digest.hexdigest()


def load_frozen_producer():
    if bounded_hash(FROZEN_PRODUCER) != FROZEN_PRODUCER_SHA:
        raise ValueError("frozen Rectangle producer drift")
    if bounded_hash(FIXED_HARNESS) != FIXED_HARNESS_SHA:
        raise ValueError("fixed viewport CaptureHost drift")
    if not MODULE_CONTEXT.is_file() or MODULE_CONTEXT.is_symlink():
        raise ValueError("v2 producer context missing")
    if bounded_hash(FIXED_AX_CLIENT) != "sha256:9514c4ed6964a9a078058fc909ea72a89ad6363fd0662ed2e9369788af59c404":
        raise ValueError("v2 AXClient drift")
    spec = importlib.util.spec_from_file_location("rectangle_same_group_frozen", FROZEN_PRODUCER)
    if spec is None or spec.loader is None:
        raise ValueError("frozen producer import unavailable")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    # Frozen producer resolves sibling CaptureHost.swift & AXClient.swift from module.__file__.
    module.__file__ = str(MODULE_CONTEXT.resolve())
    module.HARNESS = FIXED_HARNESS
    return module


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--expected-host-hash", required=True)
    known, _ = parser.parse_known_args(argv)
    if not known.expected_host_hash.startswith("sha256:") or len(known.expected_host_hash) != 71:
        raise ValueError("expected host hash must be full sha256 reference")
    producer = load_frozen_producer()
    # Original parser/lifecycle remains authoritative; wrapper changes only harness binding.
    return producer.main(argv)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError) as error:
        print(json.dumps({"status": "rejected", "reason": str(error), "nativeActions": 0}, sort_keys=True), file=sys.stderr)
        raise SystemExit(2)
