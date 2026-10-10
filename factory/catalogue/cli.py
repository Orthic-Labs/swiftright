from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path

from .catalogue import MODULES, audit_interfaces, make_catalogue, run_extraction, write_canonical
from .audit_v2 import audit_v2, audit_v3, audit_v4
from .audit_v5 import audit_v5


def _interface_paths(sdk: Path) -> list[Path]:
    root = sdk / "System/Library/Frameworks"
    paths = []
    for module in MODULES:
        framework = root / f"{module}.framework"
        paths.extend(sorted((framework / "Versions/A/Modules" / f"{module}.swiftmodule").glob("arm64e-apple-macos.swiftinterface")))
    if len(paths) != 2:
        raise FileNotFoundError(f"expected SwiftUI & SwiftUICore arm64e macOS .swiftinterface files; found {len(paths)}")
    return paths


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="python -m factory.catalogue")
    sub = parser.add_subparsers(dest="command", required=True)
    extract = sub.add_parser("extract", help="extract, merge, audit, and write catalogue evidence")
    extract.add_argument("--developer-dir", type=Path, default=Path("/Applications/Xcode-27-RC.app/Contents/Developer"))
    extract.add_argument("--sdk", type=Path, default=Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"))
    extract.add_argument("--target", default="arm64-apple-macosx27.0")
    extract.add_argument("--out", type=Path, default=Path("factory/out/catalogue/raw"))
    extract.add_argument("--evidence", type=Path, default=Path("factory/catalogue/evidence"))
    extract.add_argument("--id", default="sdk.macos27.swiftui")
    merge = sub.add_parser("merge", help="merge existing raw symbolgraphs into catalogue evidence")
    merge.add_argument("graphs", type=Path, nargs="+")
    merge.add_argument("--sdk", required=True)
    merge.add_argument("--compiler", required=True)
    merge.add_argument("--target", required=True)
    merge.add_argument("--interfaces", type=Path, nargs="+", required=True)
    merge.add_argument("--flag", dest="flags", action="append", default=[])
    merge.add_argument("--evidence", type=Path, default=Path("factory/catalogue/evidence"))
    merge.add_argument("--id", default="sdk.macos27.swiftui")
    audit = sub.add_parser("audit", help="audit interfaces against existing graphs")
    audit.add_argument("--graphs", type=Path, nargs="+", required=True)
    audit.add_argument("--interfaces", type=Path, nargs="+", required=True)
    audit.add_argument("--target")
    audit.add_argument("--output", type=Path, default=Path("factory/catalogue/evidence/interface-audit.json"))
    audit_v2_parser = sub.add_parser("audit-v2", help="audit interfaces by context and signature into separate v2 evidence")
    audit_v2_parser.add_argument("--graphs", type=Path, nargs="+", required=True)
    audit_v2_parser.add_argument("--comparison-graphs", type=Path, nargs="+")
    audit_v2_parser.add_argument("--interfaces", type=Path, nargs="+", required=True)
    audit_v2_parser.add_argument("--target")
    audit_v2_parser.add_argument("--output", type=Path, default=Path("factory/catalogue/evidence/interface-audit-v2.json"))
    audit_v3_parser = sub.add_parser("audit-v3", help="audit interfaces by context, signature, and generic constraints into separate v3 evidence")
    audit_v3_parser.add_argument("--graphs", type=Path, nargs="+", required=True)
    audit_v3_parser.add_argument("--comparison-graphs", type=Path, nargs="+")
    audit_v3_parser.add_argument("--interfaces", type=Path, nargs="+", required=True)
    audit_v3_parser.add_argument("--target")
    audit_v3_parser.add_argument("--output", type=Path, default=Path("factory/catalogue/evidence/interface-audit-v3.json"))
    audit_v4_parser = sub.add_parser("audit-v4", help="audit interfaces with module-qualified type normalization into separate v4 evidence")
    audit_v4_parser.add_argument("--graphs", type=Path, nargs="+", required=True)
    audit_v4_parser.add_argument("--comparison-graphs", type=Path, nargs="+")
    audit_v4_parser.add_argument("--interfaces", type=Path, nargs="+", required=True)
    audit_v4_parser.add_argument("--target")
    audit_v4_parser.add_argument("--output", type=Path, default=Path("factory/catalogue/evidence/interface-audit-v4.json"))
    audit_v5_parser = sub.add_parser("audit-v5", help="audit using exact compiler-probed conditional branch evidence")
    audit_v5_parser.add_argument("--graphs", type=Path, nargs="+", required=True)
    audit_v5_parser.add_argument("--comparison-graphs", type=Path, nargs="+")
    audit_v5_parser.add_argument("--interfaces", type=Path, nargs="+", required=True)
    audit_v5_parser.add_argument("--target")
    audit_v5_parser.add_argument("--probe-evidence", type=Path, default=Path("factory/catalogue/evidence/tilde-sendable-compiler-probe.json"))
    audit_v5_parser.add_argument("--output", type=Path, default=Path("factory/catalogue/evidence/interface-audit-v5.json"))
    args = parser.parse_args(argv)
    if args.command == "extract":
        graphs = run_extraction(args.sdk, args.target, args.out, args.developer_dir)
        compiler = subprocess.run(["xcrun", "swift", "--version"], check=True, capture_output=True, text=True, env={**__import__("os").environ, "DEVELOPER_DIR": str(args.developer_dir.resolve())}).stdout.strip()
        interfaces = _interface_paths(args.sdk)
        flags = ["-emit-extension-block-symbols", "modules:SwiftUI,SwiftUICore"]
        invocations = [["xcrun", "swift-symbolgraph-extract", "-module-name", module, "-sdk", str(args.sdk.absolute()), "-target", args.target, "-output-dir", str((args.out / module.lower()).resolve()), "-emit-extension-block-symbols"] for module in MODULES]
        sdk_identity = f"macOS 27.0 ({args.sdk.name}; {args.developer_dir.parent.parent.name})"
        artifact, audit_result, graph_summary = make_catalogue(graphs, interfaces, sdk=sdk_identity, compiler=compiler, target=args.target, flags=flags, catalogue_id=args.id)
        write_canonical(args.evidence / "catalogue.json", artifact)
        write_canonical(args.evidence / "interface-audit.json", audit_result)
        write_canonical(args.evidence / "extraction-summary.json", {"toolchain": {"developerDir": str(args.developer_dir.resolve()), "compiler": compiler, "sdk": sdk_identity, "sdkPath": str(args.sdk.absolute()), "target": args.target, "flags": flags, "invocations": invocations}, **graph_summary})
        print(json.dumps({"catalogue": str(args.evidence / 'catalogue.json'), "symbolCount": len(artifact['symbols']), **graph_summary}, indent=2))
    elif args.command == "merge":
        artifact, audit_result, graph_summary = make_catalogue(args.graphs, args.interfaces, sdk=args.sdk, compiler=args.compiler, target=args.target, flags=args.flags, catalogue_id=args.id)
        write_canonical(args.evidence / "catalogue.json", artifact)
        write_canonical(args.evidence / "interface-audit.json", audit_result)
        write_canonical(args.evidence / "extraction-summary.json", graph_summary)
    elif args.command == "audit":
        symbols, _ = __import__("factory.catalogue.catalogue", fromlist=["merge_graphs"]).merge_graphs(args.graphs)
        write_canonical(args.output, audit_interfaces(args.interfaces, symbols, args.target))
    elif args.command == "audit-v2":
        result = audit_v2(args.interfaces, args.graphs, symbolgraph_target=args.target, comparison_graph_paths=args.comparison_graphs or [])
        write_canonical(args.output, result)
    elif args.command == "audit-v3":
        result = audit_v3(args.interfaces, args.graphs, symbolgraph_target=args.target, comparison_graph_paths=args.comparison_graphs or [])
        write_canonical(args.output, result)
    elif args.command == "audit-v4":
        result = audit_v4(args.interfaces, args.graphs, symbolgraph_target=args.target, comparison_graph_paths=args.comparison_graphs or [])
        write_canonical(args.output, result)
    else:
        result = audit_v5(args.interfaces, args.graphs, probe_evidence_path=args.probe_evidence,
                          symbolgraph_target=args.target, comparison_graph_paths=args.comparison_graphs or [])
        write_canonical(args.output, result)
    return 0
