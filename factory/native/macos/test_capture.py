import tempfile
import unittest
from pathlib import Path
from factory.native.macos.capture import CaptureError, _write_exact, digest, file_ref, internal_scratch, nonvacuous, witness_ax_nodes

class CaptureAdapterTests(unittest.TestCase):
    def test_external_volume_and_symlink_scratch_rejected(self):
        with self.assertRaises(CaptureError): internal_scratch(Path('/Volumes/D/fresh-host'))
        with tempfile.TemporaryDirectory() as directory:
            link = Path(directory) / 'escape'
            link.symlink_to('/Volumes/D')
            with self.assertRaises(CaptureError): internal_scratch(link / 'fresh-host')
        self.assertEqual(internal_scratch(Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1')), Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1'))

    def test_origin_ref_binds_regular_file_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'origin.json'
            path.write_bytes(b'{"status":"SUCCESS"}\n')
            ref = file_ref(path)
            self.assertEqual(ref, {'path': str(path), 'sha256': digest(path), 'bytes': path.stat().st_size})
            link = Path(directory) / 'link.json'
            link.symlink_to(path)
            with self.assertRaises(CaptureError): file_ref(link)

    def test_archive_reuse_requires_exact_mode_and_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'tool'
            _write_exact(path, b'tool', 0o644)
            _write_exact(path, b'tool', 0o644)
            path.chmod(0o755)
            with self.assertRaises(CaptureError): _write_exact(path, b'tool', 0o644)
            path.chmod(0o644)
            with self.assertRaises(CaptureError): _write_exact(path, b'changed', 0o644)

    def test_nonvacuous_render_requires_pixels(self):
        self.assertFalse(nonvacuous({'status': 'OBSERVED', 'image': {'width': 48, 'height': 32, 'uniqueByteValues': 1}}))
        self.assertTrue(nonvacuous({'status': 'OBSERVED', 'image': {'width': 48, 'height': 32, 'uniqueByteValues': 80}}))
        self.assertFalse(nonvacuous({'status': 'OBSERVED', 'image': {'width': 0, 'height': 32, 'uniqueByteValues': 80}}))

    def test_ax_chrome_never_counts_as_witness(self):
        raw = {'steps': [{'tree': {'role': 'AXApplication', 'children': [{'role': 'AXWindow', 'title': 'SwiftRightFactory', 'children': [{'role': 'AXButton', 'label': 'close'}]}]}}]}
        self.assertEqual(witness_ax_nodes(raw), [])
        raw['steps'][0]['tree']['children'][0]['children'].append({'role': 'AXGroup', 'subrole': 'AXHostingView', 'children': [{'role': 'AXStaticText', 'value': 'SwiftRight AV'}]})
        self.assertEqual(len(witness_ax_nodes(raw)), 1)

if __name__ == '__main__': unittest.main()
