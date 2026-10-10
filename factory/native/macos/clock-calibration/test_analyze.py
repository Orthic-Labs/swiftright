import copy
import importlib.util
import json
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('clock_analyzer', HERE / 'analyze.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class NativeFaultControls(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw = HERE / 'evidence/49bd8dbe-202f-43db-8d02-f2fff41f7116/raw.jsonl'
        cls.rows = [json.loads(line) for line in cls.raw.read_text().splitlines()]

    def test_real_roundtrip_control(self):
        result = module.analyze(self.rows)
        self.assertEqual(result['roundTripDeltaTicks'], {'0': 10000, '-1': 20000})
        self.assertEqual(result['floorScaleConversionModelFailures'], [])
        self.assertEqual(result['makeHostFloorCMTimeModelFailures'], [])
        self.assertTrue(result['strictBracketMisses'])
        self.assertTrue(all(row['belowBeforeTicks'] == 1 for row in result['strictBracketMisses']))
        module.validate_candidate(result)

    def test_injected_tick_domain_error_detected(self):
        rows = copy.deepcopy(self.rows)
        rows[20001]['convertedSystemTicks'] += 100
        result = module.analyze(rows)
        self.assertEqual(result['floorScaleConversionModelFailures'], [{'kind': 'round-trip', 'index': 0}])
        with self.assertRaisesRegex(ValueError, 'candidate contradicted'):
            module.validate_candidate(result)

    def test_injected_cmtime_scale_error_detected(self):
        rows = copy.deepcopy(self.rows)
        rows[20001]['hostTime']['value'] += 100
        result = module.analyze(rows)
        self.assertEqual(result['makeHostFloorCMTimeModelFailures'], [0])
        with self.assertRaisesRegex(ValueError, 'candidate contradicted'):
            module.validate_candidate(result)

    def test_wrong_timebase_rejected_by_candidate_guard(self):
        rows = copy.deepcopy(self.rows)
        rows[0]['machTimebase']['numer'] += 1
        with self.assertRaisesRegex(ValueError, 'candidate contradicted'):
            module.validate_candidate(module.analyze(rows))

    def test_wrong_timescale_rejected_by_candidate_guard(self):
        rows = copy.deepcopy(self.rows)
        rows[20001]['hostTime']['timescale'] -= 1
        with self.assertRaisesRegex(ValueError, 'candidate contradicted'):
            module.validate_candidate(module.analyze(rows))

    def test_raw_clock_shift_rejected_by_candidate_guard(self):
        rows = copy.deepcopy(self.rows)
        rows[1]['machBefore'] += 100
        rows[1]['machAfter'] += 100
        with self.assertRaisesRegex(ValueError, 'candidate contradicted'):
            module.validate_candidate(module.analyze(rows))

    def test_reversed_bracket_rejected(self):
        rows = copy.deepcopy(self.rows)
        rows[1]['machBefore'] = rows[1]['machAfter'] + 1
        with self.assertRaisesRegex(ValueError, 'bracket reversed'):
            module.analyze(rows)

    def test_missing_sample_rejected(self):
        with self.assertRaisesRegex(ValueError, 'complete native row counts'):
            module.analyze(self.rows[:-1])

    def test_invalid_indefinite_time_rejected(self):
        rows = copy.deepcopy(self.rows)
        rows[1]['hostTime']['flags'] = 17
        with self.assertRaisesRegex(ValueError, 'valid finite'):
            module.analyze(rows)

if __name__ == '__main__':
    unittest.main()
