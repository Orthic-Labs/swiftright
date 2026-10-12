#!/usr/bin/env python3
"""Offline source controls for Circle package transform & Windows compile shape."""
from __future__ import annotations
import copy, hashlib, json, stat, sys
from pathlib import Path

MAX_JSON = 4 * 1024 * 1024
MAX_TEXT = 64 * 1024 * 1024
CHUNK = 1024 * 1024

def bounded(path: Path, limit: int) -> bytes:
    st = path.lstat()
    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode) or st.st_size > limit:
        raise ValueError(f"bounded regular file required: {path}")
    out = bytearray()
    with path.open("rb") as stream:
        while chunk := stream.read(CHUNK):
            out.extend(chunk)
    return bytes(out)

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

def load(path: Path) -> dict:
    return json.loads(bounded(path, MAX_JSON).decode("utf-8"))

def validate(package: Path, manifest: dict, main: str | None = None, witness: bytes | None = None, build: str | None = None, replacement_bytes_override: bytes | None = None) -> None:
    transform = manifest["transforms"]
    replacement_lineage = transform["prebuildManifestReplacement"]
    donor = replacement_lineage.get("replacesDonor", {})
    if (replacement_lineage.get("path") != "witness.manifest.json"
            or donor.get("path") != "witness.manifest.json"
            or donor.get("bindingMatched") is not False
            or len(replacement_lineage.get("replacementSha256", "").removeprefix("sha256:")) != 64
            or len(donor.get("expectedSha256", "").removeprefix("sha256:")) != 64
            or len(donor.get("actualSha256", "").removeprefix("sha256:")) != 64):
        raise ValueError("prebuild manifest replacement lineage invalid")
    main_path = package / "Sources" / "FactoryProbe" / "main.swift"
    witness_path = package / "Sources" / "FactoryProbe" / "Witness.swift"
    main = main if main is not None else bounded(main_path, MAX_TEXT).decode("utf-8")
    witness = witness if witness is not None else bounded(witness_path, MAX_TEXT)
    replacement_bytes = replacement_bytes_override if replacement_bytes_override is not None else bounded(package / "witness.manifest.json", MAX_JSON)
    if sha(replacement_bytes) != replacement_lineage["replacementSha256"].removeprefix("sha256:"):
        raise ValueError("prebuild replacement hash mismatch")
    replacement_doc = json.loads(replacement_bytes.decode("utf-8"))
    if (replacement_doc.get("candidate") != "swiftui.circle.fixed.pilot-next"
            or replacement_doc.get("qualification") != "prebuild"
            or "case" not in replacement_doc or replacement_doc.get("case") is not None
            or replacement_doc.get("sourceHash", "").removeprefix("sha256:") != sha(witness)):
        raise ValueError("prebuild replacement contract invalid")
    if main.count("Witness_circle_fixed()") != 1 or "Witness_shapes_rectangle_fill()" in main:
        raise ValueError("Circle witness call transform invalid")
    markers = transform["startupMarkers"]
    positions = [main.index(f'factoryStderr("{marker}")') for marker in markers]
    if positions != sorted(positions) or len(set(positions)) != len(positions):
        raise ValueError("startup marker order/count invalid")
    if sha(witness) != transform["circleWitness"]["sha256"].removeprefix("sha256:"):
        raise ValueError("Circle witness hash mismatch")
    witness_text = witness.decode("utf-8")
    if any(token not in witness_text for token in ("Circle()", "Color.blue", ".frame(width: 40, height: 40)", ".light")):
        raise ValueError("Circle witness semantics invalid")
    if sha(main.encode("utf-8")) != transform["mainWitnessCall"]["sha256"].removeprefix("sha256:"):
        raise ValueError("transformed main hash mismatch")
    if build is None:
        build = Path(__file__).with_name("build-circle-owned-v1.ps1").read_text(encoding="utf-8")
    for token in ("swiftui.circle.fixed.pilot-next", "--package-path", "--scratch-path", "--jobs 1", "-Xswiftc -num-threads -Xswiftc 1", "maxFrontendThreads=1", "factory-circle"):
        if token not in build:
            raise ValueError(f"compile command shape missing: {token}")

