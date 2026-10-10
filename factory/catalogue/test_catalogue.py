from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from factory.catalogue.catalogue import audit_interfaces, merge_graphs
from factory.catalogue.audit_v2 import audit_v2, audit_v3, audit_v4
from factory.catalogue.audit_v5 import apply_probe_result
from factory.core.artifacts import validate_artifact


def graph(module: str, usr: str, path: list[str]) -> dict:
    return {"module": {"name": module}, "symbols": [{"identifier": {"precise": usr}, "pathComponents": path}], "relationships": []}


class CatalogueTests(unittest.TestCase):
    def test_merge_deduplicates_reexport_graphs_by_usr_and_keeps_owner_module(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            first, reexport = root / "SwiftUI.symbols.json", root / "SwiftUI@SwiftUICore.symbols.json"
            first.write_text(json.dumps(graph("SwiftUI", "s:7SwiftUI5ThingV", ["Thing"])))
            reexport.write_text(json.dumps(graph("SwiftUI", "s:10SwiftUICore5ThingV", ["Thing"])))
            symbols, summary = merge_graphs([reexport, first])
        self.assertEqual(len(symbols), 2)
        self.assertEqual({symbol["path"] for symbol in symbols}, {"SwiftUI.Thing", "SwiftUICore.Thing"})
        self.assertEqual(summary["duplicateUsrCount"], 0)

    def test_module_comes_from_leading_mangled_module_not_nested_type_reference(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "reexport.json"
            usr = "s:10Foundation11FormatStyleP7SwiftUIAD06SystembC0O"
            path.write_text(json.dumps(graph("SwiftUI", usr, ["FormatStyle"])))
            symbols, _ = merge_graphs([path])
        self.assertEqual(symbols[0]["path"], "Foundation.FormatStyle")

    def test_merge_deduplicates_same_usr_emitted_in_extension_and_main_graph(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            main, extension = root / "main.json", root / "extension.json"
            main.write_text(json.dumps(graph("SwiftUI", "s:7SwiftUI5ThingV", ["Thing"])))
            extension.write_text(json.dumps(graph("SwiftUI", "s:7SwiftUI5ThingV", ["RenamedThing"])))
            symbols, summary = merge_graphs([main, extension])
        self.assertEqual(len(symbols), 1)
        self.assertEqual(summary["duplicateUsrCount"], 1)
        self.assertEqual(symbols[0]["path"], "SwiftUI.RenamedThing")

    def test_interface_audit_retains_hidden_and_unexplained_declarations_without_claiming_complete(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            interface = Path(directory) / "SwiftUI.swiftinterface"
            interface.write_text("@_documentation(visibility: internal)\npublic struct Hidden {}\n@_spi(Internal) public func spiOnly()\npublic func absent()\n")
            result = audit_interfaces([interface], [{"path": "SwiftUI.Present", "usr": "s:7SwiftUI7PresentV"}])
        self.assertEqual(result["status"], "incomplete-name-level-audit")
        self.assertEqual(result["summary"]["byClassification"]["hidden-attribute"], 2)
        self.assertEqual(result["summary"]["byClassification"]["unmatched"], 1)
        self.assertIn("Hidden", result["declarations"][0]["declaration"])

    def test_minimal_catalogue_matches_v01_schema(self) -> None:
        from factory.core.artifacts import canonical_hash, provenance
        value = {
            "kind": "catalogue", "version": "0.1", "id": "sdk.test.catalogue",
            "provenance": provenance({"fixture": "minimal"}),
            "symbolGraph": {"sdk": "SDK", "compiler": "Swift", "target": "arm64-apple-macosx27.0", "flagsHash": canonical_hash([]), "interfaceAuditHash": canonical_hash({})},
            "symbols": [{"usr": "s:7SwiftUI5ThingV", "precise": "s:7SwiftUI5ThingV", "path": "SwiftUI.Thing", "status": "inventory"}],
        }
        validate_artifact(value)

    def test_v2_matches_extension_context_labels_and_parameter_type_to_usr(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            interface = root / "SwiftUI.swiftinterface"
            interface.write_text("extension SwiftUICore.View {\n  public func foo(_ value: Swift.Int) -> Self\n}\n")
            graph_path = root / "SwiftUI.symbols.json"
            graph_path.write_text(json.dumps({"module": {"name": "SwiftUI"}, "symbols": [{
                "identifier": {"precise": "s:7SwiftUI4ViewP3foo_"},
                "pathComponents": ["View", "foo(_:)"] ,
                "kind": {"identifier": "swift.method"}, "accessLevel": "public",
                "functionSignature": {"parameters": [{"name": "value", "declarationFragments": [{"kind": "identifier", "spelling": "value"}, {"kind": "text", "spelling": ": "}, {"kind": "typeIdentifier", "spelling": "Int"}]}]},
            }] }))
            result = audit_v2([interface], [graph_path], symbolgraph_target="arm64e-apple-macos27.0")
        row = result["declarations"][0]
        self.assertEqual(row["classification"], "matched-context-signature")
        self.assertEqual(row["context"], ["View"])
        self.assertEqual(row["symbol"]["usr"], "s:7SwiftUI4ViewP3foo_")

    def test_v2_records_target_unavailability_separately_from_hidden_attributes(self) -> None:
        from factory.catalogue.audit_v2 import _interface_rows
        with tempfile.TemporaryDirectory() as directory:
            interface = Path(directory) / "SwiftUI.swiftinterface"
            interface.write_text("@available(macOS, unavailable)\npublic struct WatchOnly {}\n")
            row = _interface_rows(interface)[0]
        self.assertEqual(row["classification"], "excluded-target-availability")
        self.assertEqual(row["targetExclusion"], "macOS unavailable attribute")
        self.assertIsNone(row["hiddenReason"])

    def test_v3_uses_where_clause_to_resolve_same_shape_overloads(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            interface = root / "SwiftUI.swiftinterface"
            interface.write_text("""public struct Builder {
  public static func buildIf<C>(_ content: C?) -> C? where Row == C.Row, C : Content
}
""")
            graph_path = root / "SwiftUI.symbols.json"
            symbols = []
            for usr, clause in (("s:target", "Row == C.Row, C : Content"), ("s:other", "C : Content, C.Other == Never")):
                symbols.append({"identifier": {"precise": usr}, "pathComponents": ["Builder", "buildIf(_:)"],
                    "kind": {"identifier": "swift.type.method"}, "accessLevel": "public",
                    "functionSignature": {"parameters": [{"name": "content", "declarationFragments": [
                        {"kind": "identifier", "spelling": "content"}, {"kind": "text", "spelling": ": "}, {"kind": "typeIdentifier", "spelling": "C?"}]}]},
                    "declarationFragments": [{"kind": "keyword", "spelling": f"static func buildIf<C>(_ content: C?) -> C? where {clause}"}]})
            graph_path.write_text(json.dumps({"module": {"name": "SwiftUI"}, "symbols": symbols}))
            result = audit_v3([interface], [graph_path])
        row = next(row for row in result["declarations"] if row["name"] == "buildIf")
        self.assertEqual(result["version"], 3)
        self.assertEqual(row["classification"], "matched-context-signature")
        self.assertEqual(row["symbol"]["usr"], "s:target")

    def test_v3_matches_operator_operands_by_types_when_graph_labels_are_unlabeled(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            interface = root / "SwiftUI.swiftinterface"
            interface.write_text("public struct Pair {\n public static func == (a: Pair, b: Pair) -> Bool\n}\n")
            graph_path = root / "SwiftUI.symbols.json"
            graph_path.write_text(json.dumps({"module": {"name": "SwiftUI"}, "symbols": [{
                "identifier": {"precise": "s:eq"}, "pathComponents": ["Pair", "==(_:_:)"],
                "kind": {"identifier": "swift.type.method"}, "accessLevel": "public",
                "functionSignature": {"parameters": [
                    {"name": "a", "declarationFragments": [{"spelling": "a: Pair"}]},
                    {"name": "b", "declarationFragments": [{"spelling": "b: Pair"}]}]}}]}))
            result = audit_v3([interface], [graph_path])
        row = next(row for row in result["declarations"] if row["name"] == "==")
        self.assertEqual(row["classification"], "matched-context-signature")
        self.assertEqual(row["symbol"]["usr"], "s:eq")

    def test_v4_resolves_qualified_module_and_escaping_closure_overload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            interface = root / "SwiftUI.swiftinterface"
            interface.write_text("""public struct DropInfo {
  public func itemProviders(for contentTypes: [UniformTypeIdentifiers.UTType]) -> [Foundation.NSItemProvider]
}
""")
            graph_path = root / "SwiftUI.symbols.json"
            symbols = []
            for usr, param_type in (("s:uttype", "[UTType]"), ("s:string", "[String]")):
                symbols.append({"identifier": {"precise": usr}, "pathComponents": ["DropInfo", "itemProviders(for:)"],
                    "kind": {"identifier": "swift.method"}, "accessLevel": "public",
                    "functionSignature": {"parameters": [{"name": "contentTypes", "declarationFragments": [
                        {"spelling": "contentTypes: "}, {"spelling": param_type}]}]},
                    "declarationFragments": [{"spelling": f"func itemProviders(for contentTypes: {param_type}) -> [NSItemProvider]"}]})
            graph_path.write_text(json.dumps({"module": {"name": "SwiftUI"}, "symbols": symbols}))
            result = audit_v4([interface], [graph_path])
        row = next(row for row in result["declarations"] if row["name"] == "itemProviders")
        self.assertEqual(row["classification"], "matched-context-signature")
        self.assertEqual(row["symbol"]["usr"], "s:uttype")

    def test_v4_uses_exact_return_type_and_keeps_nonmatching_candidates_ambiguous(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            interface = root / "SwiftUI.swiftinterface"
            interface.write_text("""public struct Factory {
  public func value(_ input: Int) -> Int
  public func other(_ input: Int) -> String
}
""")
            symbols = []
            for name, result, usr in (("value", "Int", "s:value-int"), ("value", "Bool", "s:value-bool"),
                                      ("other", "Int", "s:other-int"), ("other", "Bool", "s:other-bool")):
                symbols.append({"identifier": {"precise": usr}, "pathComponents": ["Factory", f"{name}(_:)"],
                    "kind": {"identifier": "swift.method"}, "accessLevel": "public",
                    "functionSignature": {"parameters": [{"name": "input", "declarationFragments": [{"spelling": "input: Int"}]}],
                                          "returns": [{"spelling": result}]},
                    "declarationFragments": [{"spelling": f"func {name}(_ input: Int) -> {result}"}]})
            graph_path = root / "SwiftUI.symbols.json"
            graph_path.write_text(json.dumps({"module": {"name": "SwiftUI"}, "symbols": symbols}))
            result = audit_v4([interface], [graph_path])
        rows = {row["name"]: row for row in result["declarations"] if row["kind"] == "func"}
        self.assertEqual(rows["value"]["classification"], "matched-context-signature")
        self.assertEqual(rows["value"]["symbol"]["usr"], "s:value-int")
        self.assertEqual(rows["other"]["classification"], "ambiguous-context-signature")
        self.assertEqual(rows["other"]["candidateCount"], 2)

    def test_v5_classifies_only_compiler_proven_inactive_branch_and_preserves_exclusions(self) -> None:
        from factory.core.artifacts import canonical_hash
        condition = "compiler(>=5.3) && $TildeSendable"
        audit = {"version": 4, "status": "incomplete-context-signature-audit", "method": "fixture",
                 "declarations": [
                     {"conditions": [condition], "classification": "matched-context-signature", "symbol": {"usr": "s:active"}},
                     {"conditions": [condition], "classification": "unresolved-conditional"},
                     {"conditions": [f"else({condition})"], "classification": "matched-context-signature", "symbol": {"usr": "s:inactive"}},
                     {"conditions": [f"else({condition})"], "classification": "ambiguous-context-signature", "candidates": [{"usr": "s:a"}], "candidateCount": 1},
                     {"conditions": [f"else({condition})"], "classification": "excluded-target-availability"},
                     {"conditions": ["compiler(>=6.0)"], "classification": "unresolved-conditional"},
                 ], "summary": {"byClassification": {}}}
        evidence = {"evidenceHash": "sha256:probe", "condition": condition, "target": "arm64e-apple-macosx27.0",
                    "selectedBranch": "tilde-sendable", "inactiveBranch": "else", "execution": {"stdout": "selected=tilde-sendable\n"},
                    "targetRuns": [{"target": "arm64-apple-macosx27.0", "execution": {"stdout": "selected=tilde-sendable\n", "stdoutByteSha256": "sha256:stdout-arm64"}},
                                   {"target": "arm64e-apple-macosx27.0", "execution": {"stdout": "selected=tilde-sendable\n", "stdoutByteSha256": "sha256:stdout-arm64e"}}],
                    "source": {"sha256": "sha256:source"}, "toolchain": {"swiftcSha256": "sha256:compiler"}}
        result = apply_probe_result(audit, evidence, "probe-evidence.json")
        rows = result["declarations"]
        self.assertEqual(rows[0]["classification"], "matched-context-signature")
        self.assertEqual(rows[1]["classification"], "active-compiler-conditional-unmapped")
        self.assertEqual(rows[2]["classification"], "inactive-compiler-conditional")
        self.assertEqual(rows[2]["priorSymbol"]["usr"], "s:inactive")
        self.assertEqual(rows[3]["classification"], "inactive-compiler-conditional")
        self.assertEqual(rows[3]["priorCandidateCount"], 1)
        self.assertEqual(rows[4]["classification"], "excluded-target-availability")
        self.assertNotIn("conditionalResolution", rows[5])
        self.assertEqual(result["summary"]["compilerConditionalRows"], {"active": 2, "inactive": 3})
        unhashed = dict(result)
        saved_hash = unhashed.pop("auditHash")
        self.assertEqual(saved_hash, canonical_hash(unhashed))


if __name__ == "__main__":
    unittest.main()
