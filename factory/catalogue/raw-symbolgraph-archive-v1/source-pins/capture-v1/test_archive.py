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
        out = root / rel
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
    manifest = {
        "kind": "raw-symbolgraph-lossless-archive", "version": 1,
        "chunkSize": archive.CHUNK_SIZE, "compression": "gzip-level-9-mtime-0",
        "linkEvidencePath": "link-evidence.json", "linkEvidenceSha256": digest(link_raw),
        "rawGraphInputs": link["rawGraphInputs"], "files": file_records,
    }
    manifest_path = root / "archive-manifest.json"
    manifest_raw = (json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n").encode()
    manifest_path.write_bytes(manifest_raw)
    return manifest_path, link_path, digest(manifest_raw), source


class ArchiveTests(unittest.TestCase):
    def test_round_trip_preserves_exact_bytes_and_descriptor_order(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, link, pin, expected = tiny_archive(root)
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link.read_bytes())):
                recovered = archive.load_archive(manifest, expected_manifest_sha256=pin,
                    link_path=link, workspace_root=root, scratch_root=root / "scratch")
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
                        link_path=link, workspace_root=root, scratch_root=root / "scratch")

    def test_rejects_link_descriptor_mutation(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, link, pin, _ = tiny_archive(root)
            changed = json.loads(link.read_text())
            changed["rawGraphInputs"].reverse()
            link.write_text(json.dumps(changed, sort_keys=True, separators=(",", ":")))
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link.read_bytes())):
                with self.assertRaisesRegex(archive.ArchiveError, "exact ordered link descriptors"):
                    archive.load_archive(manifest, expected_manifest_sha256=pin,
                        link_path=link, workspace_root=root, scratch_root=root / "scratch")

    def test_rejects_chunk_truncation_and_never_exposes_partial_cache(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, link, _, _ = tiny_archive(root)
            data = json.loads(manifest.read_text())
            first = root / data["files"][0]["chunks"][0]["archivePath"]
            first.write_bytes(first.read_bytes()[:-3])
            raw = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
            manifest.write_bytes(raw)
            pin = digest(raw)
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link.read_bytes())):
                with self.assertRaisesRegex(archive.ArchiveError, "compressed chunk size changed"):
                    archive.load_archive(manifest, expected_manifest_sha256=pin,
                        link_path=link, workspace_root=root, scratch_root=root / "scratch")
            self.assertEqual(list((root / "scratch").iterdir()), [])

    def test_rejects_chunk_order_and_extra_descriptor(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest, link, _, _ = tiny_archive(root)
            data = json.loads(manifest.read_text())
            data["files"][0]["chunks"][0]["index"] = 1
            link_data = json.loads(link.read_text())
            link_data["rawGraphInputs"].append({"path": "factory/out/raw/extra.json", "sha256": "sha256:" + "0" * 64})
            link.write_text(json.dumps(link_data, sort_keys=True, separators=(",", ":")))
            data["rawGraphInputs"].append(link_data["rawGraphInputs"][-1])
            data["files"].append({"ordinal": 2})
            raw = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
            manifest.write_bytes(raw)
            with patch.object(archive, "PINNED_LINK_SHA256", digest(link.read_bytes())):
                with self.assertRaisesRegex(archive.ArchiveError, "exact ordered link descriptors"):
                    archive.load_archive(manifest, expected_manifest_sha256=digest(raw),
                        link_path=link, workspace_root=root, scratch_root=root / "scratch")


if __name__ == "__main__":
    unittest.main()
