#!/usr/bin/env python3
"""Stage fresh Circle Windows package from reviewed Rectangle source bindings."""
from __future__ import annotations
import argparse, hashlib, json, os, shutil, stat
from pathlib import Path

MAX_JSON = 4 * 1024 * 1024
MAX_FILE = 64 * 1024 * 1024
MAX_TOTAL = 256 * 1024 * 1024
CHUNK = 1024 * 1024
CIRCLE_WITNESS_SHA256 = "01f9fef3ab058a958bebf886191519e0102b05ff6b46acedd0d59a7aa8601f2e"

def regular(path: Path, limit: int) -> int:
    st = path.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_size > limit:
        raise ValueError(f"bounded regular file required: {path}")
    return st.st_size

def digest(path: Path, limit: int = MAX_FILE) -> tuple[int, str]:
    size = regular(path, limit)
    h = hashlib.sha256()
    total = 0
    with path.open("rb") as src:
        while chunk := src.read(CHUNK):
            total += len(chunk)
            if total > limit:
                raise ValueError(f"streamed file exceeds bound: {path}")
            h.update(chunk)
    if path.lstat().st_size != total or total != size:
        raise ValueError(f"file changed during hash: {path}")
    return total, h.hexdigest()

def load_json(path: Path) -> dict:
    regular(path, MAX_JSON)
    return json.loads(path.read_text(encoding="utf-8"))

def normalize_hash(value: object) -> str:
    return str(value).removeprefix("sha256:").lower()

def safe_relative(value: str) -> Path:
    p = Path(value)
    if not value or "\\" in value or p.is_absolute() or ":" in value or any(part in ("", ".", "..") for part in p.parts):
        raise ValueError(f"unsafe source binding: {value}")
    return p

def copy_stream(src: Path, dst: Path, size: int) -> None:
    if dst.exists() or dst.is_symlink():
        raise ValueError(f"fresh destination required: {dst}")
    dst.parent.mkdir(parents=True, exist_ok=True)
    copied = 0
    with src.open("rb") as inp, dst.open("xb") as out:
        while chunk := inp.read(CHUNK):
            out.write(chunk)
            copied += len(chunk)
            if copied > size:
                raise ValueError(f"copy exceeds bound: {src}")
    if copied != size or src.lstat().st_size != copied:
        raise ValueError(f"copy size drift: {src}")

