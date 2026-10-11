#!/usr/bin/env python3
from __future__ import annotations
import hashlib
import importlib.util
import json
import tempfile
import unittest
import sys
from pathlib import Path

ROOT = Path(__file__).parent
sys.path.insert(0, str(ROOT.parents[3]))

def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

receipt_validator = load('seed_origin_v3_receipt_test', ROOT / 'collector/verify_receipt.py')
positive_validator = load('seed_origin_v3_positive_test', ROOT / 'verify_positive_control.py')

class V3(unittest.TestCase):
    def test_exact_seed_input_pins(self):
        pins = json.loads((ROOT / 'input-pins.json').read_text())
        self.assertEqual(pins['seed'], 14577611000270672472)
        self.assertEqual(len(pins['rows']), 5)
        for row in pins['rows']:
            source = ROOT / row['source']['path']
            self.assertEqual('sha256:' + sha(source), row['source']['sha256'])

    def test_collector_copy_is_byte_exact(self):
        pins = json.loads((ROOT / 'collector-v2-pins.json').read_text())
        self.assertEqual(pins['kind'], 'v2-collector-pins')
        for row in pins['files']:
            path = ROOT / row['path']
            self.assertEqual(row['sha256'], 'sha256:' + sha(path))
            self.assertEqual(row['bytes'], path.stat().st_size)

    def test_positive_fixture_has_main_and_two_files(self):
        source = ROOT / 'positive-control/source'
        names = sorted(path.name for path in source.iterdir())
        self.assertEqual(names, ['CaptureHost.swift', 'Witness.swift'])
        self.assertIn('@main', (source / 'CaptureHost.swift').read_text())
        self.assertNotIn('@main', (source / 'Witness.swift').read_text())
        summary = json.loads((ROOT / 'positive-control/control-summary.json').read_text())
        self.assertEqual(summary['status'], 'POSITIVE')
        self.assertEqual(summary['attempts'], 1)
        self.assertFalse(summary['captureRun'])
        self.assertFalse(summary['seedCaptureRun'])

    def test_symlink_logical_path_control(self):
        collector = load('seed_origin_v3_collector_test', ROOT / 'collector/capture_origin.py')
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            real = root / 'swiftc-real'
            logical = root / 'swiftc-logical'
            real.write_bytes(b'tool')
            logical.symlink_to(real)
            logical_path, real_path = collector.logical_and_real(str(logical))
            self.assertEqual(str(logical_path), str(logical))
            self.assertEqual(real_path, real)
            self.assertNotEqual(str(logical_path), str(real_path))

    def test_positive_archive_verifies(self):
        result = positive_validator.validate(ROOT)
        self.assertEqual(result['status'], 'PASS')
        self.assertEqual(result['compilerExit'], 0)
        self.assertFalse(result['sourceDrift'])
        self.assertFalse(result['timedOut'])

    def test_receipt_faults_reject_source_and_timeout(self):
        receipt_path = ROOT / 'positive-control/evidence/compiler-receipt.json'
        original = json.loads(receipt_path.read_text())
        with tempfile.TemporaryDirectory() as directory:
            bad_source = Path(directory) / 'source.json'
            changed = json.loads(json.dumps(original))
            changed['sourceAfter']['Witness.swift']['sha256'] = 'sha256:' + '0' * 64
            bad_source.write_text(json.dumps(changed))
            with self.assertRaises(Exception):
                receipt_validator.validate(bad_source)
            bad_timeout = Path(directory) / 'timeout.json'
            changed = json.loads(json.dumps(original))
            changed['compiler']['timedOut'] = True
            bad_timeout.write_text(json.dumps(changed))
            with self.assertRaises(Exception):
                receipt_validator.validate(bad_timeout)

if __name__ == '__main__':
    unittest.main()
