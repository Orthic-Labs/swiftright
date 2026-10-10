from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.canonical_json import CanonicalJSONError, dumps, loads, sha256


class CanonicalJSONTests(unittest.TestCase):
    def test_canonical_text_is_unicode_compact_and_ordered(self) -> None:
        value = loads('{"z":1,"é":"雪","a":{"$decimal":"-0.000"}}')
        self.assertEqual(dumps(value), '{"a":{"$decimal":"0"},"z":1,"é":"雪"}')

    def test_hash_does_not_depend_on_input_key_order(self) -> None:
        self.assertEqual(sha256(loads('{"b":2,"a":1}')), sha256(loads('{"a":1,"b":2}')))

    def test_rejects_ambiguous_or_noncanonical_input(self) -> None:
        for text in (
            '{"a":1,"a":2}',
            '{"measurement":1.5}',
            '{"$decimal":"1e3"}',
            '{"$decimal":"1","other":2}',
            '{"text":"\\ud800"}',
            '{"n":NaN}',
        ):
            with self.subTest(text=text):
                with self.assertRaises(CanonicalJSONError):
                    loads(text)


if __name__ == "__main__":
    unittest.main()
