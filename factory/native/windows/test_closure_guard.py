import json
from pathlib import Path
import tempfile
import unittest
from factory.core.artifacts import file_hash
from factory.native.windows.closure_guard import validate

class ClosureGuardTests(unittest.TestCase):
    def test_exact_unique_tuple_and_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);status=root/'status.md';receipt=root/'receipt.json'
            def write(text, **changes):
                status.write_text(text)
                value={'tuple':'10','decision':'CLOSED','closedAt':'2026-01-01T00:00:00Z','statusHash':file_hash(status)}
                value.update(changes);receipt.write_text(json.dumps(value))
            write('**Overall: SR0 is CLOSED on tuple10.**\n');self.assertEqual(validate(status,receipt)['tuple'],'10')
            for text in ('**Overall: SR0 is CLOSED on tuple08.**\n','**Overall: SR0 is CLOSED on tuple10.**\n**Overall: SR0 is OPEN.**\n','**Overall: SR0 is CLOSED.**\n'):
                write(text)
                with self.assertRaises(ValueError):validate(status,receipt)
            for changes in ({'synthetic':True},{'context':{'synthetic':True}},{'tuple':'08'},{'statusHash':'sha256:'+'0'*64},{'closedAt':'2099-01-01T00:00:00Z'},{'closedAt':'2026-01-01T00:00:00+00:00'}):
                write('**Overall: SR0 is CLOSED on tuple10.**\n',**changes)
                with self.assertRaises(ValueError):validate(status,receipt)
