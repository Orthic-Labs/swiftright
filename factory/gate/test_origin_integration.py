"""Origin admission wiring; synthetic byte fixtures do not qualify native runs."""
import copy
import tempfile
import unittest
from pathlib import Path

from factory.gate.core import _origin_issues, evaluate_gate
from factory.gate.test_gate import fixture
from factory.gate.test_mac_origin_admission import OriginFixture
from factory.gate.test_windows_exit_admission import Fixture


class OriginIntegrationTests(unittest.TestCase):
    def test_reader_required_even_when_labels_claim_pass(self):
        issues = []
        _origin_issues([{'id': 'forged', 'platform': 'windows',
                         'verified': True, 'status': 'pass'}], None, issues)
        self.assertIn('native origin archive reader unavailable; qualification held', issues)

    def test_windows_reads_bytes_scoped_to_capture(self):
        fixture = Fixture()
        fixture.capture['id'] = 'windows.fixture'
        calls = []
        def reader(*, capture, reference):
            self.assertIs(capture, fixture.capture)
            calls.append(reference)
            return fixture.reader(reference)
        issues = []
        _origin_issues([fixture.capture], reader, issues)
        self.assertEqual([], issues)
        self.assertTrue(calls)

    def test_mac_reads_bound_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = OriginFixture(Path(directory))
            issues = []
            _origin_issues([fixture.capture],
                           lambda *, capture, reference: fixture.reader(reference), issues)
            self.assertEqual([], issues)

    def test_reader_verdict_cannot_replace_archive_bytes(self):
        fixture = Fixture()
        fixture.capture['id'] = 'forged'
        issues = []
        _origin_issues([fixture.capture],
                       lambda **kwargs: {'verified': True, 'status': 'pass'}, issues)
        self.assertTrue(issues)
        self.assertTrue(all('native origin' in issue for issue in issues))

    def test_corrupt_bytes_reject_even_with_pass_labels(self):
        fixture = Fixture()
        capture = copy.deepcopy(fixture.capture)
        capture.update(id='corrupt', verified=True, status='pass')
        issues = []
        _origin_issues([capture], lambda **kwargs: b'wrong archive bytes', issues)
        self.assertTrue(issues)

    def test_reader_failure_is_held(self):
        issues = []
        def unavailable(**kwargs):
            raise OSError('archive unavailable')
        _origin_issues([{'id': 'missing', 'platform': 'macos'}], unavailable, issues)
        self.assertTrue(issues)

    def test_seeded_runner_captures_also_require_origin(self):
        recipe, case, tuple_value = fixture()
        captured = []
        def run_seeded(**kwargs):
            row = {'id': 'seeded.native', 'platform': 'windows',
                   'case': {'id': kwargs['cases'][0]['id'], 'hash': 'wrong'},
                   'meta': {'conditions': {'verified': True}}, 'tuple': tuple_value}
            captured.append(row)
            return [row]
        result = evaluate_gate(
            recipe=recipe, cases=[case], captures=[], tuple_value=tuple_value,
            seed=47, seeded_capture_runner=run_seeded,
            origin_reader=lambda **kwargs: b'',
        )
        self.assertEqual(1, len(captured))
        self.assertTrue(any('seeded.native: native origin:' in issue
                            for issue in result['report']['issues']))
        self.assertNotEqual('pass', result['report']['status'])


if __name__ == '__main__':
    unittest.main()
