#!/usr/bin/env python3
import json, tempfile, unittest
from pathlib import Path
import verify

ROOT=Path(__file__).parent
class Controls(unittest.TestCase):
    def test_positive_packet(self):
        self.assertEqual(verify.validate(ROOT)['status'],'PASS')
    def test_changed_source_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            dst=Path(t); import shutil; shutil.copytree(ROOT,dst/'packet',dirs_exist_ok=True); p=dst/'packet'/'inputs'/'swiftui.custom-layout.recipe.gate-seeded.ca4e13f820f5d258.swift'; p.write_bytes(p.read_bytes()+b'\n')
            with self.assertRaises(ValueError): verify.validate(dst/'packet')
    def test_missing_run_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            dst=Path(t); import shutil; shutil.copytree(ROOT,dst/'packet',dirs_exist_ok=True); p=dst/'packet'/'evidence'/'swiftui.preference-key.recipe.gate-seeded.ca4e13f820f5d258'/'summary.json'; d=json.loads(p.read_text()); d['runs']=d['runs'][:-1]; p.write_text(json.dumps(d))
            with self.assertRaises(ValueError): verify.validate(dst/'packet')
    def test_duplicate_run_rejected(self):
        with tempfile.TemporaryDirectory() as t:
            dst=Path(t); import shutil; shutil.copytree(ROOT,dst/'packet',dirs_exist_ok=True); p=dst/'packet'/'evidence'/'swiftui.stack-overlay.recipe.gate-seeded.ca4e13f820f5d258'/'summary.json'; d=json.loads(p.read_text()); d['runs'][-1]['run']=1; p.write_text(json.dumps(d))
            with self.assertRaises(ValueError): verify.validate(dst/'packet')
if __name__=='__main__': unittest.main()
