from __future__ import annotations

import copy
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from factory.core import artifacts
from .audit_v10 import (
    ACTOR_LINE,
    ACTOR_NAME,
    ACTOR_VALIDATOR_SHA256,
    EDGE_EVIDENCE_SHA256,
    V9_AUDIT_HASH,
    V9_FILE_SHA256,
    _evaluate_actor_candidate,
    _load_v9,
    _module_validator,
    _validate_module_bridge,
    _validate_actor_bridge,
    build_audit_v10,
)
from . import audit_v7, audit_v8


class AuditV10Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.root = Path(__file__).resolve().parents[2]
        cls.v9_path = cls.root / "factory/catalogue/evidence/interface-audit-v9-candidate.json"
        cls.edge_path = cls.root / "factory/catalogue/compiler-edge-spike/edge-evidence.json"
        cls.module_path = cls.root / "factory/catalogue/module-provenance-spike/module-provenance-evidence.json"
        cls.v9 = _load_v9(cls.v9_path, root=cls.root)
        cls.v7 = audit_v8._load_pinned_v7(cls.root / "factory/catalogue/evidence/interface-audit-v7.json")
        cls.actor = _validate_actor_bridge(cls.v9, root=cls.root, edge_evidence_path=cls.edge_path)
        cls.v10 = build_audit_v10(cls.v9_path, root=cls.root, edge_evidence_path=cls.edge_path,
                                  module_evidence_path=cls.module_path)
        cls.interface_path = Path(next(row["path"] for row in cls.v7["sourceKitAuthority"]["interfaces"]
                                       if row["module"] == "SwiftUICore"))
        cls.interface_text = cls.interface_path.read_text(encoding="utf-8")
        cls.raw = copy.deepcopy(cls.actor["actorResult"]["rawEntity"])
        binary = Path(cls.actor["demangleReceipt"]["toolPath"])
        usr = cls.raw["usr"]
        mangled = "$s" + usr[2:] if usr.startswith("s:") else usr
        cls.demangle_text = subprocess.run([str(binary), "--expand", mangled], check=True,
                                           capture_output=True, text=True).stdout

    def test_candidate_adds_only_exact_actor_and_retains_v9_residuals(self) -> None:
        candidate = self.v10
        self.assertEqual(candidate["parentAudit"]["auditHash"], V9_AUDIT_HASH)
        self.assertEqual(candidate["parentAudit"]["fileSha256"], V9_FILE_SHA256)
        self.assertEqual(candidate["actorBridgeEvidence"]["promotedRows"], 1)
        self.assertEqual(candidate["summary"]["newlyPromotedRows"], 258)
        self.assertEqual(candidate["summary"]["exactSourceKitUsrLinks"], 2543)
        self.assertEqual(candidate["summary"]["heldSourceKitRows"], 6)
        self.assertEqual(candidate["summary"]["sourceKitUsrPresentInSymbolGraph"], 135)
        self.assertEqual(candidate["summary"]["sourceKitUsrAbsentFromSymbolGraph"], 2408)
        self.assertEqual(candidate["summary"]["byClassification"].get("unexplained", 0), 0)
        self.assertEqual(candidate["summary"]["remainingActiveUnmappedAmbiguousOrUnexplained"], 6)
        rows = [row for row in candidate["declarations"] if row.get("module") == "SwiftUICore"
                and row.get("line") == ACTOR_LINE and row.get("name") == ACTOR_NAME]
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["symbol"]["usr"], self.actor["entity"]["usr"])
        self.assertEqual(rows[0]["classification"], "matched-sourcekit-usr-absent-from-symbolgraph")
        body = dict(candidate)
        declared = body.pop("auditHash")
        self.assertEqual(declared, artifacts.canonical_hash(body))
        self.assertEqual(candidate["status"], "incomplete-v10-actor-and-module-origin-consumer-validated")
        self.assertEqual(candidate["moduleOriginBridgeEvidence"]["promotedRows"], 33)
        self.assertEqual(candidate["moduleOriginBridgeEvidence"]["originNominalCount"], 6)
        self.assertEqual(candidate["pendingEvidence"][0]["expectedRows"], 6)
        module_result = _validate_module_bridge(self.v9, root=self.root, module_evidence_path=self.module_path)
        origin_usrs = [r["bridgeRow"]["origin"]["usr"] for r in module_result["promotions"]]
        for row in candidate["declarations"]:
            bridge = row.get("sourceKitEvidence", {}).get("crossModuleOriginBridge")
            if bridge:
                self.assertIn(bridge["originUsr"], origin_usrs)

    def test_exact_receipt_pins_and_live_sourcekit_join(self) -> None:
        self.assertEqual(artifacts.file_hash(self.edge_path), EDGE_EVIDENCE_SHA256)
        self.assertEqual(artifacts.file_hash(self.root / "factory/catalogue/compiler-edge-spike/actor_bridge_validator.py"),
                         ACTOR_VALIDATOR_SHA256)
        self.assertEqual(self.actor["actorResult"]["validator"]["accepted"], True)
        self.assertEqual(self.actor["entity"]["kind"], "source.lang.swift.decl.class")
        self.assertEqual(self.actor["entity"]["effective_access"], "source.decl.effective_access.public")
        swiftui_core = next(row for row in self.v7["sourceKitAuthority"]["interfaces"]
                            if row["module"] == "SwiftUICore")
        self.assertEqual(self.actor["requestSha256"], swiftui_core["indexRequestSha256"])
        self.assertTrue(self.actor["demangleReceipt"]["stdoutSha256"].startswith("sha256:"))

    def test_actor_adapter_rejects_identity_source_access_and_usr_tampering(self) -> None:
        row = dict(self.actor["link"])

        def evaluate(changes=None, raw_changes=None, interface=None, demangle=None):
            candidate = dict(row)
            candidate.update(changes or {})
            raw = [dict(self.raw)]
            raw[0].update(raw_changes or {})
            return _evaluate_actor_candidate(candidate, raw,
                interface_text=self.interface_text if interface is None else interface,
                interface_sha256=row["sourceHash"],
                demangle_text=self.demangle_text if demangle is None else demangle)

        self.assertTrue(evaluate()["validator"]["accepted"])
        for changes in ({"module": "SwiftUI"}, {"kind": "class"}, {"line": ACTOR_LINE + 1},
                        {"name": "OtherActor"}, {"expectedAccess": "internal"}):
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                evaluate(changes)
        for changes in ({"effective_access": "source.decl.effective_access.internal"},
                        {"kind": "source.lang.swift.decl.struct"}, {"is_implicit": True},
                        {"sourcekitContext": [{"name": "Other"}]}, {"usr": "s:7SwiftUI9ForgedActorC"}):
            with self.subTest(raw=changes), self.assertRaises(ValueError):
                evaluate(raw_changes=changes)
        altered = self.interface_text.replace("public actor _ImpossibleActor", "internal actor _ImpossibleActor", 1)
        with self.assertRaisesRegex(ValueError, "interface-bytes"):
            evaluate(interface=altered)
        with self.assertRaisesRegex(ValueError, "usr-tree"):
            evaluate(demangle="Demangling for $s11SwiftUICore16_ImpossibleActorC\nkind=Global, text=\"\"\n  kind=Structure, text=\"\"\n")

    def test_production_join_rejects_changed_evidence_and_v9_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            altered_edge = Path(directory) / "edge.json"
            altered_edge.write_text(self.edge_path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "actor edge evidence bytes"):
                _validate_actor_bridge(self.v9, root=self.root, edge_evidence_path=altered_edge)
            altered_v9 = json.loads(self.v9_path.read_text(encoding="utf-8"))
            altered_v9["summary"]["exactSourceKitUsrLinks"] += 1
            path = Path(directory) / "v9.json"
            path.write_text(json.dumps(altered_v9), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "candidate bytes differ"):
                _load_v9(path, root=self.root)

    def test_module_bridge_rejects_mutated_production_source_and_raw_inputs(self) -> None:
        validator = _module_validator(self.root).Validator()
        self.assertEqual(len(validator.validate()), 33)
        cases = [
            ("SwiftUI:source", "extension SwiftUICore._TestApp", "extension SwiftUICore._ForgedApp"),
            ("SwiftUICore:source", "public struct _TestApp", "public enum _TestApp"),
            ("SwiftUI:index", 'key.usr: "s:7SwiftUI8_TestAppVAAE3runs5NeverOyF"',
             'key.usr: "s:7SwiftUI8_TestAppVAAE3forgeds5NeverOyF"'),
            ("SwiftUICore:index", 'key.usr: "s:11SwiftUICore8_TestAppV"',
             'key.usr: "s:11SwiftUICore9ForgedAppV"'),
            ("SwiftUI:request", '"SwiftUI" ]', '"SwiftUI", "-module-name", "SwiftUI" ]'),
        ]
        for key, old, new in cases:
            raw = dict(validator.inputs)
            self.assertIn(old, raw[key], key)
            raw[key] = raw[key].replace(old, new, 1)
            with self.subTest(key=key), self.assertRaises(ValueError):
                validator.validate(raw)

    def test_module_evidence_bytes_and_candidate_drift_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            altered = Path(directory) / "module-evidence.json"
            altered.write_text(self.module_path.read_text(encoding="utf-8") + "\n", encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "module-origin evidence bytes"):
                _validate_module_bridge(self.v9, root=self.root, module_evidence_path=altered)
        changed = copy.deepcopy(self.v10)
        changed["summary"]["exactSourceKitUsrLinks"] += 1
        body = dict(changed)
        old_hash = body.pop("auditHash")
        self.assertNotEqual(old_hash, artifacts.canonical_hash(body))


if __name__ == "__main__":
    unittest.main()
