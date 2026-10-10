from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from factory.catalogue.audit_v6 import _attempt, _line_scopes, _nonpublic_scope, _params, _return


class AuditV6Tests(unittest.TestCase):
    def test_qualified_builder_attribute_does_not_change_external_label(self) -> None:
        signature = "nonisolated public func alert<A>(_ titleKey: SwiftUICore.LocalizedStringKey, isPresented: SwiftUICore.Binding<Swift.Bool>, @SwiftUICore.ContentBuilder actions: () -> A) -> some SwiftUICore.View where A : SwiftUICore.View"
        self.assertEqual(_params(signature), (("_", "isPresented", "actions"),
                                              ("LocalizedStringKey", "Binding<Bool>", "()->A")))
        self.assertEqual(_return(signature), "someView")

    def test_sendable_remains_part_of_closure_type_identity(self) -> None:
        signature = "public func perform(_ operation: @Sendable () -> Void)"
        self.assertEqual(_params(signature), (("_",), ("@Sendable()->Void",)))

    def test_nested_closure_arrow_does_not_hide_top_level_result(self) -> None:
        signature = "public func transform(_ body: (Int) -> String) -> Result<String, Error>"
        self.assertEqual(_return(signature), "Result<String,Error>")

    def test_exact_attribute_types_resolve_one_graph_usr(self) -> None:
        row = {"kind": "func", "context": ["View"], "name": "alert", "signature": "nonisolated public func alert<A>(_ titleKey: SwiftUICore.LocalizedStringKey, isPresented: SwiftUICore.Binding<Swift.Bool>, @SwiftUICore.ContentBuilder actions: () -> A) -> some SwiftUICore.View where A : SwiftUICore.View"}
        usr = "s:exact-alert"
        key = (("View",), "alert", "callable")
        candidate = {"usr": usr, "pathComponents": ["View", "alert(_:isPresented:actions:)"],
                     "labels": ("_", "isPresented", "actions"),
                     "types": ("LocalizedStringKey", "Binding<Bool>", "()->A"), "returnType": "someView",
                     "whereConstraints": ("A:View",), "accessLevel": "public", "graph": "SwiftUI.symbols.json"}
        matches, evidence = _attempt(row, {key: [candidate]})
        self.assertEqual([item["usr"] for item in matches], [usr])
        self.assertEqual(evidence["reason"], "exact-context-signature-and-return-match")

    def test_same_signature_multiple_usrs_stays_ambiguous(self) -> None:
        row = {"kind": "func", "context": ["View"], "name": "alert", "signature": "public func alert(_ title: Swift.String) -> Swift.Bool"}
        key = (("View",), "alert", "callable")
        def candidate(usr: str) -> dict[str, object]:
            return {"usr": usr, "pathComponents": ["View", "alert(_:)"], "labels": ("_",),
                    "types": ("String",), "returnType": "Bool", "whereConstraints": (),
                    "accessLevel": "public", "graph": "SwiftUI.symbols.json"}
        matches, evidence = _attempt(row, {key: [candidate("s:first"), candidate("s:second")]})
        self.assertEqual(len(matches), 2)
        self.assertEqual(evidence["reason"], "multiple-signature-compatible-usrs")

    def test_where_constraints_must_match_even_when_interface_has_none(self) -> None:
        row = {"kind": "func", "context": ["View"], "name": "alert",
               "signature": "public func alert<A>(_ value: A) where A : View"}
        candidate = {"usr": "s:constrained", "pathComponents": ["View", "alert(_:)"],
                     "labels": ("_",), "types": ("A",), "returnType": None,
                     "whereConstraints": (), "accessLevel": "public", "graph": "g"}
        matches, evidence = _attempt(row, {(('View',), "alert", "callable"): [candidate]})
        self.assertEqual(matches, [])
        self.assertEqual(evidence["reason"], "context-name-candidates-fail-exact-signature")

    def test_context_suffix_is_not_treated_as_exact_context(self) -> None:
        row = {"kind": "func", "context": ["Outer", "View"], "name": "alert", "signature": "public func alert()"}
        candidate = {"usr": "s:suffix", "pathComponents": ["View", "alert()"],
                     "labels": (), "types": (), "returnType": None,
                     "whereConstraints": (), "accessLevel": "public", "graph": "g"}
        matches, evidence = _attempt(row, {(('View',), "alert", "callable"): [candidate]})
        self.assertEqual(matches, [])
        self.assertEqual(evidence["reason"], "no-public-candidate-at-exact-context-and-name")

    def test_internal_parent_is_explicit_scope_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "SwiftUI.swiftinterface"
            path.write_text("internal struct Wrapper {\n  public func api()\n}\npublic struct PublicType {\n  public func visible()\n}\n")
            scopes = _line_scopes(path)
        hidden = _nonpublic_scope(scopes[2])
        self.assertEqual((hidden["kind"], hidden["target"], hidden["line"], hidden["access"]),
                         ("struct", "Wrapper", 1, "internal"))
        self.assertIsNone(_nonpublic_scope(scopes[5]))

    def test_comment_cannot_create_nonpublic_scope_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "SwiftUI.swiftinterface"
            path.write_text("// internal struct Fake {\npublic func visible()\n")
            scopes = _line_scopes(path)
        self.assertEqual(scopes[2], [])
        self.assertIsNone(_nonpublic_scope(scopes[2]))

    def test_v6_snapshot_hashes_rows_and_keeps_unresolved_reasons(self) -> None:
        import json
        from factory.core import artifacts
        root = Path(__file__).resolve().parents[2]
        path = root / "factory/catalogue/evidence/interface-audit-v6.json"
        self.assertTrue(path.exists(), "run python -m factory.catalogue.audit_v6 to build candidate snapshot")
        audit = json.loads(path.read_text())
        unhashed = dict(audit)
        digest = unhashed.pop("auditHash")
        self.assertEqual(digest, artifacts.canonical_hash(unhashed))
        residual = [row for row in audit["declarations"] if row.get("v6Evidence")]
        self.assertEqual(len(residual), sum(audit["summary"]["beforeV5ResidualCounts"].values()))
        self.assertTrue(all(row["v6Evidence"].get("reason") for row in residual))
        self.assertEqual(audit["summary"]["remainingActiveUnmappedAmbiguousOrUnexplained"],
                         sum(audit["summary"]["byClassification"].get(name, 0)
                             for name in ("active-compiler-conditional-unmapped", "ambiguous-context-signature", "unexplained")))
        self.assertEqual(audit["status"], "incomplete-context-signature-audit")
        extraction_path = root / "factory/catalogue/evidence/extraction-summary.json"
        extraction = json.loads(extraction_path.read_text())
        self.assertEqual(audit["symbolgraphTarget"], extraction["toolchain"]["target"])
        self.assertEqual(audit["graphTargetEvidence"]["target"], extraction["toolchain"]["target"])
        self.assertEqual(audit["graphTargetEvidence"]["sourceHash"], artifacts.file_hash(extraction_path))
        self.assertNotEqual(audit["symbolgraphTarget"], audit["parentAudit"].get("symbolgraphTarget"))


if __name__ == "__main__":
    unittest.main()
