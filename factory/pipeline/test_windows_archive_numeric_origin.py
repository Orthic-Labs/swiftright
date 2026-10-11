"""Rebound synthetic archives test bool/int confusion; no native evidence."""
import unittest

from factory.core.artifacts import file_hash, write_artifact
from factory.pipeline import test_windows_archive as fixtures
from factory.pipeline.workflow import validate_windows_archive


class WindowsArchiveNumericOrigin(unittest.TestCase):
    def setUp(self):
        fixtures.WindowsArchiveBindings.setUp(self)

    def rebind(self):
        receipt = self.directory / 'native-observation.json'
        write_artifact(receipt, [self.row])
        receipt_hash = file_hash(receipt)
        self.capture['meta']['conditions']['rawReceiptHash'] = receipt_hash
        self.capture['meta']['clock']['correlationHash'] = receipt_hash

    def test_observational_archive_still_allowed(self):
        validate_windows_archive(self.capture, self.directory)

    def test_boolean_exit_code_with_rebound_hash_rejected(self):
        self.row['exitCode'] = False
        self.rebind()
        with self.assertRaisesRegex(ValueError, 'receipt case/source/host'):
            validate_windows_archive(self.capture, self.directory)

    def test_boolean_receipt_index_with_rebound_hash_rejected(self):
        self.row['index'] = True
        self.rebind()
        with self.assertRaisesRegex(ValueError, 'run missing'):
            validate_windows_archive(self.capture, self.directory)

    def test_boolean_capture_run_rejected(self):
        self.capture['meta']['run'] = True
        with self.assertRaisesRegex(ValueError, 'positive integer'):
            validate_windows_archive(self.capture, self.directory)

    def test_string_receipt_index_with_rebound_hash_rejected(self):
        self.row['index'] = '1'
        self.rebind()
        with self.assertRaisesRegex(ValueError, 'run missing'):
            validate_windows_archive(self.capture, self.directory)


if __name__ == '__main__':
    unittest.main()
