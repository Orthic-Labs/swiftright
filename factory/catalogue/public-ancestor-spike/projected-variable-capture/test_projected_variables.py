#!/usr/bin/env python3
import copy
import json
import unittest
from pathlib import Path

import verify_projected_variables as verifier


class ProjectedVariableCaptureTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads((Path(__file__).with_name("projected-variable-evidence.json")).read_text())

    def test_accepted_capture(self):
        self.assertEqual(verifier.validate(copy.deepcopy(self.data)), [])

    def assert_fault(self, mutate):
        data = copy.deepcopy(self.data)
        mutate(data)
        self.assertTrue(verifier.validate(data), "fault was accepted")

    def test_wrong_cursor_usr_rejected(self):
        self.assert_fault(lambda d: d["rows"][0]["cursor"]["fields"].update(usr="wrong"))

    def test_wrong_source_offset_rejected(self):
        self.assert_fault(lambda d: d["rows"][1].update(nameByteOffset=d["rows"][1]["nameByteOffset"] + 1))

    def test_wrong_raw_context_rejected(self):
        self.assert_fault(lambda d: d["rows"][2]["rawIdentity"]["occurrences"][0]["sourcekitContext"][0].update(name="Wrong"))

    def test_third_duplicate_rejected(self):
        def mutate(d):
            d["rows"][3]["rawIdentity"]["occurrences"].append(copy.deepcopy(d["rows"][3]["rawIdentity"]["occurrences"][0]))
        self.assert_fault(mutate)

    def test_wrong_tool_exit_rejected(self):
        self.assert_fault(lambda d: d["rows"][4]["receipt"].update(exitCode=1))

    def test_wrong_source_pin_rejected(self):
        self.assert_fault(lambda d: d["inputs"]["source"].update(sha256="sha256:wrong"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
