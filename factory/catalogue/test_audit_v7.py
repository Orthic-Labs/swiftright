from __future__ import annotations

import unittest
import tempfile
import json
from pathlib import Path

from .audit_v7 import (
    _assess_exact_sourcekit_link,
    _demangled_owner,
    _index_entities,
    _demangle_map_from_stdout,
    _name_matches,
    _validate_demangle_mapping,
    _validate_request_identity,
    _verified_link_claim,
)


class AuditV7CompilerLinkTests(unittest.TestCase):
    def setUp(self) -> None:
        self.row = {"kind": "func", "name": "accessibilityLabel",
                    "signature": "public func accessibilityLabel<A>(content: A) -> some View"}
        self.entity = {
            "kind": "source.lang.swift.decl.function.method.instance",
            "name": "accessibilityLabel(content:)", "usr": "s:example",
            "effective_access": "source.decl.effective_access.public", "line": 852,
            "sourcekitContext": [{"kind": "source.lang.swift.decl.extension.protocol",
                                  "name": "View", "usr": "s:view"}],
        }
        self.demangled = {
            "s:example": "(extension in SwiftUI):SwiftUI.View.accessibilityLabel<A where A1: SwiftUI.View>(content: (SwiftUI.PlaceholderContentView<A>) -> A1) -> some"
        }

    def test_exact_unique_raw_record_with_kind_access_owner_passes(self) -> None:
        ok, reason, entity = _assess_exact_sourcekit_link(
            self.row, [self.entity], self.demangled, ("View",))
        self.assertTrue(ok)
        self.assertIsNone(reason)
        self.assertIs(entity, self.entity)

    def test_same_usr_duplicate_raw_records_do_not_pass(self) -> None:
        ok, reason, entity = _assess_exact_sourcekit_link(
            self.row, [self.entity, dict(self.entity)], self.demangled, ("View",))
        self.assertFalse(ok)
        self.assertEqual(reason, "raw-sourcekit-entity-cardinality-not-one")
        self.assertIsNone(entity)

    def test_index_response_parser_preserves_duplicate_raw_records(self) -> None:
        response = '''key.results: [
  {
    key.kind: source.lang.swift.decl.function.method.instance,
    key.name: "accessibilityLabel(content:)",
    key.usr: "s:example",
    key.line: 852,
    key.effective_access: source.decl.effective_access.public,
  },
  {
    key.kind: source.lang.swift.decl.function.method.instance,
    key.name: "accessibilityLabel(content:)",
    key.usr: "s:example",
    key.line: 852,
    key.effective_access: source.decl.effective_access.public,
  },
]'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "response.txt"
            path.write_text(response, encoding="utf-8")
            entities = _index_entities(path)
        self.assertEqual(len(entities), 2)
        self.assertEqual({item["usr"] for item in entities}, {"s:example"})

    def test_index_response_parser_retains_raw_container_chain(self) -> None:
        response = '''key.results: [
  {
    key.kind: source.lang.swift.decl.struct,
    key.name: "Outer",
    key.usr: "s:outer",
    key.line: 1,
    key.results: [
      {
        key.kind: source.lang.swift.decl.extension.struct,
        key.name: "Inner",
        key.usr: "s:extension",
        key.results: [
          {
            key.kind: source.lang.swift.decl.function.method.instance,
            key.name: "work()",
            key.usr: "s:work",
            key.line: 2,
          },
        ],
      },
    ],
  },
]'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "response.txt"
            path.write_text(response, encoding="utf-8")
            entities = _index_entities(path)
        self.assertEqual(entities[0]["sourcekitContext"], [
            {"kind": "source.lang.swift.decl.struct", "name": "Outer", "usr": "s:outer"},
            {"kind": "source.lang.swift.decl.extension.struct", "name": "Inner", "usr": "s:extension"},
        ])

    def test_kind_access_and_context_fail_closed(self) -> None:
        wrong_kind = dict(self.entity, kind="source.lang.swift.decl.var.instance")
        self.assertEqual(_assess_exact_sourcekit_link(
            self.row, [wrong_kind], self.demangled, ("View",))[1],
            "sourcekit-kind-does-not-match-interface")
        wrong_access = dict(self.entity, effective_access="source.decl.effective_access.internal")
        self.assertEqual(_assess_exact_sourcekit_link(
            self.row, [wrong_access], self.demangled, ("View",))[1],
            "sourcekit-access-does-not-match-interface-access")
        wrong_context = dict(self.entity, sourcekitContext=[{
            "kind": "source.lang.swift.decl.extension.protocol", "name": "OtherView", "usr": "s:other"
        }])
        self.assertEqual(_assess_exact_sourcekit_link(
            self.row, [wrong_context], self.demangled, ("View",))[1],
            "raw-sourcekit-context-does-not-match-interface-context")
        self.assertEqual(_assess_exact_sourcekit_link(
            self.row, [self.entity], self.demangled, ("OtherView",))[1],
            "raw-sourcekit-context-does-not-match-interface-context")
        actor_row = {"kind": "actor", "name": "Worker", "signature": "public actor Worker {"}
        actor_entity = dict(self.entity, kind="source.lang.swift.decl.class", name="Worker")
        self.assertEqual(_assess_exact_sourcekit_link(
            actor_row, [actor_entity], {"s:example": "SwiftUI.Worker"}, ())[1],
            "sourcekit-kind-does-not-match-interface")

    def test_demangled_owner_keeps_nested_generic_signature_out_of_context(self) -> None:
        self.assertEqual(_demangled_owner(self.demangled["s:example"], "accessibilityLabel"),
                         ("View",))

    def test_demangle_mapping_must_match_retained_raw_stdout(self) -> None:
        raw = "$sexample ---> SwiftUI.View.accessibilityLabel()\n"
        _validate_demangle_mapping(raw, {"s:example": "SwiftUI.View.accessibilityLabel()"})
        with self.assertRaisesRegex(ValueError, "does not exactly reproduce"):
            _validate_demangle_mapping(raw, {"s:example": "SwiftUI.NotView.accessibilityLabel()"})
        with self.assertRaisesRegex(ValueError, "invalid or duplicate"):
            _demangle_map_from_stdout(raw + raw)

    def test_actual_context_held_row_cannot_be_promoted_by_eligibility_flag(self) -> None:
        root = Path(__file__).resolve().parents[2]
        link_path = root / "factory/catalogue/compiler-cursor-spike/link-evidence.json"
        links = json.loads(link_path.read_text(encoding="utf-8"))
        row = next(item for item in links["rows"]
                   if item.get("module") == "SwiftUI" and item.get("line") == 714
                   and item.get("name") == "run" and item.get("linkHoldReason") == "enclosing-context-mismatch")
        response_path = root / row["compilerEvidence"]["response"]
        entities = _index_entities(response_path)
        candidates = [entity for entity in entities if entity.get("line") == row["line"]
                      and _name_matches(str(entity.get("name", "")), row["name"])
                      and not entity.get("is_implicit", False)]
        self.assertEqual(len(candidates), 1)
        candidate = candidates[0]
        self.assertEqual(candidate["sourcekitContext"], [])
        ok, reason, _ = _assess_exact_sourcekit_link(
            {"kind": "func", "name": row["name"], "signature": row["signature"]},
            [candidate], {}, tuple(row["context"]))
        self.assertFalse(ok)
        self.assertEqual(reason, "raw-sourcekit-context-does-not-match-interface-context")
        with self.assertRaisesRegex(ValueError, "conflicts with local exact guards"):
            _verified_link_claim(True, local_candidate_count=0, occurrence_count=0,
                                 summary_consistent=True, occurrence_crosscheck=True)

    def test_request_parser_rejects_duplicate_or_conflicting_target(self) -> None:
        request = '''{
 key.request: source.request.indexsource,
 key.sourcefile: "/sdk/Foo.swiftinterface",
 key.compilerargs: [ "/sdk/Foo.swiftinterface", "-sdk", "/sdk", "-target", "arm64-apple-macosx27.0", "-target", "arm64-apple-macosx26.0", "-module-name", "Foo" ]
}'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "request.yaml"
            path.write_text(request, encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate, or conflicting -target"):
                _validate_request_identity(path, interface="/sdk/Foo.swiftinterface",
                                           sdk="/sdk", target="arm64-apple-macosx27.0", module="Foo")

    def test_external_eligibility_cannot_override_local_hold(self) -> None:
        with self.assertRaisesRegex(ValueError, "conflicts with local exact guards"):
            _verified_link_claim(True, local_candidate_count=2, occurrence_count=2,
                                 summary_consistent=True, occurrence_crosscheck=True)
        self.assertFalse(_verified_link_claim(False, local_candidate_count=1, occurrence_count=1,
                                              summary_consistent=True, occurrence_crosscheck=True))


if __name__ == "__main__":
    unittest.main()
