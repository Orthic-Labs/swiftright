"""Constrained archive reader tests use invented guard fixtures only."""
import hashlib
import tempfile
import unittest
from pathlib import Path

from factory.core.artifacts import canonical_hash
from factory.gate.mac_origin_admission import mac_origin_admission_issues
from factory.gate.test_mac_origin_admission import OriginFixture
from factory.gate.test_windows_exit_admission import Fixture as WindowsFixture
from factory.gate.windows_exit_admission import verify_windows_exit_admission
from factory.pipeline.archive_reader import ArchiveByteReader, ArchiveReadError


def digest(raw):
    return "sha256:" + hashlib.sha256(raw).hexdigest()


class ArchiveReaderTests(unittest.TestCase):
    def setUp(self):
        scratch_root = Path(__file__).resolve().parents[2] / '.factory-work' / 'archive-reader-tests'
        scratch_root.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch_root)
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)

    def _windows_archive(self):
        fixture = WindowsFixture()
        root = self.base / 'windows-capture'
        root.mkdir()
        for role, raw in fixture.raw.items():
            (root / (role + '.raw')).write_bytes(raw)
        for relative, raw in fixture.host.items():
            path = root / 'host' / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        for relative, raw in fixture.runtime.items():
            path = root / 'runtime' / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(raw)
        compiler = root / 'tool' / 'compiler.bin'
        compiler.parent.mkdir()
        compiler.write_bytes(fixture.compiler)
        reader = ArchiveByteReader(windows_archives={canonical_hash(fixture.capture).removeprefix('sha256:'): root})
        return fixture, root, reader

    def test_mac_guard_reads_only_bound_archive_bytes(self):
        root = self.base / 'mac-capture'
        root.mkdir()
        fixture = OriginFixture(root)
        reader = ArchiveByteReader(mac_roots=[root], mac_path_map={
            '/usr/bin/xcrun': root / 'bin/xcrun'})
        callback = lambda reference: reader(capture=fixture.capture, reference=reference)
        self.assertEqual([], mac_origin_admission_issues(fixture.capture, callback))

    def test_mac_rejects_unadmitted_path_hash_size_and_symlink_escape(self):
        root = self.base / 'mac-root'
        root.mkdir()
        file = root / 'artifact.bin'
        file.write_bytes(b'pinned')
        reader = ArchiveByteReader(mac_roots=[root])
        ref = {'path': str(file), 'sha256': digest(b'pinned'), 'bytes': 6}
        self.assertEqual(reader(capture={'platform': 'macos'}, reference=ref), b'pinned')
        for bad_ref in (
            {**ref, 'sha256': digest(b'forged')},
            {**ref, 'bytes': True},
            {**ref, 'path': str(self.base / 'outside.bin')},
            {**ref, 'path': str(root / '..' / 'outside.bin')},
        ):
            with self.subTest(reference=bad_ref), self.assertRaises(ArchiveReadError):
                reader(capture={'platform': 'macos'}, reference=bad_ref)
        outside = self.base / 'outside.bin'
        outside.write_bytes(b'outside')
        link = root / 'link.bin'
        link.symlink_to(outside)
        with self.assertRaises(ArchiveReadError):
            reader(capture={'platform': 'macos'}, reference={
                'path': str(link), 'sha256': digest(b'outside')})

    def test_windows_guard_reads_proof_host_runtime_and_compiler_files(self):
        fixture, _root, reader = self._windows_archive()
        result = verify_windows_exit_admission(fixture.capture,
            read_bytes=lambda reference: reader(capture=fixture.capture, reference=reference))
        self.assertEqual(result['issues'], [])
        self.assertFalse(result['nativeParityGranted'])

    def test_windows_requires_exact_capture_binding_and_rejects_unknown_refs(self):
        fixture, _root, reader = self._windows_archive()
        changed = dict(fixture.capture)
        changed['id'] = 'changed-capture'
        with self.assertRaisesRegex(ArchiveReadError, 'no explicitly admitted'):
            reader(capture=changed, reference='outcome.raw')
        with self.assertRaisesRegex(ArchiveReadError, 'not bound'):
            reader(capture=fixture.capture, reference='unlisted.raw')
        with self.assertRaisesRegex(ArchiveReadError, 'unsafe archive-relative'):
            reader(capture=fixture.capture, reference='../outcome.raw')
        with self.assertRaisesRegex(ArchiveReadError, 'unsafe archive-relative'):
            reader(capture=fixture.capture, reference='outcome\x00.raw')

    def test_windows_rejects_tampered_bound_hash_and_symlink(self):
        fixture, root, reader = self._windows_archive()
        original = fixture.raw['outcome']
        (root / 'outcome.raw').write_bytes(original + b'changed')
        with self.assertRaisesRegex(ArchiveReadError, 'bytes differ'):
            reader(capture=fixture.capture, reference='outcome.raw')
        (root / 'outcome.raw').unlink()
        outside = self.base / 'outside.raw'
        outside.write_bytes(original)
        (root / 'outcome.raw').symlink_to(outside)
        with self.assertRaises(ArchiveReadError):
            reader(capture=fixture.capture, reference='outcome.raw')


if __name__ == '__main__':
    unittest.main()
