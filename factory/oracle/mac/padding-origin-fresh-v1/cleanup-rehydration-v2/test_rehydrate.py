from __future__ import annotations

import gzip
import importlib.util
import json
import stat
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("rehydrate.py")
SPEC = importlib.util.spec_from_file_location("padding_rehydrate_v2", MODULE_PATH)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class RehydrationV2Controls(unittest.TestCase):
    def test_actual_manifest_uses_exact_string_version(self):
        manifest = module.load_manifest()
        self.assertEqual(manifest["version"], "1")
        self.assertIs(type(manifest["version"]), str)

    def test_manifest_version_bool_int_unknown_rejected(self):
        value = json.loads(module.ARCHIVE_MANIFEST.read_bytes())
        for invalid in (True, 1, "2"):
            altered = dict(value)
            altered["version"] = invalid
            with self.assertRaises(ValueError): module._validate_manifest_identity(altered)

    def test_archive_member_checks_compressed_and_raw_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            raw = b"data-only compiler fixture\n"
            compressed = gzip.compress(raw)
            member = root / "tool.gz"
            member.write_bytes(compressed)
            entry = {"archivePath": "tool.gz", "compression": "gzip", "archiveBytes": len(compressed),
                     "archiveSha256": module.digest(compressed), "bytes": len(raw), "sha256": module.digest(raw)}
            self.assertEqual(module._read_archive_member(entry, root), raw)
            member.write_bytes(compressed[:-1])
            with self.assertRaises(ValueError): module._read_archive_member(entry, root)

    def test_data_only_reuse_rejects_mode_bytes_symlink(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            path = root / "tool.raw"
            raw = b"immutable raw bytes"
            self.assertEqual(module.write_data_only(path, raw), "WRITTEN")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o644)
            self.assertEqual(module.write_data_only(path, raw), "REUSED_EXACT")
            path.chmod(0o755)
            with self.assertRaises(ValueError): module.write_data_only(path, raw)
            path.unlink()
            path.symlink_to(root / "target")
            with self.assertRaises(ValueError): module.write_data_only(path, raw)

    def test_production_mapping_reads_relative_cache_targets(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            xcrun_raw = b"xcrun data"
            frontend_raw = b"frontend data"
            (root / "xcrun").write_bytes(xcrun_raw)
            (root / module.FRONTEND_RAW_NAME).write_bytes(frontend_raw)
            config_path = root / "reader_config.json"
            config_path.write_text(json.dumps(module.reader_config()))
            extracted = [
                {"path": "xcrun", "sha256": module.digest(xcrun_raw), "bytes": len(xcrun_raw)},
                {"path": module.FRONTEND_RAW_NAME, "sha256": module.digest(frontend_raw), "bytes": len(frontend_raw)},
            ]
            result = module.verify_production_mapping(root, config_path, extracted)
            self.assertEqual(result["status"], "PASS")
            self.assertEqual(len(result["references"]), 3)


if __name__ == "__main__":
    unittest.main()
