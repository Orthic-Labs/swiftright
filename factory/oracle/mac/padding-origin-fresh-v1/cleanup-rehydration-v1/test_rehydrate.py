from __future__ import annotations

import gzip
import importlib.util
import stat
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("rehydrate.py")
SPEC = importlib.util.spec_from_file_location("padding_rehydrate", MODULE_PATH)
assert SPEC and SPEC.loader
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class RehydrationControls(unittest.TestCase):
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

    def test_data_only_reuse_rejects_modes_bytes_and_symlinks(self):
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

    def test_reader_mapping_is_relative_hash_named_data_only(self):
        config = module.reader_config()
        self.assertEqual(config["macRoots"], ["."])
        self.assertEqual(config["macPathMap"]["/usr/bin/xcrun"], "xcrun")
        frontend = config["macPathMap"]["/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"]
        self.assertEqual(frontend, module.FRONTEND_RAW_NAME)
        self.assertTrue(frontend.endswith(".raw"))

    def test_archive_path_traversal_rejected(self):
        with self.assertRaises(ValueError): module._archive_relative("../tool")
        with self.assertRaises(ValueError): module._archive_relative("/absolute/tool")


if __name__ == "__main__":
    unittest.main()
