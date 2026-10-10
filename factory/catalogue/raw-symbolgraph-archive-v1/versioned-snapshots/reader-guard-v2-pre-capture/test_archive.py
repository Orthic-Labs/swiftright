from __future__ import annotations

import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("raw_symbolgraph_archive", Path(__file__).with_name("archive.py"))
archive = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = archive
spec.loader.exec_module(archive)


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def tiny_archive(root: Path) -> tuple[Path, Path, str, bytes]:
    archive_dir = root / "archive"
    archive_dir.mkdir(parents=True)
    source = b'{"symbols":[{"precise":"s:test"}]}\n'
    link = {"kind": "sourcekit-interface-index-link-spike", "rawGraphInputs": [
        {"path": "factory/out/raw/one.json", "sha256": "sha256:" + digest(source)},
        {"path": "factory/out/raw/two.json", "sha256": "sha256:" + digest(source[::-1])},
    ]}
    link_path = root / "link-evidence.json"
    link_raw = json.dumps(link, sort_keys=True, separators=(",", ":")).encode()
    link_path.write_bytes(link_raw)
    compressed_files = []
    file_records = []
    for ordinal, descriptor in enumerate(link["rawGraphInputs"]):
        raw = source if ordinal == 0 else source[::-1]
        compressed = gzip.compress(raw, compresslevel=9, mtime=0)
        rel = f"input-{ordinal:02d}/chunk-0000.json.gz"
        out = archive_dir / rel
        out.parent.mkdir(parents=True)
        out.write_bytes(compressed)
        compressed_files.append(out)
        file_records.append({
            "ordinal": ordinal,
            "originalPath": descriptor["path"],
            "originalSize": len(raw),
            "originalSha256": digest(raw),
            "chunks": [{
                "index": 0, "offset": 0, "rawSize": len(raw), "rawSha256": digest(raw),
                "archivePath": rel, "compressedSize": len(compressed),
                "compressedSha256": digest(compressed), "gzipMtime": 0,
            }],
        })
    source_pins = {}
    for name in ("archive.py", "test_archive.py", "README.md"):
        source_path = Path(__file__).with_name(name)
        shutil.copyfile(source_path, archive_dir / name)
        source_pins[name] = digest(source_path.read_bytes())
    manifest = {
        "kind": "raw-symbolgraph-lossless-archive", "version": 1,
        "chunkSize": archive.CHUNK_SIZE, "compression": "gzip-level-9-mtime-0",
        "captureSources": source_pins,
        "linkEvidencePath": "link-evidence.json", "linkEvidenceSha256": digest(link_raw),
        "rawGraphInputs": link["rawGraphInputs"], "files": file_records,
    }
    manifest_path = archive_dir / "archive-manifest.json"
    manifest_raw = (json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n").encode()
    manifest_path.write_bytes(manifest_raw)
    return manifest_path, link_path, digest(manifest_raw), source


class ArchiveTests(unittest.TestCase):
    def test_capture_is_lossless_and_binds_source_code_versions(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            workspace = root / "workspace"
            archive_dir = root / "archive"
            descriptors = []
            expected = {}
            for index in range(11):
                rel = f"factory/out/raw/graph-{index}.json"
                raw = f'{{"index":{index}}}\n'.encode()
                path = workspace / rel
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(raw)
                descriptors.append({"path": rel, "sha256": "sha256:" + digest(raw)})
                expected[rel] = raw
            link = {"kind": "sourcekit-interface-index-link-spike", "rawGraphInputs": descriptors}
            link_path = workspace / "link-evidence.json"
            link_raw = json.dumps(link, sort_keys=True, separators=(",", ":")).encode()
            link_path.write_bytes(link_raw)
            archive_dir.mkdir(parents=True)
            for name in ("archive.py", "test_archive.py", "README.md"):
                shutil.copyfile(Path(__file__).with_name(name), archive_dir / name)
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link_raw)):
                manifest = archive.capture_archive(link_path=link_path, workspace_root=workspace,
                                                   output_dir=archive_dir)
                manifest_path = archive_dir / "archive-manifest.json"
                manifest_hash = digest(manifest_path.read_bytes())
                recovered = archive.load_archive(manifest_path, expected_manifest_sha256=manifest_hash,
                    link_path=link_path, workspace_root=workspace, scratch_root=root / "scratch")
            self.assertEqual(manifest["rawGraphInputs"], descriptors)
            self.assertEqual(manifest["captureSources"]["archive.py"], digest((archive_dir / "archive.py").read_bytes()))
            self.assertEqual({key: path.read_bytes() for key, path in recovered.items()}, expected)

    def test_round_trip_preserves_exact_bytes_and_descriptor_order(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, link, pin, expected = tiny_archive(root)
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link.read_bytes())):
                recovered = archive.load_archive(manifest, expected_manifest_sha256=pin,
                    link_path=link, workspace_root=root / "workspace", scratch_root=root / "scratch")
            self.assertEqual(list(recovered), [
                "factory/out/raw/one.json", "factory/out/raw/two.json",
            ])
            self.assertEqual(recovered["factory/out/raw/one.json"].read_bytes(), expected)
            self.assertEqual(recovered["factory/out/raw/two.json"].read_bytes(), expected[::-1])

    def test_rejects_manifest_pin_mismatch_before_reconstruction(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, link, pin, _ = tiny_archive(root)
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link.read_bytes())):
                with self.assertRaisesRegex(archive.ArchiveError, "trusted manifest pin"):
                    archive.load_archive(manifest, expected_manifest_sha256="0" * 64,
                        link_path=link, workspace_root=root / "workspace", scratch_root=root / "scratch")

    def test_rejects_capture_source_pin_drift(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, link, _, _ = tiny_archive(root)
            data = json.loads(manifest.read_text())
            data["captureSources"]["archive.py"] = "0" * 64
            raw = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
            manifest.write_bytes(raw)
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link.read_bytes())):
                with self.assertRaisesRegex(archive.ArchiveError, "capture source bytes changed: archive.py"):
                    archive.load_archive(manifest, expected_manifest_sha256=digest(raw),
                        link_path=link, workspace_root=root / "workspace", scratch_root=root / "scratch")

    def test_rejects_workspace_archive_and_symlink_scratch_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, link, pin, _ = tiny_archive(root)
            workspace = root / "workspace"
            workspace.mkdir()
            (workspace / "cache").mkdir()
            symlink = root / "scratch-link"
            symlink.symlink_to(workspace, target_is_directory=True)
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link.read_bytes())):
                with self.assertRaisesRegex(archive.ArchiveError, "disjoint from workspace"):
                    archive.load_archive(manifest, expected_manifest_sha256=pin,
                        link_path=link, workspace_root=workspace, scratch_root=workspace / "cache")
                with self.assertRaisesRegex(archive.ArchiveError, "disjoint from archive folder"):
                    archive.load_archive(manifest, expected_manifest_sha256=pin,
                        link_path=link, workspace_root=workspace, scratch_root=manifest.parent / "cache")
                with self.assertRaisesRegex(archive.ArchiveError, "disjoint from workspace"):
                    archive.load_archive(manifest, expected_manifest_sha256=pin,
                        link_path=link, workspace_root=workspace, scratch_root=symlink / "cache")

    def test_rejects_boolean_version_ordinal_index_and_offset(self):
        cases = [
            ("version", lambda data: data.__setitem__("version", True), "unsupported archive manifest"),
            ("ordinal", lambda data: data["files"][0].__setitem__("ordinal", True), "input order or ordinal"),
            ("index", lambda data: data["files"][0]["chunks"][0].__setitem__("index", True), "chunk order/index"),
            ("offset", lambda data: data["files"][0]["chunks"][0].__setitem__("offset", True), "chunk offset"),
        ]
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for label, mutate, message in cases:
                with self.subTest(field=label):
                    case_root = root / label
                    case_root.mkdir()
                    manifest, link, _, _ = tiny_archive(case_root)
                    data = json.loads(manifest.read_text())
                    mutate(data)
                    raw = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
                    manifest.write_bytes(raw)
                    with patch.object(archive, "PINNED_LINK_SHA256", digest(link.read_bytes())):
                        with self.assertRaisesRegex(archive.ArchiveError, message):
                            archive.load_archive(manifest, expected_manifest_sha256=digest(raw),
                                link_path=link, workspace_root=case_root / "workspace",
                                scratch_root=case_root / "scratch")

    def test_rejects_link_descriptor_mutation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, link, pin, _ = tiny_archive(root)
            changed = json.loads(link.read_text())
            changed["rawGraphInputs"].reverse()
            link_raw = json.dumps(changed, sort_keys=True, separators=(",", ":")).encode()
            link.write_bytes(link_raw)
            data = json.loads(manifest.read_text())
            data["linkEvidenceSha256"] = digest(link_raw)
            manifest_raw = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
            manifest.write_bytes(manifest_raw)
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link_raw)):
                with self.assertRaisesRegex(archive.ArchiveError, "exact ordered link descriptors"):
                    archive.load_archive(manifest, expected_manifest_sha256=digest(manifest_raw),
                        link_path=link, workspace_root=root / "workspace", scratch_root=root / "scratch")

    def test_rejects_chunk_truncation_and_never_exposes_partial_cache(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, link, _, _ = tiny_archive(root)
            data = json.loads(manifest.read_text())
            first = manifest.parent / data["files"][0]["chunks"][0]["archivePath"]
            first.write_bytes(first.read_bytes()[:-3])
            raw = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
            manifest.write_bytes(raw)
            pin = digest(raw)
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link.read_bytes())):
                with self.assertRaisesRegex(archive.ArchiveError, "compressed chunk size changed"):
                    archive.load_archive(manifest, expected_manifest_sha256=pin,
                        link_path=link, workspace_root=root / "workspace", scratch_root=root / "scratch")
            self.assertEqual(list((root / "scratch").iterdir()), [])

    def test_rejects_chunk_order(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, link, _, _ = tiny_archive(root)
            data = json.loads(manifest.read_text())
            data["files"][0]["chunks"][0]["index"] = 1
            raw = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
            manifest.write_bytes(raw)
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link.read_bytes())):
                with self.assertRaisesRegex(archive.ArchiveError, "chunk order/index"):
                    archive.load_archive(manifest, expected_manifest_sha256=digest(raw),
                        link_path=link, workspace_root=root / "workspace", scratch_root=root / "scratch")

    def test_rejects_extra_input_descriptor(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, link, _, _ = tiny_archive(root)
            data = json.loads(manifest.read_text())
            link_data = json.loads(link.read_text())
            link_data["rawGraphInputs"].append({"path": "factory/out/raw/extra.json", "sha256": "sha256:" + "0" * 64})
            link_raw = json.dumps(link_data, sort_keys=True, separators=(",", ":")).encode()
            link.write_bytes(link_raw)
            data["linkEvidenceSha256"] = digest(link_raw)
            raw = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
            manifest.write_bytes(raw)
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link_raw)):
                with self.assertRaisesRegex(archive.ArchiveError, "exact ordered link descriptors"):
                    archive.load_archive(manifest, expected_manifest_sha256=digest(raw),
                        link_path=link, workspace_root=root / "workspace", scratch_root=root / "scratch")


if __name__ == "__main__":
    unittest.main()
