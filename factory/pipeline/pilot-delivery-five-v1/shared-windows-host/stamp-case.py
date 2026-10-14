#!/usr/bin/env python3
"""Stamps the shared capture host into a case package: main.swift (from CaptureHost.template.swift), FactoryViewport.swift and a
Package.swift that depends only on the product (SwiftRightHost + the runtime it re-exports). Everything else a case used to carry
(shape adapter, system-image provider/registry/assets, font adapter, body-font adapter, mappers, fill/geometry helpers) is deleted:
the product owns it (packages/SwiftRightHost). Witness.swift is never touched.
usage: stamp-case.py <case-dir> --witness 'Witness_x()' [--centered] [--dark]"""
import argparse, re, shutil
from pathlib import Path

HERE = Path(__file__).resolve().parent
KEEP = {"Witness.swift", "main.swift", "FactoryViewport.swift"}

PACKAGE = '''// swift-tools-version:6.0
import PackageDescription
// The product (SwiftRightHost = runtime + bridge + paint path) is staged once for all cases; pair.py replaces the token with the
// staged tree (factory/tools/stage-product.py: git archive of one commit). The renderer DLL is chosen per run (SWIFTRIGHT_RENDER_DLL).
let package = Package(name: "FactoryProbe", dependencies: [
    .package(name: "fresh-runtime", path: "@@PRODUCT_STAGE@@\\\\probes\\\\sr0-s\\\\fresh-runtime"),
    .package(path: "@@PRODUCT_STAGE@@\\\\packages\\\\SwiftRightHost")
], targets: [.executableTarget(name: "FactoryProbe", dependencies: [
    .product(name: "SwiftRightRuntime", package: "fresh-runtime"),
    .product(name: "SwiftRightHost", package: "SwiftRightHost")
])], swiftLanguageModes: [.v5])
'''


def centre_through_runtime(w):
    return ("ZStack(alignment: .center) { " + w + " }.frame(width: CGFloat(metrics.width) / CGFloat(scale), "
            "height: CGFloat(metrics.height) / CGFloat(scale), alignment: .center)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("case"); ap.add_argument("--witness", required=True)
    ap.add_argument("--centered", action="store_true"); ap.add_argument("--dark", action="store_true")
    a = ap.parse_args()
    pkg = Path(a.case).resolve() / "package"
    src = pkg / "Sources/FactoryProbe"
    assert (src / "Witness.swift").is_file(), "no Witness.swift"
    for f in sorted(src.iterdir()):
        if f.name not in KEEP:
            f.unlink()
    for extra in ("FactorySystemImageAssets.json",):
        (pkg / extra).unlink(missing_ok=True)
    text = (HERE / "CaptureHost.template.swift").read_text()
    witness = centre_through_runtime(a.witness) if a.centered else a.witness
    # --centered now centres through the runtime (a ZStack in a viewport-sized frame, as the Mac hosts do); the host never translates the finished tree (docs: blocks-6-10/pixel-ties/README.md)
    text = text.replace("@@WITNESS@@", witness).replace("@@CENTERED@@", "false").replace("@@DARK@@", "true" if a.dark else "false")
    assert "@@" not in text
    (src / "main.swift").write_text(text)
    shutil.copy(HERE / "FactoryViewport.swift", src / "FactoryViewport.swift")
    (pkg / "Package.swift").write_text(PACKAGE)
    print("stamped", pkg)
    # decision C12: the case's Mac host (mac-source, stamped beside this package by new-case.py / stamp-mac.py) must pin the window and displayScale to the capture scale
    mac_src = pkg.parent / "mac-source"
    unpinned = [str(f) for f in sorted(mac_src.rglob("*.swift")) if "@main" in f.read_text() and "ScalePin." not in f.read_text()] if mac_src.is_dir() else []
    if unpinned:
        raise SystemExit("Mac host does not pin the window/displayScale (decision C12; run factory/tools/mac-scale-pin/pin_hosts.py): " + ", ".join(unpinned))


if __name__ == "__main__":
    main()
