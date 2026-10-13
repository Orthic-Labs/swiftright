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


def fixture(root: Path, *, mode: str = "none", duplicate: bool = False,
            bool_int: bool = False, symlink: bool = False):
    archive = root / "archive"
    archive.mkdir()
    original = str(root / "SDK" / "Header.h")
    raw = b"exact external bytes\n"
    if mode == "gzip":
        encoded = gzip.compress(raw, compresslevel=9, mtime=0)
        path = archive / "payload.bin.gz"
        path.write_bytes(encoded)
        storage = {"bytes": len(encoded), "compression": "gzip", "path": "payload.bin.gz", "sha256": digest(encoded), "decompressedBytes": len(raw), "decompressedSha256": digest(raw)}
    else:
        path = archive / "payload.bin"
        path.write_bytes(raw)
        if symlink:
            target = archive / "target.bin"
            target.write_bytes(raw)
            path.unlink()
            path.symlink_to(target)
        storage = {"bytes": len(raw), "compression": "none", "path": "payload.bin", "sha256": digest(raw)}
    entry = {"archive": storage, "bytes": True if bool_int else len(raw), "kind": "file", "observedLive": {"bytes": len(raw), "sha256": digest(raw)}, "provenance": [], "roles": [], "semanticPath": original, "sha256": digest(raw)}
    entries = [entry]
    if duplicate:
        entries.append(dict(entry))
    manifest = {"directoryPrerequisites": [], "entries": entries, "policy": {"archivePathsRepositoryRelative": True}, "schema": "factory.public-ancestor.archive-input-mapping.v1", "sourceScope": {}, "status": "frozen-inputs-only"}
    manifest_path = archive / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n")
    return archive, manifest_path, digest(manifest_path.read_bytes()), original, raw


class ArchiveResolverTests(unittest.TestCase):
    def make(self, **kwargs):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        archive, manifest, pin, original, raw = fixture(root, **kwargs)
        return root, resolver.ArchiveResolver(manifest_path=manifest, expected_manifest_sha256=pin, archive_root=archive, allow_fixture=True), original, raw

    def test_real_pinned_absolute_source_and_gzip_inputs(self):
        reader = resolver.pinned_resolver()
        header = "/Applications/Xcode-27-RC.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/AppKit.framework/Versions/C/Headers/AppKit.h"
        self.assertEqual(digest(reader.read_bytes(header, force_archive=True)), reader.verify(header)["sha256"])
        clang = "/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
        self.assertEqual(digest(reader.read_bytes(clang, force_archive=True)), reader.verify(clang)["sha256"])

    def test_approved_v2_manifest_reads_additive_input(self):
        reader = resolver.ArchiveResolver(manifest_path=resolver.V2_MANIFEST_PATH, expected_manifest_sha256=resolver.V2_MANIFEST_SHA256)
        entry = reader.manifest["entries"][0]
        self.assertEqual(digest(reader.read_bytes(entry["semanticPath"], force_archive=True)), entry["sha256"])

    def test_verify_result_is_defensive_copy(self):
        _, reader, original, raw = self.make()
        result = reader.verify(original)
        result["bytes"] = 1
        result["archive"]["path"] = "changed"
        reader.manifest["entries"][0]["bytes"] = 1
        self.assertEqual(reader.verify(original)["bytes"], len(raw))
        self.assertEqual(reader.read_bytes(original, force_archive=True), raw)

    def test_force_archive_never_reads_corrupt_original(self):
        root, reader, original, raw = self.make()
        source = Path(original)
        source.parent.mkdir(parents=True)
        source.write_bytes(b"corrupt live source")
        self.assertEqual(reader.read_bytes(original, force_archive=True), raw)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "corrupt"):
            reader.read_bytes(original)

    def test_expected_hash_size_exact_path_and_plain_resolution(self):
        _, reader, original, raw = self.make()
        self.assertEqual(reader.read_bytes(original, expected_sha256="sha256:" + digest(raw), expected_size=len(raw), force_archive=True), raw)
        self.assertEqual(reader.resolve_path(original, force_archive=True).read_bytes(), raw)
        with self.assertRaises(resolver.ArchiveResolverError):
            reader.verify(original + "/alias")
        with self.assertRaises(resolver.ArchiveResolverError):
            reader.verify(original, expected_size=True)

    def test_compressed_resolution_requires_bytes_api(self):
        _, reader, original, raw = self.make(mode="gzip")
        self.assertEqual(reader.read_bytes(original, force_archive=True), raw)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "use read_bytes"):
            reader.resolve_path(original, force_archive=True)

    def test_rejects_duplicate_original_mapping(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        archive, manifest, pin, *_ = fixture(root, duplicate=True)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "duplicate original"):
            resolver.ArchiveResolver(manifest_path=manifest, expected_manifest_sha256=pin, archive_root=archive, allow_fixture=True)

    def test_rejects_observed_live_mismatch(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        archive, manifest, _, *_ = fixture(root)
        data = json.loads(manifest.read_text())
        data["entries"][0]["observedLive"]["bytes"] += 1
        manifest.write_text(json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n")
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "observedLive size"):
            resolver.ArchiveResolver(manifest_path=manifest, expected_manifest_sha256=digest(manifest.read_bytes()), archive_root=archive, allow_fixture=True)

    def test_rejects_boolean_integer(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        archive, manifest, pin, *_ = fixture(root, bool_int=True)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "strict integer"):
            resolver.ArchiveResolver(manifest_path=manifest, expected_manifest_sha256=pin, archive_root=archive, allow_fixture=True)

    def test_rejects_truthy_control_flags(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        archive, manifest, pin, original, _ = fixture(root)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "allow_fixture must be bool"):
            resolver.ArchiveResolver(manifest_path=manifest, expected_manifest_sha256=pin, archive_root=archive, allow_fixture=1)
        reader = resolver.ArchiveResolver(manifest_path=manifest, expected_manifest_sha256=pin, archive_root=archive, allow_fixture=True)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "force_archive must be bool"):
            reader.read_bytes(original, force_archive=1)

    def test_rejects_manifest_parent_symlink(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        archive, manifest, pin, *_ = fixture(root)
        real = root / "real"
        real.mkdir()
        copied = real / "manifest.json"
        copied.write_bytes(manifest.read_bytes())
        link = root / "link"
        link.symlink_to(real, target_is_directory=True)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "manifest parent is symlink"):
            resolver.ArchiveResolver(manifest_path=link / "manifest.json", expected_manifest_sha256=pin, archive_root=archive, allow_fixture=True)

    def test_rejects_archive_symlink_and_path_escape(self):
        root = Path(tempfile.mkdtemp())
        self.addCleanup(shutil.rmtree, root)
        archive, manifest, pin, original, _ = fixture(root, symlink=True)
        reader = resolver.ArchiveResolver(manifest_path=manifest, expected_manifest_sha256=pin, archive_root=archive, allow_fixture=True)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "symlink"):
            reader.read_bytes(original, force_archive=True)
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "not archived"):
            reader.verify("/../escape")

    def test_rejects_corrupt_archive_bytes(self):
        root, reader, original, _ = self.make()
        path = root / "archive/payload.bin"
        path.write_bytes(b"changed")
        with self.assertRaisesRegex(resolver.ArchiveResolverError, "corrupt"):
            reader.read_bytes(original, force_archive=True)


if __name__ == "__main__":
    unittest.main()