def expect_reject(label: str, func) -> None:
    try:
        func()
    except (AssertionError, KeyError, ValueError, IndexError):
        return
    raise AssertionError(f"fault accepted: {label}")

def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("package manifest")
    package = Path(sys.argv[1]); manifest_path = Path(sys.argv[2])
    manifest = load(manifest_path)
    validate(package, manifest)
    main_text = bounded(package / "Sources" / "FactoryProbe" / "main.swift", MAX_TEXT).decode("utf-8")
    witness = bounded(package / "Sources" / "FactoryProbe" / "Witness.swift", MAX_TEXT)
    build = (Path(__file__).with_name("build-circle-owned-v1.ps1")).read_text(encoding="utf-8")
    faults = []
    bad_main = main_text.replace('Witness_circle_fixed()', 'Witness_shapes_rectangle_fill()', 1)
    expect_reject("wrong witness transform", lambda: validate(package, manifest, main=bad_main, witness=witness, build=build)); faults.append("wrong witness transform")
    bad_marker = main_text.replace('factoryStderr("FACTORY_BRIDGE_ON_READY")', '', 1)
    expect_reject("missing startup marker", lambda: validate(package, manifest, main=bad_marker, witness=witness, build=build)); faults.append("missing startup marker")
    expect_reject("wrong Circle witness bytes", lambda: validate(package, manifest, main=main_text, witness=b"Rectangle()", build=build)); faults.append("wrong Circle witness bytes")
    bad_manifest = copy.deepcopy(manifest); bad_manifest["transforms"]["mainWitnessCall"]["sha256"] = "sha256:" + ("0" * 64)
    expect_reject("transformed hash drift", lambda: validate(package, bad_manifest, main=main_text, witness=witness, build=build)); faults.append("transformed hash drift")
    bad_build = build.replace("--jobs 1", "--jobs 2", 1)
    expect_reject("compile command parallelism", lambda: validate(package, manifest, main=main_text, witness=witness, build=bad_build)); faults.append("compile command parallelism")
    bad_frontend_missing = build.replace("-Xswiftc -num-threads -Xswiftc 1", "-Xswiftc 1", 1)
    expect_reject("frontend thread cap missing", lambda: validate(package, manifest, main=main_text, witness=witness, build=bad_frontend_missing)); faults.append("frontend thread cap missing")
    bad_frontend_two = build.replace("-Xswiftc 1", "-Xswiftc 2", 1)
    expect_reject("frontend thread count two", lambda: validate(package, manifest, main=main_text, witness=witness, build=bad_frontend_two)); faults.append("frontend thread count two")
    bad_replacement = json.loads(bounded(package / "witness.manifest.json", MAX_JSON).decode("utf-8")); bad_replacement["candidate"] = "swiftui.shapes.rectangle-fill.pilot-next"
    bad_replacement_bytes = (json.dumps(bad_replacement, indent=2) + "\n").encode("utf-8")
    bad_lineage = copy.deepcopy(manifest); bad_lineage["transforms"]["prebuildManifestReplacement"]["replacementSha256"] = "sha256:" + sha(bad_replacement_bytes)
    expect_reject("wrong prebuild candidate", lambda: validate(package, bad_lineage, main=main_text, witness=witness, build=build, replacement_bytes_override=bad_replacement_bytes)); faults.append("wrong prebuild candidate")
    print(json.dumps({"status": "SOURCE_CONTROLS_PASS", "positive": True, "faults": faults, "effects": {"compilerActions": 0, "nativeActions": 0, "remoteActions": 0, "guiActions": 0, "lockActions": 0}}, sort_keys=True))
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
