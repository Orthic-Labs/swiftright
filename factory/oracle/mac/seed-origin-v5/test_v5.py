#!/usr/bin/env python3
from __future__ import annotations
import hashlib
import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path
ROOT=Path(__file__).parent
sys.path.insert(0,str(ROOT.parents[3]))
def load(name,path):
 spec=importlib.util.spec_from_file_location(name,path); assert spec and spec.loader; mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
collector=load('seed_origin_v5_collector_test',ROOT/'capture_origin.py')
receipt_validator=load('seed_origin_v5_receipt_test',ROOT/'verify_receipt.py')
positive_validator=load('seed_origin_v5_positive_test',ROOT/'verify_positive_control.py')
timeout_validator=load('seed_origin_v5_timeout_test',ROOT/'verify_timeout_control.py')
dependency_validator=load('seed_origin_v5_dependency_test',ROOT/'verify_dependency_closure.py')
class V5(unittest.TestCase):
 def test_input_pins_and_siblings(self):
  pins=json.loads((ROOT/'input-pins.json').read_text()); self.assertEqual(pins['seed'],14577611000270672472); self.assertEqual(len(pins['rows']),5)
  for row in pins['rows']: self.assertEqual('sha256:'+sha(ROOT/row['source']['path']),row['source']['sha256'])
  for name in ['AXClient.swift','CaptureHost.swift']: self.assertEqual(sha(ROOT/name),sha(ROOT.parents[3]/'factory/oracle/mac/seed-origin-v2'/name))
 def test_dependency_closure(self): self.assertEqual(dependency_validator.validate(ROOT,ROOT.parents[3])['status'],'PASS')
 def test_marker_root_and_symlink(self):
  self.assertEqual(collector.REPO,ROOT.parents[3])
  with tempfile.TemporaryDirectory() as directory:
   root=Path(directory); real=root/'swiftc-real'; logical=root/'swiftc-logical'; real.write_bytes(b'tool'); logical.symlink_to(real); lp,rp=collector.logical_and_real(str(logical)); self.assertEqual(str(lp),str(logical)); self.assertEqual(rp,real); self.assertNotEqual(lp,rp)
 def test_runner_and_source_join(self):
  runner=(ROOT/'positive-control/run-control.py').read_text(); self.assertIn('SWIFTRIGHT_REPO_ROOT',runner); self.assertIn('factory/core/artifacts.py',runner); self.assertIn('seed-origin-v5/capture_origin.py',runner); self.assertNotIn('seed-origin-v4/capture_origin.py',runner)
  result=positive_validator.validate(ROOT); self.assertEqual(result['status'],'PASS'); self.assertEqual(result['sourceBindings'],2)
 def test_timeout(self): self.assertEqual(timeout_validator.validate(ROOT)['status'],'PASS')
 def test_fault_controls(self):
  original=json.loads((ROOT/'positive-control/evidence/compiler-receipt.json').read_text())
  with tempfile.TemporaryDirectory() as directory:
   changed=json.loads(json.dumps(original)); changed['sourceAfter']['Witness.swift']['sha256']='sha256:'+'0'*64; p=Path(directory)/'source.json'; p.write_text(json.dumps(changed));
   with self.assertRaises(Exception): receipt_validator.validate(p)
   changed=json.loads(json.dumps(original)); changed['compiler']['timedOut']=True; p=Path(directory)/'timeout.json'; p.write_text(json.dumps(changed));
   with self.assertRaises(Exception): receipt_validator.validate(p)
 def test_timeout_propagation(self):
  source=(ROOT/'capture_origin.py').read_text(); self.assertIn("cleanup['timedOut'] = True",source); self.assertIn("compiler_receipt['cleanup'].get('timedOut')",source); self.assertIn('_repo_root()',source)
if __name__=='__main__': unittest.main()
