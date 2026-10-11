from __future__ import annotations

import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("archive_resolver", Path(__file__).with_name("archive_resolver.py"))
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def fixture(root: Path, *, mode: str = "chunks", duplicate: bool = False, bool_int: bool = False, symlink: bool = False):
    archive = root / "archive"
    workspace = root / "workspace"
    archive.mkdir()
    workspace.mkdir()
    raw = b"exact archive bytes\n"
    original = "factory/out/raw/example.json"
    descriptor = {"path": original, "sha256": "sha256:" + digest(raw)}
    if mode == "chunks":
        encoded = gzip.compress(raw, compresslevel=9, mtime=0)
        chunk_path = archive / "input-00" / "chunk-0000.json.gz"
        chunk_path.parent.mkdir()
        chunk_path.write_bytes(encoded)
        if symlink:
            target = archive / "target.gz"
            target.write_bytes(encoded)
            chunk_path.unlink()
            chunk_path.symlink_to(target)
        storage = {"chunks": [{"index": 0, "offset": 0, "rawSize": len(raw), "rawSha256": digest(raw), "archivePath": "input-00/chunk-0000.json.gz", "compressedSize": len(encoded), "compressedSha256": digest(encoded), "gzipMtime": 0}]}
    elif mode == "plainPath":
        (archive / "plain.bin").write_bytes(raw)
        storage = {"plainPath": "plain.bin"}
    else:
        encoded = gzip.compress(raw, compresslevel=9, mtime=0)
        (archive / "whole.gz").write_bytes(encoded)
        storage = {"gzipPath": "whole.gz"}
    record = {"ordinal": 0, "originalPath": original, "originalSize": len(raw), "originalSha256": digest(raw), **storage}
    descriptors = [descriptor]
    files = [record]
    if duplicate:
        descriptors.append(descriptor.copy())
        files.append({**record, "ordinal": 1})
    if bool_int:
        files[0]["ordinal"] = True
    manifest = {"captureSources": {}, "chunkSize": resolver.CHUNK_SIZE, "compression": "gzip-level-9-mtime-0", "files": files, "kind": "raw-symbolgraph-lossless-archive", "linkEvidencePath": "link.json", "linkEvidenceSha256": "0" * 64, "rawGraphInputs": descriptors, "version": 1}
    manifest_path = archive / "archive-manifest.json"
    manifest_path.write_text(json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n")
    return archive, workspace, manifest_path, digest(manifest_path.read_bytes()), original, raw


class ArchiveResolverTests(unittest.TestCase):
    def make(self, **kwargs):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        archive, workspace, manifest, pin, original, raw = fixture(root, **kwargs)
        return root, resolver.ArchiveResolver(manifest_path=manifest, expected_manifest_sha256=pin, archive_root=archive, workspace_root=workspace, allow_fixture=True), original, raw

    def test_real_pinned_archive_reads_exact_small_entry(self):
        live = resolver.pinned_resolver()
        path = "factory/out/catalogue/raw/swiftui/SwiftUI@AppKit.symbols.json"
        raw = live.read_bytes(path, force_archive=True)
        self.assertEqual(digest(raw), live.verify(path)["originalSha256"])
        self.assertEqual(len(raw), live.verify(path)["originalSize"])

    def test_force_archive_does_not_consult_live_original_path(self):
        root, reader, original, raw = self.make()
        source = root / "workspace" / original
        source.parent.mkdir(parents=True)
        source.write_bytes(b"corrupt live source")
        self.assertEqual(reader.read_bytes(original, force_archive=True), raw)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "corrupt"):
            reader.read_bytes(original)

    def test_chunked_bytes_are_exact_and_resolve_path_is_explicit(self):
        _, reader, original, raw = self.make()
        self.assertEqual(reader.read_bytes(original, expected_sha256="sha256:" + digest(raw), force_archive=True), raw)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "use read_bytes"):
            reader.resolve_path(original, force_archive=True)

    def test_plain_and_gzip_modes_are_supported(self):
        for mode in ("plainPath", "gzipPath"):
            with self.subTest(mode=mode):
                _, reader, original, raw = self.make(mode=mode)
                self.assertEqual(reader.read_bytes(original, force_archive=True), raw)

    def test_rejects_duplicate_original_mapping(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        archive, workspace, manifest, pin, *_ = fixture(root, duplicate=True)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "duplicate original"):
            resolver.ArchiveResolver(manifest_path=manifest, expected_manifest_sha256=pin, archive_root=archive, workspace_root=workspace, allow_fixture=True)

    def test_rejects_boolean_integer(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        archive, workspace, manifest, pin, *_ = fixture(root, bool_int=True)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "strict integer"):
            resolver.ArchiveResolver(manifest_path=manifest, expected_manifest_sha256=pin, archive_root=archive, workspace_root=workspace, allow_fixture=True)

    def test_rejects_path_escape_and_symlink_archive_bytes(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        archive, workspace, manifest, pin, original, _ = fixture(root, symlink=True)
        reader = resolver.ArchiveResolver(manifest_path=manifest, expected_manifest_sha256=pin, archive_root=archive, workspace_root=workspace, allow_fixture=True)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "symlink"):
            reader.read_bytes(original, force_archive=True)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "escapes"):
            reader.verify("../escape.json")

    def test_rejects_corrupt_compressed_bytes(self):
        root, reader, original, _ = self.make()
        chunk = root / "archive/input-00/chunk-0000.json.gz"
        chunk.write_bytes(chunk.read_bytes()[:-1] + b"x")
        with self.assertRaises(resolver.ArchiveResolverError):
            reader.read_bytes(original, force_archive=True)


if __name__ == "__main__":
    unittest.main()
