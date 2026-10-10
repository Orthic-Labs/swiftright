#!/usr/bin/env python3
import copy
import json
import unittest
from pathlib import Path

import verify_destructors as verifier


class DestructorCaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads((Path(__file__).with_name("destructor-access-evidence.json")).read_text())

    def assert_fault(self, mutate):
        data = copy.deepcopy(self.data)
        mutate(data)
        self.assertTrue(verifier.validate(data), "fault was accepted")

    def test_accepted_baseline(self):
        self.assertEqual(verifier.validate(copy.deepcopy(self.data)), [])

    def test_wrong_usr_rejected(self):
        self.assert_fault(lambda d: d["rows"][0]["cursor"]["fields"].update(usr="wrong"))

    def test_wrong_kind_rejected(self):
        self.assert_fault(lambda d: d["rows"][1]["cursor"]["fields"].update(kind="source.lang.swift.decl.var.instance"))

    def test_wrong_source_offset_rejected(self):
        self.assert_fault(lambda d: d["rows"][2].update(deinitByteOffset=d["rows"][2]["deinitByteOffset"] + 1))

    def test_inferred_access_rejected(self):
        self.assert_fault(lambda d: d["rows"][3]["cursor"].update(accessibility={"status": "observed", "keys": ["effective_access"], "values": {"effective_access": "public"}}))

    def test_failed_request_rejected(self):
        self.assert_fault(lambda d: d["rows"][4]["receipt"].update(exitCode=1))

    def test_source_pin_rejected(self):
        self.assert_fault(lambda d: d["rows"][5]["source"].update(sha256="sha256:wrong"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
