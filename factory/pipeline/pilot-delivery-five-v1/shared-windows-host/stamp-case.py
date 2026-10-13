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
    text = text.replace("@@WITNESS@@", a.witness).replace("@@CENTERED@@", "true" if a.centered else "false").replace("@@DARK@@", "true" if a.dark else "false")
    assert "@@" not in text
    (src / "main.swift").write_text(text)
    shutil.copy(HERE / "FactoryViewport.swift", src / "FactoryViewport.swift")
    (pkg / "Package.swift").write_text(PACKAGE)
    print("stamped", pkg)


if __name__ == "__main__":
    main()
