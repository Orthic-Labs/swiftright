from pathlib import Path
import tempfile
import unittest
from factory.native.windows.normalize import number, normalize

class NativeNormalizationGuards(unittest.TestCase):
    def test_preserves_fractional_coordinates_without_bare_floats(self):
        self.assertEqual(number(1.25), {'$decimal': '1.25'})
        self.assertEqual(number(2.0), 2)
        with self.assertRaisesRegex(ValueError, 'nonfinite'): number(float('nan'))
    def test_rejects_output_escape_before_reading_receipt(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(ValueError, 'under Windows factory'):
                normalize(Path(temp), Path(temp)/'tuple.json', Path(temp)/'out')

class SyntheticArchiveIntegration(unittest.TestCase):
    """Unit byte bindings only; fixtures never count as native evidence."""
    def setUp(self):
        import json
        import struct
        from factory.core.artifacts import file_hash, write_artifact
        lane = Path(__file__).resolve().parent
        self.temp = tempfile.TemporaryDirectory(prefix='synthetic-unit-', dir=lane)
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package = self.root / 'package'
        witness = self.package / 'Sources/FactoryProbe/Witness.swift'
        witness.parent.mkdir(parents=True)
        witness.write_text('// synthetic unit fixture; never native replay\n')
        sample = json.loads((lane.parents[1] / 'spec/examples/rectangle-v0.1/capture-windows-candidate.json').read_text())
        self.tuple_path = self.root / 'tuple.json'
        write_artifact(self.tuple_path, sample['tuple'])
        self.plan = {'case': sample['case'], 'sourceHash': file_hash(witness), 'synthetic': True}
        write_artifact(self.package / 'plan.json', self.plan)
        self.rows = []
        for index in range(1, 21):
            run = self.package / f'native-{index:02d}'
            run.mkdir()
            write_artifact(run / 'native.uia.json', {'synthetic': True, 'automationId': 'unit',
                'controlType': 'ControlType.Button', 'name': 'Unit fixture', 'enabled': False,
                'offscreen': False, 'bounds': [0, 0, 10, 10], 'children': []})
            # Minimal header tests byte plumbing only, never screenshot decoding.
            (run / 'native.screen.png').write_bytes(b'\x89PNG\r\n\x1a\n' + b'\0' * 8 + struct.pack('>II', 10, 10))
            (run / 'host.stdout.txt').write_text('SYNTHETIC UNIT FIXTURE\nFACTORY_RENDERER_READY scale=1.25\nFACTORY_RENDERER_COMMIT\n')
            (run / 'host.stderr.txt').write_text('synthetic unit fixture')
            self.rows.append({'index': index, 'case': sample['case'], 'sourceHash': self.plan['sourceHash'],
                'exeSha256': '1' * 64, 'rendererSha256': sample['tuple']['rendererHash'].removeprefix('sha256:'),
                'hostValid': True, 'exitCode': 0, 'nativeParity': 'hold', 'occlusionQualified': False,
                'synthetic': True, 'files': [{'path': p.name, 'sha256': file_hash(p).removeprefix('sha256:')}
                    for p in sorted(run.iterdir())]})
        write_artifact(self.package / 'native-observation.json', self.rows)

    def test_twenty_adjacent_archives_bind_bytes_to_collector(self):
        import json
        from factory.core.artifacts import file_hash
        from factory.pipeline.workflow import validate_windows_archive
        paths = normalize(self.package, self.tuple_path, self.root / 'normalized')
        self.assertEqual(len(paths), 20)
        self.assertEqual(paths[0].relative_to(self.root).as_posix(), 'normalized/run-001/capture.json')
        for index, path in enumerate(paths, 1):
            capture = json.loads(path.read_text())
            archive = path.parent
            validate_windows_archive(capture, archive)
            self.assertIs(capture['meta']['conditions']['synthetic'], True)
            self.assertEqual(capture['images'][0]['hash'], file_hash(archive / 'native.screen.png'))
            self.assertEqual(capture['meta']['conditions']['rawPlanHash'], file_hash(archive / 'plan.json'))
            self.assertEqual(capture['provenance']['sourceHash'], file_hash(archive / 'Witness.swift'))
            self.assertEqual((archive / 'native-observation.json').read_bytes(), (self.package / 'native-observation.json').read_bytes())
        with self.assertRaisesRegex(ValueError, 'archive exists'):
            normalize(self.package, self.tuple_path, self.root / 'normalized')

    def test_late_raw_mutation_leaves_no_partial_archive(self):
        (self.package / 'native-20/native.uia.json').write_text('{}')
        output = self.root / 'normalized'
        with self.assertRaisesRegex(ValueError, 'file hash mismatch'):
            normalize(self.package, self.tuple_path, output)
        self.assertFalse(output.exists())

    def test_relative_traversal_rejected_before_copy(self):
        from factory.core.artifacts import write_artifact
        self.rows[0]['files'][0]['path'] = '../native-01/host.stderr.txt'
        write_artifact(self.package / 'native-observation.json', self.rows)
        with self.assertRaisesRegex(ValueError, 'escapes replay archive'):
            normalize(self.package, self.tuple_path, self.root / 'normalized')

if __name__ == '__main__': unittest.main()
