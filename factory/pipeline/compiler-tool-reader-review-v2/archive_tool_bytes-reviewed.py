"""Extract exact archived Mac compiler-tool bytes without reading current tools."""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
V1 = HERE.parent / "seed-origin-actual-v1"
SHA_XCRUN = "sha256:bbe7671518a3905f9d3fce54312fbc77c2876b0d62aca74a0688fa869d31a8a9"
SHA_FRONTEND = "sha256:84b410d8143298f90ab0b721d488dab90e2fdbf23577ae6186162832a1155cb7"

def digest(raw: bytes) -> str:
    return "sha256:" + hashlib.sha256(raw).hexdigest()

def path_for(value: str, root: Path) -> Path:
    p = Path(value)
    if p.is_absolute() or ".." in p.parts:
        raise ValueError("archive path must be relative and local")
    out = (root / p).resolve()
    if not out.is_relative_to(root.resolve()):
        raise ValueError("archive path escapes archive root")
    return out

def archive_bytes(entry: dict[str, object], *, archive_root: Path = HERE, archive_path: Path | None = None) -> bytes:
    """Read one archive member, checking compressed & reconstructed hashes."""
    value = entry["archivePath"]
    if not isinstance(value, str):
        raise ValueError("archivePath must be string")
    path = archive_path or path_for(value, archive_root)
    compressed = path.read_bytes()
    expected_compressed = entry.get("archiveSha256")
    expected_compressed_bytes = entry.get("archiveBytes")
    if expected_compressed_bytes is not None and len(compressed) != expected_compressed_bytes:
        raise ValueError(f"compressed byte mismatch: {value}")
    if expected_compressed is not None and digest(compressed) != expected_compressed:
        raise ValueError(f"compressed hash mismatch: {value}")
    if entry["compression"] == "gzip":
        raw = gzip.decompress(compressed)
    elif entry["compression"] == "none":
        raw = compressed
    else:
        raise ValueError("unsupported compression")
    if len(raw) != entry["bytes"] or digest(raw) != entry["sha256"]:
        raise ValueError(f"reconstructed byte mismatch: {value}")
    return raw

def receipt_refs() -> tuple[set[str], set[str]]:
    xcrun: set[str] = set()
    frontend: set[str] = set()
    for receipt_path in sorted(V1.glob("swiftui.*/compiler-receipt.json")) + [V1 / "ax-compiler-receipt.json"]:
        receipt = json.loads(receipt_path.read_text())
        compiler = receipt["compiler"]
        xcrun.add(compiler["xcrunHash"])
        frontend.add(compiler["realToolBefore"]["sha256"])
    return xcrun, frontend

def entries() -> list[dict[str, object]]:
    xcrun_refs, frontend_refs = receipt_refs()
    if xcrun_refs != {SHA_XCRUN} or frontend_refs != {SHA_FRONTEND}:
        raise ValueError("receipt tool identities disagree or differ from pins")
    return [
        {
            "requestedPath": "/usr/bin/xcrun",
            "logicalPath": "/usr/bin/xcrun",
            "realPath": "/usr/bin/xcrun",
            "archivePath": "tools/xcrun",
            "compression": "none",
            "bytes": 199024,
            "sha256": SHA_XCRUN,
            "archiveBytes": 199024,
            "archiveSha256": SHA_XCRUN,
        },
        {
            "requestedPath": "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend",
            "logicalPath": "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc",
            "realPath": "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend",
            "archivePath": "tools/swift-frontend.gz",
            "compression": "gzip",
            "bytes": 173118384,
            "sha256": SHA_FRONTEND,
            "archiveBytes": 60527695,
            "archiveSha256": "sha256:c7c2a62d3bacfdb800574b882f8089c80a7a8c7763600952cd52131b2f1de71e",
        },
    ]

def write_exact(path: Path, raw: bytes) -> str:
    """Create or reuse exact output; never overwrite divergent bytes."""
    if path.exists():
        if path.read_bytes() != raw or path.stat().st_mode & 0o777 != 0o644:
            raise ValueError(f"refusing reuse of divergent bytes/mode: {path}")
        return "REUSED_EXACT"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(raw)
    path.chmod(0o644)
    return "WRITTEN"

def reader_config() -> dict[str, object]:
    return {
        "version": 1,
        "macRoots": ["."],
        "windowsArchives": {},
        "macPathMap": {
            "/usr/bin/xcrun": "xcrun",
            "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc": "swift-frontend",
            "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend": "swift-frontend",
        },
    }

def verify_faults(specs: list[dict[str, object]]) -> dict[str, str]:
    results: dict[str, str] = {}
    with tempfile.TemporaryDirectory(prefix="compiler-tool-archive-faults-") as tmp:
        temp = Path(tmp)
        x = specs[0]
        original = path_for(str(x["archivePath"]), HERE).read_bytes()
        tampered_path = temp / "xcrun-tampered"
        tampered_path.write_bytes(bytes([original[0] ^ 1]) + original[1:])
        try:
            archive_bytes(x, archive_path=tampered_path)
        except ValueError:
            results["tampered-xcrun"] = "REJECTED"
        else:
            results["tampered-xcrun"] = "FAILED"
        compressed = path_for("tools/swift-frontend.gz", HERE).read_bytes()
        truncated_path = temp / "swift-frontend-truncated.gz"
        truncated_path.write_bytes(compressed[:-1])
        try:
            archive_bytes(specs[1], archive_path=truncated_path)
        except (EOFError, gzip.BadGzipFile, OSError, ValueError):
            results["truncated-swift-frontend"] = "REJECTED"
        else:
            results["truncated-swift-frontend"] = "FAILED"
    try:
        archive_bytes({**specs[0], "archivePath": "../seed-origin-actual-v1/fault-controls.json"})
    except ValueError:
        results["path-traversal"] = "REJECTED"
    else:
        results["path-traversal"] = "FAILED"
    return results

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, default=HERE / "scratch/internal/cache-v3")
    args = parser.parse_args()
    specs = entries()
    extracted: list[dict[str, object]] = []
    for spec, name in zip(specs, ("xcrun", "swift-frontend")):
        raw = archive_bytes(spec)
        action = write_exact(args.output_dir / name, raw)
        extracted.append({"path": name, "bytes": len(raw), "sha256": digest(raw), "mode": "0644"})
    config_path = args.output_dir / "reader_config.json"
    config_raw = json.dumps(reader_config(), indent=2, sort_keys=True).encode() + b"\n"
    config_action = write_exact(config_path, config_raw)
    faults = verify_faults(specs)
    if any(value != "REJECTED" for value in faults.values()):
        raise SystemExit(f"fault controls failed: {faults}")
    receipt = {
        "version": 1,
        "status": "PASS",
        "currentToolReadsDuringReplay": 0,
        "nativeExecutions": 0,
        "extracted": extracted,
        "readerConfig": {"path": "reader_config.json", "sha256": digest(config_raw)},
        "faultControls": faults,
    }
    receipt_raw = json.dumps(receipt, indent=2, sort_keys=True).encode() + b"\n"
    write_exact(args.output_dir / "verification-receipt.json", receipt_raw)
    print(json.dumps(receipt, indent=2, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