def transformed_main(source: str) -> str:
    old = "Witness_shapes_rectangle_fill()"
    if source.count(old) != 1:
        raise ValueError("expected exactly one Rectangle witness call")
    source = source.replace(old, "Witness_circle_fixed()", 1)
    helper = '''
func factoryStderr(_ marker: String) {
    FileHandle.standardError.write(Data((marker + "\\n").utf8))
    fflush(stderr)
}
'''
    anchor = "import WinSDK\n"
    if source.count(anchor) != 1:
        raise ValueError("main import anchor missing")
    source = source.replace(anchor, anchor + helper, 1)
    replacements = (
        ("let bridge = try Bridge.load(path:", 'factoryStderr("FACTORY_BRIDGE_LOAD_BEGIN")\n        let bridge = try Bridge.load(path:'),
        ("let host = RendererHost(bridge, captureLeaseNanoseconds: captureLease)", 'factoryStderr("FACTORY_BRIDGE_LOAD_END")\n        let host = RendererHost(bridge, captureLeaseNanoseconds: captureLease)'),
        ("bridge.onReady = { window in MainActor.assumeIsolated { host.ready(window) } }", 'bridge.onReady = { window in factoryStderr("FACTORY_BRIDGE_ON_READY"); MainActor.assumeIsolated { host.ready(window) } }'),
        ('try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240)', 'factoryStderr("FACTORY_BRIDGE_RUN_BEGIN")\n        try bridge.run(title: "Alchemist FactoryProbe", width: 320, height: 240)\n        factoryStderr("FACTORY_BRIDGE_RUN_END")'),
    )
    for old, new in replacements:
        if source.count(old) != 1:
            raise ValueError(f"startup transform anchor count != 1: {old[:40]}")
        source = source.replace(old, new, 1)
    return source

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--source-package", type=Path, required=True)
    ap.add_argument("--source-plan", type=Path, required=True)
    ap.add_argument("--circle-witness", type=Path, required=True)
    ap.add_argument("--prebuild-manifest", type=Path, required=True)
    ap.add_argument("--output-package", type=Path, required=True)
    ap.add_argument("--output-manifest", type=Path, required=True)
    args = ap.parse_args()
    package = args.source_package.resolve()
    plan_path = args.source_plan.resolve()
    witness_path = args.circle_witness.resolve()
    prebuild_manifest_path = args.prebuild_manifest.resolve()
    output = args.output_package.resolve()
    if output.exists():
        raise ValueError("fresh output package required")
    plan = load_json(plan_path)
    if plan_path.name != "plan-final-v3.json":
        raise ValueError("exact reviewed Rectangle plan-final-v3.json required")
    if plan.get("kind") != "factory-rectangle-compiler-plan-v2" or plan.get("phase") != "final":
        raise ValueError("reviewed Rectangle final plan required")
    rows = list(plan.get("sourceBindings", []))
    if not rows or len(rows) > 256:
        raise ValueError("bounded source binding set required")
    witness_size, witness_hash = digest(witness_path, MAX_FILE)
    if witness_hash != CIRCLE_WITNESS_SHA256:
        raise ValueError("exact Circle witness hash required")
    witness_text = witness_path.read_text(encoding="utf-8")
    required = ("Circle()", "Color.blue", ".frame(width: 40, height: 40)", ".light")
    if any(token not in witness_text for token in required):
        raise ValueError("Circle witness contract mismatch")
    prebuild_manifest = load_json(prebuild_manifest_path)
    if (not {"candidate", "qualification", "case", "sourceHash"}.issubset(prebuild_manifest)
            or prebuild_manifest.get("candidate") != "swiftui.circle.fixed.pilot-next"
            or prebuild_manifest.get("qualification") != "prebuild"
            or prebuild_manifest.get("case") is not None
            or normalize_hash(prebuild_manifest.get("sourceHash")) != witness_hash):
        raise ValueError("Circle prebuild metadata contract mismatch")
    total = 0
    copied = []
    seen = set()
    donor_manifest_row = None
    for row in rows:
        rel = safe_relative(str(row.get("path", "")))
        if rel.as_posix() in seen:
            raise ValueError("duplicate source binding")
        seen.add(rel.as_posix())
        src = package / rel
        size = regular(src, MAX_FILE)
        expected = str(row.get("sha256", "")).removeprefix("sha256:").lower()
        actual_size, actual_hash = digest(src, MAX_FILE)
        is_donor_manifest = rel.as_posix() == "witness.manifest.json"
        if (not is_donor_manifest and expected != actual_hash) or ("bytes" in row and int(row["bytes"]) != actual_size):
            raise ValueError(f"source binding drift: {rel}")
        total += actual_size
        if total > MAX_TOTAL:
            raise ValueError("source binding total exceeds bound")
        # Witness & main are emitted once below after exact transformations.
        if is_donor_manifest:
            donor_manifest_row = {"path": rel.as_posix(), "bytes": actual_size, "expectedSha256": "sha256:" + expected, "actualSha256": "sha256:" + actual_hash, "bindingMatched": False}
        elif rel.as_posix() not in {"Sources/FactoryProbe/main.swift", "Sources/FactoryProbe/Witness.swift"}:
            copy_stream(src, output / rel, size)
        copied.append(({"path": rel.as_posix(), "bytes": size, "sha256": "sha256:" + actual_hash}
                       if not is_donor_manifest else {"path": rel.as_posix(), "bytes": size, "expectedSha256": "sha256:" + expected, "actualSha256": "sha256:" + actual_hash, "bindingMatched": False, "replaced": True}))
    required_sources = {"Sources/FactoryProbe/main.swift", "Sources/FactoryProbe/Witness.swift"}
    if not required_sources.issubset(seen):
        raise ValueError("main.swift and Witness.swift must be explicit source bindings")
    if donor_manifest_row is None:
        raise ValueError("witness.manifest.json donor binding required")
    main_path = output / "Sources" / "FactoryProbe" / "main.swift"
    witness_out = output / "Sources" / "FactoryProbe" / "Witness.swift"
    source_main = package / "Sources" / "FactoryProbe" / "main.swift"
    regular(source_main, MAX_FILE)
    transformed = transformed_main(source_main.read_text(encoding="utf-8"))
    main_path.parent.mkdir(parents=True, exist_ok=True)
    with main_path.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(transformed)
    copy_stream(witness_path, witness_out, witness_size)
    replacement_manifest_bytes = json.dumps(prebuild_manifest, indent=2) + "\n"
    replacement_manifest = output / "witness.manifest.json"
    replacement_manifest.parent.mkdir(parents=True, exist_ok=True)
    with replacement_manifest.open("x", encoding="utf-8", newline="\n") as stream:
        stream.write(replacement_manifest_bytes)
    replacement_manifest_size, replacement_manifest_hash = digest(replacement_manifest, MAX_JSON)
    main_size2, main_hash2 = digest(main_path, MAX_FILE)
    witness_size2, witness_hash2 = digest(witness_out, MAX_FILE)
    output_manifest = {
        "kind": "factory-circle-windows-source-package-v1",
        "status": "SOURCE_ONLY",
        "candidate": "swiftui.circle.fixed.pilot-next",
        "basePlan": {"path": str(plan_path), "sha256": "sha256:" + digest(plan_path, MAX_JSON)[1]},
        "baseSourceBindings": copied,
        "transforms": {
            "mainWitnessCall": {"from": "Witness_shapes_rectangle_fill()", "to": "Witness_circle_fixed()", "count": 1, "sha256": "sha256:" + main_hash2, "bytes": main_size2},
            "circleWitness": {"path": str(witness_path), "sha256": "sha256:" + witness_hash2, "bytes": witness_size2, "exact": True},
            "prebuildManifestReplacement": {"path": "witness.manifest.json", "replacementSha256": "sha256:" + replacement_manifest_hash, "replacementBytes": replacement_manifest_size, "metadataSha256": "sha256:" + digest(prebuild_manifest_path, MAX_JSON)[1], "replacesDonor": donor_manifest_row},
            "startupMarkers": ["FACTORY_BRIDGE_LOAD_BEGIN", "FACTORY_BRIDGE_LOAD_END", "FACTORY_BRIDGE_ON_READY", "FACTORY_BRIDGE_RUN_BEGIN", "FACTORY_BRIDGE_RUN_END"],
        },
        "effects": {"compilerActions": 0, "nativeActions": 0, "remoteActions": 0, "guiActions": 0, "lockActions": 0},
    }
    if args.output_manifest.exists():
        raise ValueError("fresh output manifest required")
    args.output_manifest.parent.mkdir(parents=True, exist_ok=True)
    args.output_manifest.write_text(json.dumps(output_manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
