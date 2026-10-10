"""Synthetic unit archives only: never native Windows replay evidence."""
from pathlib import Path
import json
import tempfile
import unittest

from factory.core.artifacts import artifact_ref, file_hash, load_artifact, write_artifact
from factory.pipeline.workflow import HERE, collect, validate_windows_archive


class WindowsArchiveBindings(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='synthetic-unit-windows-')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name) / 'run-01'
        self.directory.mkdir()
        self.case = load_artifact(HERE / 'inputs/cases.json')[0]
        self.case_ref = artifact_ref(self.case)
        d = self.directory
        (d / 'Witness.swift').write_text('// synthetic unit fixture; not native replay\n')
        write_artifact(d / 'plan.json', {'case': self.case_ref, 'sourceHash': file_hash(d / 'Witness.swift'), 'synthetic': True})
        write_artifact(d / 'tuple.json', self.case['tuple'])
        write_artifact(d / 'native.uia.json', {'synthetic': True, 'role': 'UnitFixture'})
        # Byte payload exists solely for receipt hash tests; no image claim.
        (d / 'native.screen.png').write_bytes(b'synthetic-unit-fixture-not-native-PNG')
        (d / 'host.stdout.txt').write_text('synthetic unit fixture')
        self.row = {'index': 1, 'case': self.case_ref, 'sourceHash': file_hash(d / 'Witness.swift'),
            'exeSha256': '1' * 64, 'rendererSha256': self.case['tuple']['rendererHash'].removeprefix('sha256:'),
            'hostValid': True, 'exitCode': 0, 'nativeParity': 'hold', 'occlusionQualified': False,
            'synthetic': True, 'files': [{'path': p.name, 'sha256': file_hash(p).removeprefix('sha256:')}
                for p in [d / 'native.uia.json', d / 'native.screen.png', d / 'host.stdout.txt']]}
        write_artifact(d / 'native-observation.json', [self.row])
        receipt_hash = file_hash(d / 'native-observation.json')
        source_hash = file_hash(d / 'Witness.swift')
        self.capture = {'kind': 'capture', 'platform': 'windows', 'case': self.case_ref, 'tuple': self.case['tuple'],
            'provenance': {'sourceHash': source_hash}, 'meta': {'run': 1, 'host': {'hash': 'sha256:' + '1' * 64},
            'clock': {'correlationHash': receipt_hash}, 'conditions': {'synthetic': True,
            'actualSourceHash': source_hash, 'rawReceiptHash': receipt_hash,
            'rawWitnessHash': source_hash, 'rawPlanHash': file_hash(d / 'plan.json'),
            'actualHostExecutableHash': 'sha256:' + '1' * 64,
            'actualRendererHash': self.case['tuple']['rendererHash'],
            'tupleWindowsHostHash': self.case['tuple']['hostHashes']['windows'],
            'nativeParity': 'hold', 'occlusionQualified': False, 'rawUIAHash': file_hash(d / 'native.uia.json')}}}

    def test_adjacent_windows_contract(self):
        validate_windows_archive(self.capture, self.directory)

    def test_source_mutation(self):
        (self.directory / 'Witness.swift').write_text('mutated synthetic source')
        with self.assertRaisesRegex(ValueError, 'source/plan/case'):
            validate_windows_archive(self.capture, self.directory)

    def test_raw_receipt_mutation(self):
        with (self.directory / 'native-observation.json').open('ab') as stream:
            stream.write(b' ')
        with self.assertRaisesRegex(ValueError, 'receipt/clock'):
            validate_windows_archive(self.capture, self.directory)

    def test_raw_receipt_bom_native_float_supported(self):
        self.row['syntheticNativeElapsedMs'] = 1.25
        receipt = self.directory / 'native-observation.json'
        receipt.write_text(json.dumps([self.row]), encoding='utf-8-sig')
        h = file_hash(receipt)
        self.capture['meta']['conditions']['rawReceiptHash'] = h
        self.capture['meta']['clock']['correlationHash'] = h
        validate_windows_archive(self.capture, self.directory)

    def test_duplicate_raw_receipt_keys_rejected(self):
        receipt = self.directory / 'native-observation.json'
        receipt.write_text('[{"index":1,"index":2,"synthetic":true}]')
        h = file_hash(receipt)
        self.capture['meta']['conditions']['rawReceiptHash'] = h
        self.capture['meta']['clock']['correlationHash'] = h
        with self.assertRaisesRegex(ValueError, 'duplicate key'):
            validate_windows_archive(self.capture, self.directory)

    def test_plan_metadata_mutation(self):
        plan = load_artifact(self.directory / 'plan.json')
        plan['unboundMetadata'] = 'mutated synthetic fixture'
        write_artifact(self.directory / 'plan.json', plan)
        with self.assertRaisesRegex(ValueError, 'witness/plan/tuple'):
            validate_windows_archive(self.capture, self.directory)

    def test_tuple_archive_mutation(self):
        tuple_value = load_artifact(self.directory / 'tuple.json')
        tuple_value['factoryVersion'] = 'mutated-synthetic'
        write_artifact(self.directory / 'tuple.json', tuple_value)
        with self.assertRaisesRegex(ValueError, 'witness/plan/tuple'):
            validate_windows_archive(self.capture, self.directory)

    def test_raw_uia_mutation(self):
        write_artifact(self.directory / 'native.uia.json', {'synthetic': True, 'changed': True})
        with self.assertRaisesRegex(ValueError, 'file hash'):
            validate_windows_archive(self.capture, self.directory)

    def test_receipt_case_mutation_with_rebound_hash(self):
        self.row['case'] = {'id': self.case_ref['id'], 'hash': 'sha256:' + '0' * 64}
        write_artifact(self.directory / 'native-observation.json', [self.row])
        h = file_hash(self.directory / 'native-observation.json')
        self.capture['meta']['conditions']['rawReceiptHash'] = h
        self.capture['meta']['clock']['correlationHash'] = h
        with self.assertRaisesRegex(ValueError, 'receipt case/source/host'):
            validate_windows_archive(self.capture, self.directory)

    def test_receipt_path_escape_rejected(self):
        self.row['files'][0]['path'] = '../outside.json'
        write_artifact(self.directory / 'native-observation.json', [self.row])
        h = file_hash(self.directory / 'native-observation.json')
        self.capture['meta']['conditions']['rawReceiptHash'] = h
        self.capture['meta']['clock']['correlationHash'] = h
        with self.assertRaisesRegex(ValueError, 'escapes'):
            validate_windows_archive(self.capture, self.directory)

    def test_recursive_native_filename_still_rejects_synthetic(self):
        write_artifact(self.directory / 'capture.json', self.capture)
        value = collect([self.case], [self.directory.parent])
        self.assertEqual(value['captures'], [])
        self.assertIn('synthetic', value['diagnostics'][0]['reason'])
        self.assertEqual(Path(value['diagnostics'][0]['path']).name, 'capture.json')


if __name__ == '__main__':
    unittest.main()
