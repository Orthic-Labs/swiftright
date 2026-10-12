#!/usr/bin/env python3
"""Pure source controls for Text F10 input admission.

Controls exercise production row/path/hash helpers with bounded in-memory
mutations; they never touch native inputs or grant qualification.
"""
from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("text_f10_reader", HERE / "prepare_text_f10_reader_input.py")
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def expect_hold(name: str, fn) -> None:
    try:
        fn()
    except mod.Hold:
        return
    raise AssertionError(f"fault accepted: {name}")


def check(mac_report: Path | None) -> None:
    digest = "a" * 64
    assert mod.hash_matches(digest, "sha256:" + digest)
    assert mod.hash_matches("sha256:" + digest, digest)
    assert not mod.hash_matches("sha256:" + "b" * 64, "sha256:" + digest)
    for value in ("../escape", "x\\y", "/absolute"):
        expect_hold("unsafe-path", lambda value=value: mod.safe_rel(value))

    base = {"files": [{"path": "native/plan.json", "bytes": 1, "sha256": digest}]}
    assert list(mod.manifest_rows(base)) == ["native/plan.json"]
    duplicate = {"files": [base["files"][0], dict(base["files"][0])]}
    expect_hold("duplicate-row", lambda: mod.manifest_rows(duplicate))
    bad_hash = {"files": [{"path": "native/plan.json", "bytes": 1, "sha256": "bad"}]}
    expect_hold("bad-row-hash", lambda: mod.manifest_rows(bad_hash))
    if mac_report is not None:
        measured = mod.validate_mac_report(mac_report)
        assert measured["qualification"] == "held"
        assert any("Mac original-process exit/cleanup evidence absent" in str(item) for item in measured["holds"])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mac-report", type=Path)
    args = parser.parse_args()
    check(args.mac_report)
    print("text F10 reader source controls: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
