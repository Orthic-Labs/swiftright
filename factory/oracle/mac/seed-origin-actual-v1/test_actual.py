#!/usr/bin/env python3
from __future__ import annotations
import copy, json, shutil, tempfile, unittest
from pathlib import Path
import verify_actual

ROOT = Path(__file__).parent

class ActualV1(unittest.TestCase):
    def mutated(self, mutate):
        with tempfile.TemporaryDirectory() as td:
            dst = Path(td)/'capture'; shutil.copytree(ROOT, dst)
            mutate(dst)
            with self.assertRaises(Exception): verify_actual.validate(dst)

    def test_positive(self): self.assertEqual(verify_actual.validate(ROOT)['runs'], 100)
    def test_missing_run_rejected(self):
        self.mutated(lambda d: self._pop_run(d))
    def _pop_run(self, d):
        p=d/'lineage.json'; x=json.loads(p.read_text()); x['cases'][0]['runs'].pop(); p.write_text(json.dumps(x))
    def test_pid_mismatch_rejected(self):
        def f(d):
            p=next((d/x/'compiler-receipt.json' for x in [c['caseId'] for c in json.loads((d/'lineage.json').read_text())['cases']])); x=json.loads(p.read_text()); x['compiler']['pgid']+=1; p.write_text(json.dumps(x))
        self.mutated(f)
    def test_source_drift_rejected(self):
        def f(d):
            p=d/'lineage.json'; x=json.loads(p.read_text()); x['cases'][0]['sourceBindings'][0]['sourceAfter']['sha256']='sha256:'+'0'*64; p.write_text(json.dumps(x))
        self.mutated(f)
    def test_tool_drift_rejected(self):
        def f(d):
            cid=json.loads((d/'lineage.json').read_text())['cases'][0]['caseId']; p=d/cid/'compiler-receipt.json'; x=json.loads(p.read_text()); x['compiler']['realToolAfter']['sha256']='sha256:'+'0'*64; p.write_text(json.dumps(x))
        self.mutated(f)
    def test_ax_binary_join_rejected(self):
        def f(d):
            p=d/'ax-compiler-receipt.json'; x=json.loads(p.read_text()); x['compiler']['outputBinary']['sha256']='sha256:'+'0'*64; p.write_text(json.dumps(x))
        self.mutated(f)

if __name__ == '__main__': unittest.main()
