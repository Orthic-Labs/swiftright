from __future__ import annotations

import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from factory.reports import build_report
from factory.shell.report_demand import ReportDemandError, _build_report_demand, build_report_demand
from factory.pipeline.workflow import report as pipeline_report


ROOT = Path(__file__).resolve().parents[2]
INTEGRATION = ROOT / "factory/shell/report-demand-integration-v1"


def read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class ReportDemandTests(unittest.TestCase):
    def setUp(self):
        self.demand_path = ROOT / "factory/shell/demand.json"
        self.manifest_path = ROOT / "factory/registry/manifest.json"
        self.registry_path = ROOT / "factory/registry/evidence/block-registry.json"
        self.crosswalk_path = INTEGRATION / "crosswalk.json"
        self.demand = read(self.demand_path)
        self.manifest = read(self.manifest_path)
        self.registry = read(self.registry_path)
        self.crosswalk = read(self.crosswalk_path)
        self.demand_bytes = self.demand_path.read_bytes()
        self.manifest_bytes = self.manifest_path.read_bytes()
        self.registry_bytes = self.registry_path.read_bytes()
        self.crosswalk_bytes = self.crosswalk_path.read_bytes()
        self.kwargs = {
            "demand_sha256": sha(self.demand_path),
            "manifest_sha256": sha(self.manifest_path),
            "registry_sha256": sha(self.registry_path),
            "crosswalk_sha256": sha(self.crosswalk_path),
        }

    def adapt(self, demand=None, registry=None, crosswalk=None, **kwargs):
        return _build_report_demand(
            self.demand if demand is None else demand,
            self.manifest,
            self.registry if registry is None else registry,
            self.crosswalk if crosswalk is None else crosswalk,
            **(self.kwargs | kwargs),
        )

    def test_all_journeys_map_and_all_extended_demands_remain_unmapped(self):
        mapped = self.adapt()
        self.assertEqual(mapped["blockCapabilities"], {})
        self.assertEqual(len(mapped["journeys"]), 26)
        self.assertEqual(len(mapped["unmappedDemands"]), 107)
        self.assertTrue(all(row["registry_block_id"] is None for row in mapped["unmappedDemands"]))
        self.assertEqual(mapped["integration"]["mappingCount"], 10)
        self.assertEqual(mapped["integration"]["capabilityMapping"], "none")
        self.assertEqual(
            mapped["journeys"][0]["blocks"],
            ["swiftui.text.bundled-font", "swiftui.scroll-view", "swiftui.padding-frame"],
        )

    def test_public_adapter_parses_and_hashes_exact_raw_bytes(self):
        mapped = build_report_demand(
            self.demand_bytes,
            self.manifest_bytes,
            self.registry_bytes,
            self.crosswalk_bytes,
        )
        self.assertEqual(mapped["integration"]["f12DemandSha256"], sha(self.demand_path))
        with self.assertRaises(TypeError):
            build_report_demand(
                self.demand,
                self.manifest,
                self.registry,
                self.crosswalk,
                **self.kwargs,
            )
        changed = copy.deepcopy(self.demand)
        changed["journey_demands"][0]["journey_id"] = "navigation.poisoned"
        poisoned_bytes = json.dumps(changed, separators=(",", ":")).encode("utf-8")
        with self.assertRaisesRegex(ReportDemandError, "stale or misbound"):
            build_report_demand(
                poisoned_bytes,
                self.manifest_bytes,
                self.registry_bytes,
                self.crosswalk_bytes,
            )

    def test_report_renders_journey_associations_and_unmapped_rows(self):
        mapped = self.adapt()
        with tempfile.TemporaryDirectory() as directory:
            paths = build_report(self.registry, [], [], [], directory, mapped)
            text = Path(paths["markdown"]).read_text(encoding="utf-8")
        self.assertIn("| navigation | 3 | 0 | 3 |", text)
        self.assertIn("| settings | 5 | 0 | 5 |", text)
        self.assertIn("## Unmapped extended demands (107)", text)
        self.assertEqual(text.count("| unmapped | unmapped |"), 61)
        self.assertEqual(text.count("| source_inventory_only | unmapped |"), 46)
        self.assertNotIn("No demand map supplied", text)
        self.assertIn("No capability mapping supplied", text)

    def test_already_normalized_f9_shape_remains_reportable(self):
        normalized = {
            "blockCapabilities": {"swiftui.image": ["image preview"]},
            "journeys": [{"id": "legacy-journey", "blocks": ["swiftui.image"]}],
        }
        with tempfile.TemporaryDirectory() as directory:
            paths = build_report(self.registry, [], [], [], directory, normalized)
            text = Path(paths["markdown"]).read_text(encoding="utf-8")
        self.assertIn("| swiftui.image | no manifest cases", text)
        self.assertIn("legacy-journey", text)
        self.assertIn("image preview", text)

    def test_pipeline_preserves_normalized_f9_demand_input(self):
        normalized = {
            "blockCapabilities": {"block.one": ["explicit capability"]},
            "journeys": [{"id": "legacy-journey", "blocks": ["block.one"]}],
        }
        registry = {
            "kind": "block-registry",
            "blocks": [{"id": "block.one", "symbols": [], "inventoryStatus": "inventory", "progress": "not-started", "semanticDependencies": []}],
        }
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            cases = base / "cases.json"
            primary = base / "primary.json"
            config = base / "config.json"
            registry_path = base / "registry.json"
            demand_path = base / "demand.json"
            for path, value in ((cases, []), (primary, []), (config, {}), (registry_path, registry), (demand_path, normalized)):
                path.write_text(json.dumps(value), encoding="utf-8")
            output = base / "output"
            pipeline_report(output, cases, [], primary, config, registry_path, demand_path)
            text = (output / "report/index.md").read_text(encoding="utf-8")
            self.assertFalse((output / "report-demand.json").exists())
        self.assertIn("legacy-journey", text)
        self.assertIn("explicit capability", text)

    def test_unknown_and_duplicate_mapping_rows_reject(self):
        bad = copy.deepcopy(self.crosswalk)
        bad["mappings"][0]["pilotBlockId"] = "unknown-pilot"
        with self.assertRaisesRegex(ReportDemandError, "exactly cover"):
            self.adapt(crosswalk=bad)
        bad = copy.deepcopy(self.crosswalk)
        bad["mappings"].append(copy.deepcopy(bad["mappings"][0]))
        with self.assertRaisesRegex(ReportDemandError, "duplicate F12"):
            self.adapt(crosswalk=bad)

    def test_duplicate_target_and_missing_registry_target_reject(self):
        bad = copy.deepcopy(self.crosswalk)
        bad["mappings"][1]["registryBlockId"] = bad["mappings"][0]["registryBlockId"]
        with self.assertRaisesRegex(ReportDemandError, "duplicate F2"):
            self.adapt(crosswalk=bad)
        bad = copy.deepcopy(self.crosswalk)
        bad["mappings"][0]["registryBlockId"] = "swiftui.missing"
        with self.assertRaisesRegex(ReportDemandError, "absent from registry"):
            self.adapt(crosswalk=bad)
        bad = copy.deepcopy(self.crosswalk)
        bad["mappings"][0]["registryBlockId"] = "registry-only-extra"
        extra_registry = copy.deepcopy(self.registry)
        extra_registry["blocks"].append({"id": "registry-only-extra"})
        with self.assertRaisesRegex(ReportDemandError, "curated F2 manifest"):
            self.adapt(crosswalk=bad, registry=extra_registry)

    def test_stale_source_pins_and_unknown_journey_label_reject(self):
        with self.assertRaisesRegex(ReportDemandError, "stale or misbound"):
            self.adapt(demand_sha256="0" * 64)
        changed = copy.deepcopy(self.demand)
        changed["journey_demands"][0]["pilot_blocks"].append("unknown-pilot")
        with self.assertRaisesRegex(ReportDemandError, "unknown F12 pilot"):
            self.adapt(demand=changed)

    def test_extended_rows_cannot_be_promoted_or_dropped(self):
        bad = copy.deepcopy(self.demand)
        bad["unmapped_demands"][0]["registry_block_id"] = "swiftui.image"
        with self.assertRaisesRegex(ReportDemandError, "extended demands and unmapped rows differ|remain explicitly"):
            self.adapt(demand=bad)
        bad = copy.deepcopy(self.demand)
        bad["unmapped_demands"].pop()
        with self.assertRaisesRegex(ReportDemandError, "extended demands and unmapped rows differ"):
            self.adapt(demand=bad)

    def test_crosswalk_pilot_set_must_match_f12_rounds(self):
        bad = copy.deepcopy(self.demand)
        bad["pilot_blocks"]["round_1"].append("text")
        with self.assertRaisesRegex(ReportDemandError, "round membership"):
            self.adapt(demand=bad)

    def test_coherent_mapping_swap_requires_reviewed_crosswalk_bytes(self):
        bad = copy.deepcopy(self.crosswalk)
        bad["mappings"][0]["registryBlockId"], bad["mappings"][1]["registryBlockId"] = (
            bad["mappings"][1]["registryBlockId"], bad["mappings"][0]["registryBlockId"]
        )
        with self.assertRaisesRegex(ReportDemandError, "crosswalk bytes differ|reviewed F12-to-F2 mapping"):
            self.adapt(crosswalk=bad, crosswalk_sha256="0" * 64)


if __name__ == "__main__":
    unittest.main()
