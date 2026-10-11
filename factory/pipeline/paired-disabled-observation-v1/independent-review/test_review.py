from __future__ import annotations
import copy, json, unittest
from pathlib import Path
from review import (ROOT, MANIFEST_PATH, MANIFEST_SHA, REPORT_SHA, ReviewError,
                    load_payloads, audit_payloads)

class IndependentReviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest_raw, cls.manifest, cls.payloads = load_payloads()
        cls.result = audit_payloads(cls.manifest_raw, cls.manifest, cls.payloads)
    def test_baseline_has_all_raw_joins_and_holds(self):
        self.assertEqual(self.result["producerPacket"]["inputCount"],78)
        self.assertEqual(self.result["producerPacket"]["macRuns"],20)
        self.assertEqual(self.result["channels"]["qualifiedTiming"],"unavailable")
        self.assertEqual(self.result["channels"]["hitTesting"],"untested")
        self.assertEqual(self.result["channels"]["nativeParity"],"held")
        self.assertEqual(self.result["channels"]["promotion"],"none")
    def test_changed_manifest_is_rejected(self):
        with self.assertRaises(ReviewError): audit_payloads(self.manifest_raw+b" ", self.manifest, self.payloads)
    def test_missing_payload_is_rejected(self):
        changed=dict(self.payloads); changed.pop(next(iter(changed)))
        with self.assertRaises(ReviewError): audit_payloads(self.manifest_raw,self.manifest,changed)
    def test_changed_source_is_rejected(self):
        changed=dict(self.payloads); path=next(r["path"] for r in self.manifest["inputs"] if r["role"]=="probe-source")
        changed[path]=changed[path].replace(b"Button",b"Group",1)
        with self.assertRaises(ReviewError): audit_payloads(self.manifest_raw,self.manifest,changed)
    def test_changed_windows_enabled_is_rejected(self):
        changed=dict(self.payloads); path=next(r["path"] for r in self.manifest["inputs"] if r["role"]=="windows-native.uia.json")
        changed[path]=changed[path].replace(b'"enabled":  true',b'"enabled":  false',1)
        with self.assertRaises(ReviewError): audit_payloads(self.manifest_raw,self.manifest,changed)
    def test_changed_native_hold_is_rejected(self):
        changed=dict(self.payloads); path=next(r["path"] for r in self.manifest["inputs"] if r["role"]=="windows-native-observation")
        changed[path]=changed[path].replace(b'"nativeParity":  "hold"',b'"nativeParity":  "pass"',1)
        with self.assertRaises(ReviewError): audit_payloads(self.manifest_raw,self.manifest,changed)

if __name__ == "__main__": unittest.main(verbosity=2)
