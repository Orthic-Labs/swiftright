"""Opt-in reader config & CLI forwarding tests; no native archive execution."""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from factory.pipeline.__main__ import main
from factory.pipeline.archive_reader import ArchiveByteReader
from factory.pipeline.reader_config import load_origin_reader_config


class ReaderConfigTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        (self.base / 'mac').mkdir()
        (self.base / 'windows').mkdir()
        (self.base / 'mac' / 'tool').write_bytes(b'tool bytes')
        self.config = self.base / 'origin-reader.json'

    def write_config(self, **overrides):
        value = {'version': 1, 'macRoots': ['mac'], 'windowsArchives': {}, 'macPathMap': {}}
        value.update(overrides)
        self.config.write_text(json.dumps(value), encoding='utf-8')
        return self.config

    def test_load_resolves_config_relative_roots(self):
        reader = load_origin_reader_config(self.write_config())
        self.assertIsInstance(reader, ArchiveByteReader)
        raw = b'tool bytes'
        reference = {'path': str(self.base / 'mac' / 'tool'),
                     'sha256': 'sha256:' + __import__('hashlib').sha256(raw).hexdigest(),
                     'bytes': len(raw)}
        self.assertEqual(reader(capture={'platform': 'macos'}, reference=reference), raw)

    def test_rejects_wrong_shape_version_absolute_and_unknown_paths(self):
        bad_values = [
            {'version': True, 'macRoots': ['mac'], 'windowsArchives': {}, 'macPathMap': {}},
            {'version': 1, 'macRoots': ['/tmp'], 'windowsArchives': {}, 'macPathMap': {}},
            {'version': 1, 'macRoots': ['missing'], 'windowsArchives': {}, 'macPathMap': {}},
            {'version': 1, 'macRoots': ['mac'], 'windowsArchives': {}, 'macPathMap': {}, 'extra': 1},
            {'version': 1, 'macRoots': [], 'windowsArchives': {}, 'macPathMap': {}},
        ]
        for value in bad_values:
            with self.subTest(value=value):
                with self.assertRaises(ValueError):
                    load_origin_reader_config(self.write_config(**value))

    def test_duplicate_json_keys_rejected(self):
        self.config.write_text('{"version":1,"version":1,"macRoots":["mac"],"windowsArchives":{},"macPathMap":{}}', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'duplicate'):
            load_origin_reader_config(self.config)

    def test_windows_mapping_requires_exact_capture_hash_and_relative_directory(self):
        key = 'a' * 64
        reader = load_origin_reader_config(self.write_config(
            macRoots=[], windowsArchives={key: 'windows'}))
        self.assertIsInstance(reader, ArchiveByteReader)
        for mapping in ({'sha256:' + key: 'windows'}, {'A' * 64: 'windows'}, {key: '../outside'}):
            with self.subTest(mapping=mapping):
                with self.assertRaises(ValueError):
                    load_origin_reader_config(self.write_config(macRoots=[], windowsArchives=mapping))

    def test_gate_cli_passes_explicit_reader_and_default_none(self):
        cfg = self.write_config()
        seen = []
        def fake_gate(*args, **kwargs):
            seen.append(kwargs.get('origin_reader'))
            return {'status': 'blocked'}
        args = ['gate', '--output', str(self.base / 'out'), '--evidence-root', str(self.base),
                '--origin-reader-config', str(cfg)]
        with patch('factory.pipeline.__main__.gate', side_effect=fake_gate), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(args), 3)
        self.assertIsInstance(seen[-1], ArchiveByteReader)
        with patch('factory.pipeline.__main__.gate', side_effect=fake_gate), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(args[:-2]), 3)
        self.assertIsNone(seen[-1])

    def test_gate_evidence_cli_passes_explicit_reader_and_default_none(self):
        cfg = self.write_config()
        seen = []
        def fake_gate_evidence(*args, **kwargs):
            seen.append(kwargs.get('origin_reader'))
            return {'status': 'blocked'}
        args = ['gate-evidence', '--output', str(self.base / 'out-evidence'),
                '--plan', str(self.base / 'plan.json'), '--evidence-root', str(self.base),
                '--origin-reader-config', str(cfg)]
        with patch('factory.pipeline.__main__.gate_evidence', side_effect=fake_gate_evidence), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(args), 3)
        self.assertIsInstance(seen[-1], ArchiveByteReader)
        with patch('factory.pipeline.__main__.gate_evidence', side_effect=fake_gate_evidence), contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(args[:-2]), 3)
        self.assertIsNone(seen[-1])


if __name__ == '__main__':
    unittest.main()
