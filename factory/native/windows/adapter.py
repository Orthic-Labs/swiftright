"""Prepare observational Swift probes against immutable staged dependencies."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import re
from factory.core.artifacts import file_hash, write_artifact

STAGE = r"D:\Claude\sr0-r09"
DLL_HASH = "e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93"
WINDOWS_ROOT = r"D:\Claude\swiftright\factory\native\windows"

def prepare(manifest_path: Path, output: Path, *, renderer: bool = False) -> dict:
    manifest = json.loads(manifest_path.read_text())
    witness = manifest.get("witnessType", "")
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", witness):
        raise ValueError("invalid witness type")
    source_name = manifest["sourceFile"]
    if Path(source_name).name != source_name:
        raise ValueError("sourceFile must be basename")
    source = manifest_path.parent / source_name
    if file_hash(source) != manifest["sourceHash"]:
        raise ValueError("generated source hash mismatch")
    output = output.resolve()
    root = Path(__file__).resolve().parent
    if not output.is_relative_to(root) or output == root:
        raise ValueError("output must live below factory/native/windows")
    if output.exists():
        raise ValueError("output exists; use fresh directory")
    swift_source = source.read_text()
    if "import SwiftRightRuntime" not in swift_source:
        raise ValueError("Windows probe must import staged SwiftRightRuntime")
    src = output / "Sources" / "FactoryProbe"
    src.mkdir(parents=True)
    (src / "Witness.swift").write_text(swift_source)
    (src / "main.swift").write_text('''import Foundation
import SwiftRightRuntime
import SwiftRightBridge
// Observational layout only: fixed advance measurer is explicitly identified.
// No provider paint or native UIA is manufactured from runtime snapshots.
func node(_ n: ResolvedNode) -> [String: Any] {
    return ["id": n.id, "kind": n.kind,
      "text": n.text ?? "", "frame": [Double(n.frame.origin.x), Double(n.frame.origin.y), Double(n.frame.size.width), Double(n.frame.size.height)],
      "children": n.children.map(node)]
}
let payload = MainActor.assumeIsolated { () -> [String: Any] in
    let graph = Graph(''' + witness + '''())
    graph.rootProposal = ProposedViewSize(width: 320, height: 240)
    graph.flush()
    return ["channel": "runtime.layout.observational", "measurer": "FixedAdvanceTextMeasurer",
      "nativeWindowOpened": false, "root": graph.snapshot().map(node) ?? [:]]
}
let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
FileHandle.standardOutput.write(data)
''')
    if renderer:
        if manifest.get("environmentInputs", {}).get("colorScheme", "light") not in ("light", "dark"):
            raise ValueError("unsupported color scheme")
        template = Path(__file__).with_name("RendererHost.swift.in").read_text()
        (src / "main.swift").write_text(template.replace("__WITNESS__", witness).replace("__COLORSCHEME__", manifest.get("environmentInputs", {}).get("colorScheme", "light")))
    runtime = STAGE + r"\src\probes\sr0-s\fresh-runtime"
    bridge = STAGE + r"\src\packages\SwiftRightBridge"
    package = '''// swift-tools-version:6.0
import PackageDescription
let package = Package(name: "FactoryProbe", dependencies: [
    .package(path: RUNTIME), .package(path: BRIDGE)
], targets: [.executableTarget(name: "FactoryProbe", dependencies: [
    .product(name: "SwiftRightRuntime", package: "fresh-runtime"),
    .product(name: "SwiftRightBridge", package: "SwiftRightBridge")
])], swiftLanguageModes: [.v5])
'''.replace("RUNTIME", json.dumps(runtime)).replace("BRIDGE", json.dumps(bridge))
    (output / "Package.swift").write_text(package)
    plan = {"kind": "windows-observational-plan", "version": "0.1", "case": manifest["case"],
        "manifestHash": file_hash(manifest_path), "sourceHash": manifest["sourceHash"],
        "stage": STAGE, "rendererSha256": DLL_HASH,
        "compileExpectation": manifest["compileExpectation"], "replays": 20,
        "executionEligible": manifest.get("executionEligible", True), "hostMode": "renderer" if renderer else "headless",
        "environmentInputs": manifest.get("environmentInputs", {}),
        "nativeParity": "hold", "nativeHold": "Native capture under coordinated desktop lock required; headless layout is never native evidence.",
        "channelsUnavailable": ["provider.paint", "native.screenshot", "native.uia"],
        "sourceBindings": [{"path": str(p.relative_to(output)), "sha256": file_hash(p)} for p in sorted(output.rglob("*.swift"))]}
    write_artifact(output / "plan.json", plan)
    return plan

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--renderer", action="store_true", help="build actual renderer host; native execution requires desktop coordination")
    args = parser.parse_args(argv)
    print(json.dumps(prepare(args.manifest, args.output, renderer=args.renderer), sort_keys=True))
    return 0
