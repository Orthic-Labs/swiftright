import json
import copy
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import capture


class FullSourceCensusCaptureTests(unittest.TestCase):
    def test_replays_pinned_source_and_raw_index_census(self):
        result = capture.capture()
        source = result["sourceCensus"]
        raw = result["sourceKitCensus"]
        self.assertEqual(source["declarationStarts"], 20443)
        self.assertEqual(source["extensionHeaderStarts"], 2597)
        self.assertEqual(source["nonextensionDeclarationStarts"], 17846)
        self.assertEqual(source["nominalScopeCount"], 2386)
        self.assertEqual(source["v12LineageRows"], 12635)
        self.assertEqual(source["v12LineageRowsAddressedByExactKeyOrUniqueLineAndFamily"], 12635)
        self.assertEqual(source["v12LineageRowsUnaddressedOrAmbiguous"], 0)
        self.assertEqual(source["distinctSourceStartsAddressedByV12"], 12635)
        self.assertTrue(source["v12SourceStartMappingIsOneToOne"])
        self.assertEqual(source["addedNonextensionSourceStartsBeyondV12"], 5211)
        self.assertEqual(source["v12LineageJoinStates"], {
            "exact-source-start": 12602,
            "unique-line-family-source-start-name-differs": 33,
        })
        self.assertEqual(raw["immutable836ObservedRawEntityCount"], 19185)
        self.assertEqual(raw["freshUiPlusCoreHeaderObservedRawEntityCount"], 19185)
        self.assertTrue(raw["uiPlusCoreRecordCountAgreesAcrossOldAndFreshCoreInputs"])
        saved = Path(capture.HERE / "full-source-census-v2.json")
        self.assertEqual(result, json.loads(saved.read_text()))

    def test_rejects_manifest_and_sdk_source_pin_faults(self):
        original_manifest = capture.PRE_CAPTURE_MANIFEST
        original_modules = copy.deepcopy(capture.MODULES)
        try:
            manifest = json.loads(original_manifest.read_text())
            manifest["files"][0]["sha256"] = "sha256:" + "0" * 64
            with tempfile.TemporaryDirectory(dir=capture.HERE) as directory:
                altered = Path(directory) / "manifest.json"
                altered.write_text(json.dumps(manifest))
                capture.PRE_CAPTURE_MANIFEST = altered
                with self.assertRaisesRegex(ValueError, "pre-capture source/input changed"):
                    capture.capture()
            capture.PRE_CAPTURE_MANIFEST = original_manifest
            capture.MODULES["SwiftUI"]["source_sha256"] = "sha256:" + "0" * 64
            with self.assertRaisesRegex(ValueError, "pinned input hash mismatch"):
                capture.capture()
        finally:
            capture.PRE_CAPTURE_MANIFEST = original_manifest
            capture.MODULES = original_modules

    def test_archive_replay_does_not_read_installed_sdk_path(self):
        original_read_bytes = Path.read_bytes

        def reject_sdk_read(path):
            if str(path).startswith("/Applications/Xcode-27-RC.app/"):
                raise AssertionError("offline census replay read installed SDK bytes")
            return original_read_bytes(path)

        with patch.object(Path, "read_bytes", reject_sdk_read):
            replay = capture.capture()
        self.assertEqual(
            replay["preservedLiveSdkCheck"]["replayMode"],
            "archived-source-and-raw-inputs-only; does-not-read-installed-SDK-or-cache",
        )


if __name__ == "__main__":
    unittest.main()
