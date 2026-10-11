"""Actual archive byte-reader faults; no compiler/native execution."""
import importlib.util
import json
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[4]
spec = importlib.util.spec_from_file_location('seed_join_v2', HERE / 'verify.py')
v = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v)
MAC = REPO / 'factory/oracle/mac/seed-corrections-v1'
LINEAGE = REPO / 'factory/oracle/mac/seed-corrections-lineage-v2'
PLANS = HERE.parent

class JoinControls(unittest.TestCase):
    def run_verify(self, changes=None):
        changes = changes or {}
        return v.verify(MAC, LINEAGE, PLANS, lambda path: changes.get(str(path), Path(path).read_bytes()))

    def mutate(self, path, change):
        obj = json.loads(path.read_bytes()); change(obj)
        return {str(path): json.dumps(obj).encode()}

    def test_actual_positive(self):
        proof = self.run_verify()
        self.assertEqual(len(proof['cases']), 5)
        self.assertTrue(all(len(row['runs']) == 20 for row in proof['cases']))
        self.assertFalse(proof['windowsCompileValidated'])
        self.assertEqual(proof['nativeParity'], 'hold')

    def test_witness_bytes(self):
        p = LINEAGE / 'cases/stack-overlay/Witness.swift'
        with self.assertRaisesRegex(ValueError, 'archive raw hash'):
            self.run_verify({str(p): p.read_bytes() + b'\n'})

    def test_adapted_host_bytes(self):
        p = LINEAGE / 'cases/stack-overlay/CaptureHost.adapted.swift'
        with self.assertRaisesRegex(ValueError, 'archive raw hash'):
            self.run_verify({str(p): p.read_bytes() + b'\n'})

    def first(self):
        row = json.loads((LINEAGE / 'cases/stack-overlay/lineage.json').read_bytes())
        return row, MAC / row['rawInstrumentedJoins'][0]['rawPath']

    def test_raw_bytes(self):
        _, p = self.first()
        with self.assertRaisesRegex(ValueError, 'raw observation hash'):
            self.run_verify({str(p): p.read_bytes() + b'\n'})

    def test_binary_bytes(self):
        row, _ = self.first(); p = MAC / row['binary']['v1OwnedPath']
        with self.assertRaisesRegex(ValueError, 'binary raw join'):
            self.run_verify({str(p): p.read_bytes() + b'\0'})

    def test_capture_case(self):
        _, p = self.first(); p = p.parent / 'capture.json'
        with self.assertRaisesRegex(ValueError, 'capture case/run'):
            self.run_verify(self.mutate(p, lambda d: d['case'].update(id='forged')))

    def test_count(self):
        row, _ = self.first(); p = MAC / row['rawInstrumentedJoins'][0]['rawSummaryPath']
        with self.assertRaisesRegex(ValueError, 'exact twenty'):
            self.run_verify(self.mutate(p, lambda d: d['runs'].pop()))

    def test_duplicate_run(self):
        row, _ = self.first(); p = MAC / row['rawInstrumentedJoins'][0]['rawSummaryPath']
        with self.assertRaisesRegex(ValueError, 'exact twenty'):
            self.run_verify(self.mutate(p, lambda d: d['runs'][1].update(run=1)))

    def test_timing_failfield_with_consistent_hashes(self):
        row, p = self.first()
        observation = json.loads(p.read_bytes()); observation['monoEndNs'] = observation['monoStartNs']
        raw = json.dumps(observation).encode(); h = v.digest(raw)
        row['rawInstrumentedJoins'][0]['rawSha256'] = h
        row['rawInstrumentedJoins'][0]['summaryInstrumentedRawHash'] = h
        top_path = LINEAGE / 'lineage.json'; top = json.loads(top_path.read_bytes())
        top['cases'] = [row if x['block'] == 'stack-overlay' else x for x in top['cases']]
        summary_path = MAC / row['rawInstrumentedJoins'][0]['rawSummaryPath']; summary = json.loads(summary_path.read_bytes())
        summary['runs'][0]['instrumented']['rawHash'] = h
        changes = {str(p): raw, str(LINEAGE / 'cases/stack-overlay/lineage.json'): json.dumps(row).encode(), str(top_path): json.dumps(top).encode(), str(summary_path): json.dumps(summary).encode()}
        with self.assertRaisesRegex(ValueError, 'raw timing failure'):
            self.run_verify(changes)

    def test_boolean_run(self):
        row, _ = self.first(); p = MAC / row['rawInstrumentedJoins'][0]['rawSummaryPath']
        with self.assertRaisesRegex(ValueError, 'exact twenty'):
            self.run_verify(self.mutate(p, lambda d: d['runs'][0].update(run=True)))

if __name__ == '__main__':
    unittest.main()
