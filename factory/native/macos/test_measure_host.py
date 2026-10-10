import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from factory.native.macos.capture import CaptureError, digest
from factory.native.macos.measure_host import measure, require_closure

class HostMeasurementTests(unittest.TestCase):
    def test_forged_synthetic_closed_receipt_never_runs_subprocess(self):
        for marker in ({'synthetic': True}, {'metadata': {'specExample': True}}, {'source': 'synthetic closure'}):
            with self.subTest(marker=marker), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                status = root/'status.md'; status.write_text('**Overall: SR0 is CLOSED on tuple10.**\n')
                receipt = root/'receipt.json'
                receipt.write_text(json.dumps({'tuple': '10', 'decision': 'CLOSED', 'statusHash': digest(status), 'closedAt': '2026-10-10T00:00:00Z', **marker}))
                with patch('factory.native.macos.measure_host.subprocess.check_output') as command, patch('factory.native.macos.measure_host.subprocess.run') as process, patch('factory.native.macos.measure_host.logged') as build:
                    with self.assertRaisesRegex(CaptureError, 'synthetic closure'):
                        measure(root/'out', root/'scratch', '0'*40, receipt, status)
                    command.assert_not_called()
                    process.assert_not_called()
                    build.assert_not_called()
                self.assertFalse((root/'out').exists())
                self.assertFalse((root/'scratch').exists())

    def test_open_status_creates_no_work_or_evidence(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            status = root/'status.md'; status.write_text('**Overall: SR0 is OPEN on tuple10.**\n')
            with self.assertRaises(CaptureError):
                measure(root/'out', root/'scratch', '0'*40, root/'missing-receipt.json', status)
            self.assertFalse((root/'out').exists())
            self.assertFalse((root/'scratch').exists())

    def test_closed_receipt_must_bind_exact_status_bytes(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            status = root/'status.md'; status.write_text('**Overall: SR0 is CLOSED on tuple10.**\n')
            receipt = root/'receipt.json'; receipt.write_text(json.dumps({'tuple':'10','decision':'CLOSED','statusHash':'sha256:'+'0'*64,'closedAt':'2026-10-10T00:00:00Z'}))
            with self.assertRaisesRegex(CaptureError, 'exact CLOSED'):
                require_closure(status, receipt, '0'*40)

    def test_future_closure_cannot_produce_postclosure_receipt(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            status = root/'status.md'; status.write_text('**Overall: SR0 is CLOSED on tuple10.**\n')
            receipt = root/'receipt.json'; receipt.write_text(json.dumps({'tuple':'10','decision':'CLOSED','statusHash':digest(status),'closedAt':'2999-01-01T00:00:00Z'}))
            with self.assertRaisesRegex(CaptureError, 'after closure'):
                require_closure(status, receipt, '0'*40)

if __name__ == '__main__': unittest.main()
