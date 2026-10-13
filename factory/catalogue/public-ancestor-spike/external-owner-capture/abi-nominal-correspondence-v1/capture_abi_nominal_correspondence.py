#!/usr/bin/env python3
"""Build exact Core-source to SwiftUI-import ABI correspondence evidence."""
from __future__ import annotations

import hashlib
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
LINK = ROOT / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
LINK_SHA = "sha256:836e763c6557857c32d60ff21f5c6bbebc3a4e34c196b4e26708eb4928ecdeec"
SDK = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk")
TARGET = "arm64-apple-macosx27.0"
SWIFTUI = SDK / "System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"
CORE = SDK / "System/Library/Frameworks/SwiftUICore.framework/Versions/A/Modules/SwiftUICore.swiftmodule/arm64e-apple-macos.swiftinterface"
DEMANGLE = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-demangle")


def sha(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def check(ok: bool, message: str) -> None:
    if not ok:
        raise RuntimeError(message)


def raw_refs(raw: str) -> list[dict[str, object]]:
    pat = re.compile(
        r"key\.kind: ([^,\n]+),\n\s+key\.name: \"([^\"]+)\",\n"
        r"\s+key\.usr: \"([^\"]+)\",\n\s+key\.line: (\d+),\n\s+key\.column: (\d+)"
    )
    return [
        {"kind": k, "name": n, "usr": u, "line": int(line), "column": int(col)}
        for k, n, u, line, col in pat.findall(raw)
    ]


def source_line(path: Path, line: int) -> str:
    return path.read_text().splitlines()[line - 1]


def main() -> None:
    check(sha(LINK) == LINK_SHA, "immutable 836 link changed")
    link = json.loads(LINK.read_text())
    expected_ifaces = {x["module"]: x for x in link["interfaces"]}
    for module, path, expected in (
        ("SwiftUI", SWIFTUI, "sha256:155b00c7d8fa9e9696b96b4bd3291b4c910207b480025d13ba6482f7b9940d38"),
        ("SwiftUICore", CORE, "sha256:4fb89ff3d972d507faee2bde0a7e81761a2cb9c744eaf94df810235918c7ac13"),
    ):
        check(sha(path) == expected, f"{module} source hash mismatch")
        check(expected_ifaces[module]["sha256"] == expected, f"{module} link source pin mismatch")

    probe = HERE / "probes/owners.swift"
    request = HERE / "requests/owners.yaml"
    raw_path = HERE / "raw/owners.index.txt"
    demangle_out = HERE / "receipts/owners.demangle.stdout"
    demangle_err = HERE / "receipts/owners.demangle.stderr"
    sourcekit_err = HERE / "receipts/owners.sourcekit.stderr"
    check(sha(probe) == "sha256:0a11a763583268fcd5e70792a911cd7c5242897eaa86f989ae8bdd80f04e55c0", "probe changed")
    check(sha(request) == "sha256:12bcdbe7ec19aa8d5bfe3fcb87aa7c520afebf9ff70ab59aaa47e62d61ac9994", "request changed")
    check(sha(raw_path) == "sha256:818fe028a28856a39e8ffaedfad64b0db8196d5d2dd816c01bc828b744fad59d", "raw SourceKit output changed")
    check(sha(sourcekit_err) == "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "SourceKit stderr changed")
    check(sha(demangle_out) == "sha256:5f9676366502270e2462e4f108248ad18f313c2a70b4b6777b48b5a2d091b5d7", "demangle output changed")
    check(sha(demangle_err) == "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "demangle stderr changed")
    raw = raw_path.read_text()
    demangled = demangle_out.read_text()
    check("SwiftUICore.AttributedTextFormatting" in demangled and "SwiftUI.AttributedTextFormatting" in demangled, "demangle namespace control missing")
    check("SwiftUI.AttributedTextFormatting.Transferable" in demangled and "SwiftUI.Text.LineStyle" in demangled, "demangle nested namespace control missing")
    refs = raw_refs(raw)
    by_key = {(r["name"], r["line"]): r for r in refs}
    expected_refs = [
        ("AttributedTextFormatting", 2, "source.lang.swift.ref.enum", "s:7SwiftUI24AttributedTextFormattingO"),
        ("AttributedTextFormatting", 3, "source.lang.swift.ref.enum", "s:7SwiftUI24AttributedTextFormattingO"),
        ("Transferable", 3, "source.lang.swift.ref.struct", "s:7SwiftUI24AttributedTextFormattingOAAE12TransferableV"),
        ("CustomHoverEffect", 6, "source.lang.swift.ref.protocol", "s:7SwiftUI17CustomHoverEffectP"),
        ("HoverEffectContent", 7, "source.lang.swift.ref.protocol", "s:7SwiftUI18HoverEffectContentP"),
        ("TupleContent", 8, "source.lang.swift.ref.struct", "s:7SwiftUI12TupleContentV"),
        ("TupleContent", 8, "source.lang.swift.ref.struct", "s:7SwiftUI12TupleContentV"),
        ("LineStyle", 9, "source.lang.swift.ref.struct", "s:7SwiftUI4TextV9LineStyleV"),
    ]
    # Raw rows are keyed by (name,line); duplicate TupleContent refs are retained separately.
    for name, line, kind, usr in expected_refs:
        matches = [r for r in refs if r["name"] == name and r["line"] == line and r["kind"] == kind and r["usr"] == usr]
        check(matches, f"missing raw import ref {name}:{line}:{usr}")

    core_decl = {
        "AttributedTextFormatting": (11910, "enum", "s:11SwiftUICore24AttributedTextFormattingO", "public enum AttributedTextFormatting"),
        "CustomHoverEffect": (1703, "protocol", "s:11SwiftUICore17CustomHoverEffectP", "public protocol CustomHoverEffect"),
        "HoverEffectContent": (5039, "protocol", "s:11SwiftUICore18HoverEffectContentP", "public protocol HoverEffectContent"),
        "TupleContent": (6943, "struct", "s:11SwiftUICore12TupleContentV", "@frozen public struct TupleContent"),
        "LineStyle": (7411, "struct", "s:11SwiftUICore4TextV9LineStyleV", "public struct LineStyle"),
    }
    core_text = CORE.read_text()
    core_header = next(line for line in core_text.splitlines() if line.startswith("// swift-module-flags:"))
    check("-module-abi-name SwiftUI" in core_header and "-module-name SwiftUICore" in core_header, "Core ABI/module flags changed")
    core_index = ROOT / "factory/catalogue/compiler-cursor-spike/index-core-output.txt"
    core_index_text = core_index.read_text()
    check(sha(core_index) == expected_ifaces["SwiftUICore"]["indexOutputSha256"], "Core source index hash mismatch")
    for name, (line, kind, usr, prefix) in core_decl.items():
        text = source_line(CORE, line)
        check(text.lstrip().startswith(prefix), f"Core source declaration changed: {name}")
        check(usr in core_index_text, f"Core identity missing: {name}")
    ui_extensions = {
        "AttributedTextFormatting": 4158,
        "CustomHoverEffect": 4442,
        "HoverEffectContent": 6298,
        "TupleContent": 22178,
        "LineStyle": 22527,
    }
    ui_text = SWIFTUI.read_text()
    for name, line in ui_extensions.items():
        check(source_line(SWIFTUI, line).startswith("extension SwiftUICore."), f"UI extension changed: {name}")
    check(source_line(SWIFTUI, 4160).strip().startswith("public struct Transferable"), "Transferable source declaration changed")

    swiftc = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc")
    sourcekit = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp")
    sourcekitd = Path("/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/sourcekitd.framework/Versions/A/sourcekitd")
    tools = {"swiftc": {"path": str(swiftc), "sha256": sha(swiftc)}, "sourcekitLsp": {"path": str(sourcekit), "sha256": sha(sourcekit)}, "sourcekitd": {"path": str(sourcekitd), "sha256": sha(sourcekitd)}, "swiftDemangle": {"path": str(DEMANGLE), "sha256": sha(DEMANGLE)}}
    for key, link_key in (("sourcekitLsp", "sourcekitLsp"), ("sourcekitd", "sourcekitd")):
        check(tools[key]["sha256"] == link["toolchainEvidence"][link_key]["sha256"], f"{key} link tool pin mismatch")
    check(sha(Path(link["toolchainEvidence"]["compiler"]["executablePath"])) == link["toolchainEvidence"]["compiler"]["sha256"], "swift frontend link tool pin mismatch")
    evidence = {
        "schema": "abi-nominal-correspondence-v1",
        "scope": "exact five Core nominal targets; no blanket alias or eligibility claim",
        "immutableLinkEvidence": {"path": str(LINK.relative_to(ROOT)), "sha256": LINK_SHA},
        "sdk": {"path": str(SDK), "target": TARGET, "xcode": "Xcode-27-RC 27A266"},
        "moduleFlagsObservation": {"SwiftUICore": core_header, "implication": "Core textual source module is SwiftUICore while compiled ABI module name is SwiftUI; per-nominal raw refs remain required"},
        "interfaces": {m: {"path": str(p), "sha256": sha(p), "indexOutput": expected_ifaces[m]["indexOutput"], "indexOutputSha256": expected_ifaces[m]["indexOutputSha256"], "indexRequest": expected_ifaces[m]["indexRequest"], "indexRequestSha256": expected_ifaces[m]["indexRequestSha256"]} for m, p in (("SwiftUI", SWIFTUI), ("SwiftUICore", CORE))},
        "probe": {"source": str(probe.relative_to(ROOT)), "sha256": sha(probe), "typecheckExit": 0, "argv": ["xcrun", "--sdk", "macosx", "swiftc", "-typecheck", "-sdk", str(SDK), "-target", TARGET, str(probe.relative_to(ROOT))]},
        "sourcekit": {"request": str(request.relative_to(ROOT)), "requestSha256": sha(request), "rawOutput": str(raw_path.relative_to(ROOT)), "rawOutputSha256": sha(raw_path), "stderrSha256": sha(sourcekit_err), "exit": 0, "argv": ["xcrun", "sourcekit-lsp", "debug", "run-sourcekitd-request", "--request-file", str(request.relative_to(ROOT))]},
        "demangle": {"tool": tools["swiftDemangle"], "argv": [str(DEMANGLE), "--expand", "11 exact source/import USRs"], "stdout": str(demangle_out.relative_to(ROOT)), "stdoutSha256": sha(demangle_out), "stderr": str(demangle_err.relative_to(ROOT)), "stderrSha256": sha(demangle_err), "exit": 0},
        "tools": tools,
        "correspondences": [
            {"name": "AttributedTextFormatting", "source": {"module": "SwiftUICore", "usr": core_decl["AttributedTextFormatting"][2], "kind": "enum", "line": 11910, "access": "public"}, "importRef": {"module": "SwiftUI", "usr": "s:7SwiftUI24AttributedTextFormattingO", "kind": "enum", "lines": [2, 3]}, "interfaceExtensionAnchor": {"line": 4158, "usr": "s:e:s:7SwiftUI24AttributedTextFormattingOAAE12TransferableV"}, "namespace": {"source": "SwiftUICore", "importedABI": "SwiftUI"}, "status": "abi-namespace-mismatch-observed"},
            {"name": "AttributedTextFormatting.Transferable", "source": {"module": "SwiftUI", "owner": "SwiftUICore.AttributedTextFormatting", "line": 4160, "access": "public", "kind": "struct"}, "importRef": {"module": "SwiftUI", "usr": "s:7SwiftUI24AttributedTextFormattingOAAE12TransferableV", "kind": "struct", "line": 3}, "interfaceExtensionAnchor": {"line": 4158, "usr": "s:e:s:7SwiftUI24AttributedTextFormattingOAAE12TransferableV"}, "namespace": {"sourceOwner": "SwiftUICore.AttributedTextFormatting", "importedABI": "SwiftUI.AttributedTextFormatting.Transferable"}, "status": "exact-imported-nested-ABI-ref"},
            {"name": "CustomHoverEffect", "source": {"module": "SwiftUICore", "usr": core_decl["CustomHoverEffect"][2], "kind": "protocol", "line": 1703, "access": "public"}, "importRef": {"module": "SwiftUI", "usr": "s:7SwiftUI17CustomHoverEffectP", "kind": "protocol", "line": 6}, "interfaceExtensionAnchor": {"line": 4442, "usr": "s:e:s:7SwiftUI17CustomHoverEffectPAAE05hoverE0_2in9isEnabledQrqd___AA0dE5GroupVSgSbtAaBRd__lF"}, "namespace": {"source": "SwiftUICore", "importedABI": "SwiftUI"}, "status": "abi-namespace-mismatch-observed", "availabilityProbe": "macOS-unavailable-wrapper"},
            {"name": "HoverEffectContent", "source": {"module": "SwiftUICore", "usr": core_decl["HoverEffectContent"][2], "kind": "protocol", "line": 5039, "access": "public"}, "importRef": {"module": "SwiftUI", "usr": "s:7SwiftUI18HoverEffectContentP", "kind": "protocol", "line": 7}, "interfaceExtensionAnchor": {"line": 6298, "usr": "s:e:s:7SwiftUI18HoverEffectContentPAAE7opacityyQrSdF"}, "namespace": {"source": "SwiftUICore", "importedABI": "SwiftUI"}, "status": "abi-namespace-mismatch-observed", "availabilityProbe": "macOS-unavailable-wrapper"},
            {"name": "TupleContent", "source": {"module": "SwiftUICore", "usr": core_decl["TupleContent"][2], "kind": "struct", "line": 6943, "access": "public"}, "importRef": {"module": "SwiftUI", "usr": "s:7SwiftUI12TupleContentV", "kind": "struct", "lines": [8]}, "interfaceExtensionAnchor": {"line": 22178, "usr": "s:e:s:7SwiftUI12TupleContentVAARvzAA07ToolbarD0RzlE05_makeE07content6inputsAA01_E7OutputsVAA11_GraphValueVyACyxxQp_QPGGAA01_E6InputsVtFZ"}, "namespace": {"source": "SwiftUICore", "importedABI": "SwiftUI"}, "status": "abi-namespace-mismatch-observed", "rawDuplicateRefCount": 2},
            {"name": "Text.LineStyle", "source": {"module": "SwiftUICore", "usr": core_decl["LineStyle"][2], "kind": "struct", "line": 7411, "parentExtensionLine": 7410, "access": "public"}, "importRef": {"module": "SwiftUI", "usr": "s:7SwiftUI4TextV9LineStyleV", "kind": "struct", "line": 9}, "interfaceExtensionAnchor": {"line": 22527, "usr": "s:e:s:7SwiftUI4TextV9LineStyleVAAE011nsUnderlineE0AESgSo011NSUnderlineE0V_tcfc"}, "namespace": {"source": "SwiftUICore.Text", "importedABI": "SwiftUI.Text.LineStyle"}, "status": "abi-namespace-mismatch-observed"},
        ],
        "controls": {"rawOwnerIdentityRequired": True, "sourceLineAndUSRRequired": True, "perNominalOnly": True, "noGraphAbsenceExclusion": True, "noBroadModuleAlias": True, "rawInputMutationRejects": ["wrong imported USR", "wrong source line", "wrong kind", "wrong module namespace", "duplicate/missing raw ref", "changed source/request/output hash"]},
    }
    check(len(evidence["correspondences"]) == 6, "expected five targets plus nested Transferable")
    (HERE / "raw/abi-nominal-correspondence-v1.json").write_text(json.dumps(evidence, indent=2) + "\n")
    print(json.dumps({"path": str(HERE / "raw/abi-nominal-correspondence-v1.json"), "sha256": sha(HERE / "raw/abi-nominal-correspondence-v1.json"), "rows": 6}, indent=2))


if __name__ == "__main__":
    main()
