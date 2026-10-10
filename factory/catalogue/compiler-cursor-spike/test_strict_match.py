import copy
import unittest
from pathlib import Path

from strict_match import cursor_result_usr, entity_matches, request_identity_matches, unique_entity_usr


HERE = Path(__file__).resolve().parent
INTERFACE = "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/SwiftUI.framework/Versions/A/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface"
SDK = "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk"
TARGET = "arm64-apple-macosx27.0"


class StrictSourceKitMatchTests(unittest.TestCase):
    def setUp(self):
        self.row = {
            "module": "SwiftUI", "sourceHash": "sha256:interface", "line": 852,
            "kind": "func", "name": "accessibilityLabel", "context": ["View"],
            "signature": "public func accessibilityLabel<V>(content: V) -> some View",
        }
        self.entity = {
            "module": "SwiftUI", "line": 852, "kind": "source.lang.swift.decl.function.method.instance",
            "name": "accessibilityLabel(content:)", "usr": "s:precise", "effective_access": "source.decl.effective_access.public",
            "sourcekitContext": [{"kind": "source.lang.swift.decl.extension.protocol", "name": "View", "usr": "s:extension"}],
        }

    def test_exact_declaration_matches(self):
        self.assertTrue(entity_matches(self.row, self.entity, module="SwiftUI", live_interface_hash="sha256:interface"))

    def test_wrong_interface_identity_does_not_match(self):
        self.assertFalse(entity_matches(self.row, self.entity, module="SwiftUICore", live_interface_hash="sha256:interface"))
        self.assertFalse(entity_matches(self.row, self.entity, module="SwiftUI", live_interface_hash="sha256:other-interface"))

    def test_wrong_line_or_declaration_name_does_not_match(self):
        for field, value in [("line", 853), ("name", "other(content:)" )]:
            changed = copy.deepcopy(self.entity)
            changed[field] = value
            self.assertFalse(entity_matches(self.row, changed, module="SwiftUI", live_interface_hash="sha256:interface"))

    def test_wrong_kind_context_or_access_does_not_match_even_when_usr_is_same(self):
        for field, value in [
            ("kind", "source.lang.swift.decl.var.instance"),
            ("sourcekitContext", [{"kind": "source.lang.swift.decl.extension.protocol", "name": "Other"}]),
            ("effective_access", "source.decl.effective_access.internal"),
        ]:
            changed = copy.deepcopy(self.entity)
            changed[field] = value
            self.assertEqual(changed["usr"], self.entity["usr"])
            self.assertFalse(entity_matches(self.row, changed, module="SwiftUI", live_interface_hash="sha256:interface"))

    def test_unknown_expected_access_is_held(self):
        row = {**self.row, "signature": "case value"}
        entity = {**self.entity, "kind": "source.lang.swift.decl.enumelement", "name": "value"}
        self.assertFalse(entity_matches(row, entity, module="SwiftUI", live_interface_hash="sha256:interface"))

    def test_actor_is_not_promoted_from_unverified_class_entity_kind(self):
        changed_row = {**self.row, "kind": "actor"}
        changed_entity = {**self.entity, "kind": "source.lang.swift.decl.class"}
        self.assertFalse(entity_matches(changed_row, changed_entity, module="SwiftUI", live_interface_hash="sha256:interface"))

    def test_duplicate_same_usr_records_remain_held(self):
        duplicate = copy.deepcopy(self.entity)
        self.assertEqual(self.entity["usr"], duplicate["usr"])
        self.assertIsNone(unique_entity_usr([self.entity, duplicate]))
        self.assertEqual("s:precise", unique_entity_usr([self.entity]))

    def test_cursor_result_uses_root_usr_not_nested_receiver_usr(self):
        response = '{\n  key.receivers: [\n    {\n      key.usr: "s:receiver"\n    }\n  ],\n  key.usr: "s:resolved-declaration",\n  key.kind: source.lang.swift.decl.function\n}\n'
        self.assertEqual("s:resolved-declaration", cursor_result_usr(response))
        self.assertIsNone(cursor_result_usr('{\n  key.internal_diagnostic: "Unable to resolve cursor info."\n}\n'))

    def test_request_identity_is_exact_for_source_target_module_and_sdk(self):
        text = (HERE / "request-index-interface.yaml").read_text()
        self.assertTrue(request_identity_matches(text, interface=INTERFACE, sdk=SDK, target=TARGET, module="SwiftUI"))
        self.assertFalse(request_identity_matches(text, interface=INTERFACE, sdk=SDK, target=TARGET, module="SwiftUICore"))
        self.assertFalse(request_identity_matches(text, interface=INTERFACE, sdk=SDK, target="arm64-apple-macosx26.0", module="SwiftUI"))
        self.assertFalse(request_identity_matches(text, interface=INTERFACE, sdk="/SDK/other.sdk", target=TARGET, module="SwiftUI"))
        self.assertFalse(request_identity_matches(text.replace("source.request.indexsource", "source.request.cursorinfo"), interface=INTERFACE, sdk=SDK, target=TARGET, module="SwiftUI"))
        duplicate = text.replace('"-module-name", "SwiftUI"', '"-module-name", "SwiftUI", "-module-name", "SwiftUI"')
        self.assertFalse(request_identity_matches(duplicate, interface=INTERFACE, sdk=SDK, target=TARGET, module="SwiftUI"))
        self.assertFalse(request_identity_matches(text + '\n key.sourcefile: "' + INTERFACE + '"\n', interface=INTERFACE, sdk=SDK, target=TARGET, module="SwiftUI"))
        self.assertFalse(request_identity_matches(text + '\n key.request: source.request.indexsource\n', interface=INTERFACE, sdk=SDK, target=TARGET, module="SwiftUI"))
        self.assertFalse(request_identity_matches(text + '\n key.compilerargs: []\n', interface=INTERFACE, sdk=SDK, target=TARGET, module="SwiftUI"))


if __name__ == "__main__":
    unittest.main()
