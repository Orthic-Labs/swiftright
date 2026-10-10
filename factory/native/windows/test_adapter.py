import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from factory.native.windows import adapter
from factory.core.artifacts import file_hash

class AdapterGuards(unittest.TestCase):
    def test_reject_escape_hash_and_invalid_type_without_outputs(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            source = base / 'Witness.swift'
            source.write_text('import SwiftRightRuntime\nstruct Witness: View { var body: some View { Text("Hi") } }')
            manifest = {'sourceFile': source.name, 'sourceHash': file_hash(source), 'witnessType': 'Witness',
                        'case': {'id': 'test-only', 'hash': 'sha256:' + '0'*64}, 'compileExpectation': 'success'}
            path = base / 'manifest.json'
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'below factory'):
                adapter.prepare(path, base / 'outside')
            manifest['sourceFile'] = '../Witness.swift'
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'basename'):
                adapter.prepare(path, base / 'outside')
            manifest['sourceFile'] = source.name
            manifest['sourceHash'] = 'sha256:' + '0'*64
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'hash mismatch'):
                adapter.prepare(path, base / 'outside')
            manifest['sourceHash'] = file_hash(source)
            manifest['witnessType'] = 'Witness(); fatalError()'
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(ValueError, 'invalid witness'):
                adapter.prepare(path, base / 'outside')
            self.assertFalse((base / 'outside').exists())

if __name__ == '__main__': unittest.main()
