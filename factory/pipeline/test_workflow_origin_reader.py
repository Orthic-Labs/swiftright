"""Workflow origin-reader wiring; archive guard fixtures remain test-only."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from factory.core.artifacts import artifact_ref, write_artifact
from factory.gate.core import _origin_issues
from factory.gate.test_windows_exit_admission import Fixture as WindowsFixture
from factory.pipeline import workflow


class WorkflowOriginReaderTests(unittest.TestCase):
    def setUp(self):
        self.scratch_root = workflow.ROOT / '.factory-work' / 'workflow-origin-reader-tests'
        self.scratch_root.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=self.scratch_root)
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.fixture = WindowsFixture()
        self.capture = self.fixture.capture
        # Workflow routes captures by case ID; the exit guard accepts the same
        # exact case value from every bound raw record.
        case = {'id': 'base-case'}
        self.capture['case'] = case
        self.fixture.objects['plan']['case'] = case
        self.fixture.objects['observation'][0]['case'] = case
        self.fixture.rebind()
        self.recipe = {'kind': 'recipe', 'id': 'recipe-one', 'block': 'block-one', 'axes': []}
        self.case = {'id': 'base-case', 'block': 'block-one'}
        self.seeded = {'id': 'seed-case', 'kind': 'case', 'version': '1',
                       'block': 'block-one', 'inputs': {}, 'coverage': 'gate-seeded',
                       'seed': 17, 'tuple': {}, 'recipe': {}, 'expectedCaseSetHash': 'test-hash'}
        self.tuple_value = {'test-only': True}
        self.config = {'normalizers': []}
        self.manifests = self.base / 'manifests'
        self.manifests.mkdir()
        write_artifact(self.manifests / 'block-one.json', {'manifest': True})
        self.cases_path = self.base / 'cases.json'
        self.tuple_path = self.base / 'tuple.json'
        self.config_path = self.base / 'config.json'
        write_artifact(self.cases_path, [self.case])
        write_artifact(self.tuple_path, self.tuple_value)
        write_artifact(self.config_path, self.config)

    def _mock_evaluator(self, observed):
        def evaluate_gate(**kwargs):
            observed.append(kwargs['origin_reader'])
            issues = []
            _origin_issues(kwargs['captures'], kwargs['origin_reader'], issues)
            return {'issues': issues}
        return evaluate_gate

    def _workflow_patches(self, observed):
        return (
            patch('factory.pipeline.workflow.load_recipes', return_value=[self.recipe]),
            patch('factory.pipeline.workflow.collect', return_value={
                'captures': [self.capture], 'diagnostics': [], 'supersededArchives': []}),
            patch('factory.pipeline.workflow.validate_batch'),
            patch('factory.pipeline.workflow.generate_probe', side_effect=self._write_probe),
            patch('factory.gate.core.evaluate_gate', side_effect=self._mock_evaluator(observed)),
            patch('factory.gate.core.expand_gate_seeded_cases', return_value=[self.seeded]),
        )

    def _write_probe(self, _recipe, case, output):
        path = Path(output) / 'test.manifest.json'
        write_artifact(path, {'case': {'id': case['id']}})
        return path

    def _run_gate(self, origin_reader):
        observed = []
        patches = self._workflow_patches(observed)
        with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5]:
            result = workflow.gate(self.base / 'gate-output', self.cases_path, [], self.tuple_path,
                                   self.config_path, self.manifests, test_seed=17,
                                   origin_reader=origin_reader)
        return result, observed

    def _run_gate_evidence(self, origin_reader):
        observed = []
        plan_path = self.base / 'prior' / 'gate-results.json'
        plan_path.parent.mkdir(parents=True)
        write_artifact(plan_path, {'seed': 17, 'seedPlan': [{
            'block': 'block-one', 'cases': [artifact_ref(self.seeded)], 'commands': []}]})
        write_artifact(plan_path.parent / 'seed-cases.json', [self.seeded])
        patches = self._workflow_patches(observed)
        with patches[0], patches[1], patches[2], patches[3], patches[4], patches[5]:
            result = workflow.gate_evidence(self.base / 'evidence-output', plan_path,
                self.cases_path, [], self.tuple_path, self.config_path, self.manifests,
                origin_reader=origin_reader)
        return result, observed

    def _reader(self, *, capture, reference):
        self.assertIs(capture, self.capture)
        return self.fixture.reader(reference)

    def test_gate_forwards_reader_to_archive_guard(self):
        result, observed = self._run_gate(self._reader)
        self.assertEqual(observed, [self._reader])
        self.assertEqual(result['gateResults'][0]['issues'], [])

    def test_gate_defaults_to_fail_closed_origin_hold(self):
        result, observed = self._run_gate(None)
        self.assertEqual(observed, [None])
        self.assertIn('native origin archive reader unavailable; qualification held',
                      result['gateResults'][0]['issues'])

    def test_gate_evidence_forwards_reader_to_archive_guard(self):
        result, observed = self._run_gate_evidence(self._reader)
        self.assertEqual(observed, [self._reader])
        self.assertEqual(result['gateResults'][0]['issues'], [])

    def test_gate_evidence_defaults_to_fail_closed_origin_hold(self):
        result, observed = self._run_gate_evidence(None)
        self.assertEqual(observed, [None])
        self.assertIn('native origin archive reader unavailable; qualification held',
                      result['gateResults'][0]['issues'])


if __name__ == '__main__':
    unittest.main()
