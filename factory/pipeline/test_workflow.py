"""Binding tests use existing measured native archives, never parity fixtures."""
from pathlib import Path
import shutil
import tempfile
import unittest

from factory.core.artifacts import load_artifact, write_artifact
from factory.pipeline.workflow import HERE, ROOT, collect, fresh_output, prepare, validate_batch, gate_evidence, validate_primary_source


class PipelineBindings(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.cases = load_artifact(HERE / 'inputs/cases.json')

    def archive(self):
        root = ROOT / 'factory/native/macos/evidence/20261010-primary-five-r3'
        source = next(root.rglob('capture.json'), None)
        if source is None:
            self.skipTest('measured native archive absent')
        target = self.base / 'native/run-1'
        shutil.copytree(source.parent, target)
        return target / 'capture.json'

    def test_current_batch_is_protected(self):
        for name in ('inputs', 'manifests', 'cases', 'probes'):
            with self.assertRaisesRegex(ValueError, 'protected'):
                fresh_output(HERE / name / 'new')

    def test_config_hash_checked_before_writing(self):
        config = load_artifact(HERE / 'inputs/acceptance-candidate.json')
        config['mode'] = 'changed'
        write_artifact(self.base / 'config.json', config)
        with self.assertRaisesRegex(ValueError, 'does not bind'):
            prepare(self.base / 'output', HERE / 'inputs/observed-tuple.json', self.base / 'config.json')
        self.assertFalse((self.base / 'output').exists())

    def test_future_prepare_reproducible_case_artifacts(self):
        from factory.core.artifacts import file_hash
        outputs = [self.base / 'future-a', self.base / 'future-b']
        summaries = [prepare(out, HERE / 'inputs/observed-tuple.json',
            HERE / 'inputs/acceptance-candidate.json', seed=19) for out in outputs]
        self.assertEqual(summaries[0], summaries[1])
        self.assertEqual(file_hash(outputs[0] / 'cases.json'), file_hash(outputs[1] / 'cases.json'))
        self.assertGreater(summaries[0]['caseDenominator'], 0)
        self.assertEqual(summaries[0]['blocks'], 10)
        self.assertFalse(summaries[0]['acceptedDenominator'])

    def test_prepare_rejects_seed_outside_bound_baseline(self):
        from factory.core.artifacts import canonical_hash
        config = load_artifact(HERE / 'inputs/acceptance-candidate.json')
        config['baseline'] = {'version': '1', 'recipes': [{'recipe': {'id': 'synthetic-unit-only', 'hash': 'sha256:' + '1' * 64}, 'seed': 5, 'cases': []}]}
        measured = load_artifact(HERE / 'inputs/observed-tuple.json')
        measured['acceptanceConfigHash'] = canonical_hash(config)
        write_artifact(self.base / 'config.json', config)
        write_artifact(self.base / 'tuple.json', measured)
        with self.assertRaisesRegex(ValueError, 'bound baseline seed'):
            prepare(self.base / 'output', self.base / 'tuple.json', self.base / 'config.json', seed=6)
        self.assertFalse((self.base / 'output').exists())

    def test_actual_native_archive_binding(self):
        path = self.archive()
        value = collect(self.cases, [path.parents[1]])
        self.assertEqual(len(value['captures']), 1)
        self.assertEqual(value['diagnostics'], [])
        self.assertTrue(all(Path(f['path']).exists() for f in value['archives'][0]['files']))

    def test_duplicate_id_rejected(self):
        path = self.archive()
        shutil.copytree(path.parent, path.parent.parent / 'run-2')
        result = collect(self.cases, [path.parents[1]])
        self.assertEqual(len(result['captures']), 1)
        self.assertIn('repeated capture ID', result['diagnostics'][0]['reason'])

    def test_explicit_superseded_directory_keeps_new_capture(self):
        path = self.archive()
        replacement = path.parent.parent / 'run-2'
        shutil.copytree(path.parent, replacement)
        result = collect(self.cases, [path.parents[1]], [path.parent])
        self.assertEqual(len(result['captures']), 1)
        self.assertEqual(len(result['supersededArchives']), 1)
        self.assertEqual(result['diagnostics'], [])
        self.assertEqual(Path(result['archives'][0]['path']).parent, replacement)

    def test_superseded_directory_cannot_escape_selected_root(self):
        self.archive()
        with self.assertRaisesRegex(ValueError, 'explicitly selected'):
            collect(self.cases, [self.base / 'native'], [self.base])

    def test_selected_primary_source_must_match_current_lineage(self):
        with self.assertRaisesRegex(ValueError, 'source lineage'):
            validate_primary_source(self.cases[0], [{'sourceHash': 'sha256:' + '1' * 64}], [],
                [{'synthetic': True, 'sourceHash': 'sha256:' + '2' * 64}], [])

    def test_superseded_primary_requires_full_replacement20(self):
        from factory.core.artifacts import artifact_ref
        rows = [{'platform': 'macos', 'meta': {'run': n}, 'synthetic': True} for n in range(1, 21)]
        lineage = [{'sourceHash': 'sha256:' + '1' * 64}]
        refs = [{'case': artifact_ref(self.cases[0]), 'synthetic': True}]
        validate_primary_source(self.cases[0], lineage, rows, [], refs)
        with self.assertRaisesRegex(ValueError, 'complete20'):
            validate_primary_source(self.cases[0], lineage, rows[:-1], [], refs)

    def test_stale_case_rejected(self):
        path = self.archive()
        capture = load_artifact(path)
        capture['case']['hash'] = 'sha256:' + '0' * 64
        write_artifact(path, capture)
        result = collect(self.cases, [path.parents[1]])
        self.assertEqual(result['captures'], [])
        self.assertIn('stale', result['diagnostics'][0]['reason'])

    def test_synthetic_rejected(self):
        path = self.archive()
        capture = load_artifact(path)
        capture['meta']['conditions']['synthetic'] = True
        write_artifact(path, capture)
        result = collect(self.cases, [path.parents[1]])
        self.assertEqual(result['captures'], [])
        self.assertIn('synthetic', result['diagnostics'][0]['reason'])

    def test_missing_png_archive_rejected(self):
        path = self.archive()
        for png in path.parent.glob('*.png'):
            png.unlink()
        result = collect(self.cases, [path.parents[1]])
        self.assertEqual(result['captures'], [])
        self.assertIn('PNG', result['diagnostics'][0]['reason'])

    def test_no_archive_guessing(self):
        self.archive()
        result = collect(self.cases, [self.base / 'different-selected-root'])
        self.assertEqual(result['captures'], [])
        self.assertEqual(len(result['diagnostics']), 1)

    def test_raw_source_hash_rejected(self):
        path = self.archive()
        with (path.parent / 'instrumented.raw.json').open('ab') as stream:
            stream.write(b' ')
        result = collect(self.cases, [path.parents[1]])
        self.assertEqual(result['captures'], [])
        self.assertIn('raw source hash', result['diagnostics'][0]['reason'])

    def test_clock_correlation_rejected(self):
        path = self.archive()
        clock = load_artifact(path.parent / 'clock.json')
        clock['endNs'] += 1
        write_artifact(path.parent / 'clock.json', clock)
        result = collect(self.cases, [path.parents[1]])
        self.assertEqual(result['captures'], [])
        self.assertIn('clock correlation', result['diagnostics'][0]['reason'])

    def test_manifest_wrapper_and_bare(self):
        expansion = load_artifact(HERE / 'manifests/swiftui.disabled.json')
        selected = [c for c in self.cases if c['block'] == 'swiftui.disabled']
        validate_batch(expansion, selected)
        validate_batch(expansion['manifest'], selected)

    def test_recorded_seed_receipt_uses_exact_case_hash(self):
        from factory.core.artifacts import artifact_ref
        plan_path = HERE / 'gate-pilot/gate-results.json'
        if not plan_path.exists():
            self.skipTest('recorded runtime seed plan absent')
        result = gate_evidence(self.base / 'reevaluation', plan_path, HERE / 'inputs/cases.json',
            [self.base / 'missing-native'], HERE / 'inputs/observed-tuple.json',
            HERE / 'inputs/acceptance-candidate.json', HERE / 'manifests')
        seed_cases = load_artifact(HERE / 'gate-pilot/seed-cases.json')
        refs = [v for r in result['gateResults'] for v in r['report']['cases']]
        self.assertTrue(all(artifact_ref(c) in refs for c in seed_cases))
        self.assertEqual(result['status'], 'blocked')
        self.assertEqual(result['nativeCaptureCount'], 0)


if __name__ == '__main__':
    unittest.main()
