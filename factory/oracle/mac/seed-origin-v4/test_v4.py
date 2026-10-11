#!/usr/bin/env python3
from __future__ import annotations
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT.parents[3]))

def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod

def sha(path: Path) -> str: return hashlib.sha256(path.read_bytes()).hexdigest()

collector = load('seed_origin_v4_collector_test', ROOT / 'capture_origin.py')
receipt_validator = load('seed_origin_v4_receipt_test', ROOT / 'verify_receipt.py')
positive_validator = load('seed_origin_v4_positive_test', ROOT / 'verify_positive_control.py')
timeout_validator = load('seed_origin_v4_timeout_test', ROOT / 'verify_timeout_control.py')

class V4(unittest.TestCase):
    def test_inputs_and_v3_lineage(self):
        pins=json.loads((ROOT/'input-pins.json').read_text()); self.assertEqual(pins['seed'],14577611000270672472); self.assertEqual(len(pins['rows']),5)
        for row in pins['rows']: self.assertEqual('sha256:'+sha(ROOT/row['source']['path']),row['source']['sha256'])
        lineage=json.loads((ROOT/'v3-lineage.json').read_text()); self.assertEqual(lineage['v3StageManifestSha256'],'d791a795f11dd0f1558177e96cb74f81bc2a435f7ce371f87a3f76ce5b38e503')

    def test_marker_root_and_symlink_binding(self):
        self.assertEqual(collector.REPO, ROOT.parents[3])
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); real=root/'swiftc-real'; logical=root/'swiftc-logical'; real.write_bytes(b'tool'); logical.symlink_to(real)
            logical_path, real_path=collector.logical_and_real(str(logical)); self.assertEqual(str(logical_path),str(logical)); self.assertEqual(real_path,real); self.assertNotEqual(logical_path,real_path)

    def test_runner_is_replayable_from_known_root(self):
        runner=(ROOT/'positive-control/run-control.py').read_text()
        self.assertIn('SWIFTRIGHT_REPO_ROOT',runner); self.assertIn('factory/core/artifacts.py',runner); self.assertIn('seed-origin-v4/capture_origin.py',runner); self.assertNotIn('seed-origin-v3/capture_origin.py',runner)

    def test_positive_and_timeout_receipts(self):
        self.assertEqual(positive_validator.validate(ROOT)['status'],'PASS')
        timeout=timeout_validator.validate(ROOT); self.assertEqual(timeout['status'],'PASS'); self.assertTrue(timeout['initialTimeoutRecorded'])

    def test_receipt_fault_controls(self):
        original=json.loads((ROOT/'positive-control/evidence/compiler-receipt.json').read_text())
        with tempfile.TemporaryDirectory() as directory:
            changed=json.loads(json.dumps(original)); changed['sourceAfter']['Witness.swift']['sha256']='sha256:'+'0'*64; p=Path(directory)/'source.json'; p.write_text(json.dumps(changed))
            with self.assertRaises(Exception): receipt_validator.validate(p)
            changed=json.loads(json.dumps(original)); changed['compiler']['timedOut']=True; p=Path(directory)/'timeout.json'; p.write_text(json.dumps(changed))
            with self.assertRaises(Exception): receipt_validator.validate(p)

    def test_timeout_propagation_is_explicit(self):
        source=(ROOT/'capture_origin.py').read_text()
        self.assertIn("cleanup['timedOut'] = True",source)
        self.assertIn("compiler_receipt['cleanup'].get('timedOut')",source); self.assertIn("compiler_receipt['cleanup'].get('drainTimedOut')",source)
        self.assertIn("_repo_root()",source)

if __name__ == '__main__': unittest.main()
