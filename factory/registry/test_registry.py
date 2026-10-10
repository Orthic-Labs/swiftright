from __future__ import annotations

import unittest

from factory.registry.registry import RegistryBuildError, build_registry, validate_registry


def catalogue(*paths: str) -> dict:
    return {
        "kind": "catalogue",
        "version": "0.1",
        "id": "sdk.test.catalogue",
        "provenance": {
            "sourceHash": "sha256:" + "0" * 64,
            "createdAt": "2026-10-10T00:00:00Z",
            "producer": "test",
        },
        "symbolGraph": {
            "sdk": "test",
            "compiler": "test",
            "target": "test",
            "flagsHash": "sha256:" + "1" * 64,
            "interfaceAuditHash": "sha256:" + "2" * 64,
        },
        "symbols": [
            {"usr": f"test:{index}", "precise": f"test:{index}", "path": path, "status": "inventory"}
            for index, path in enumerate(paths)
        ],
    }


def manifest(*blocks: dict) -> dict:
    return {"version": "0.1", "id": "test.registry", "blocks": list(blocks)}


def block(block_id: str, path: str, **extra: object) -> dict:
    return {
        "id": block_id,
        "symbols": [path],
        "inventoryStatus": "inventory",
        "progress": "not-started",
        "semanticDependencies": [],
        **extra,
    }


class RegistryTests(unittest.TestCase):
    def test_resolves_exact_catalogue_usr_and_emits_schema_valid_artifact(self) -> None:
        artifact = build_registry(
            catalogue("SwiftUI.Rectangle"),
            manifest=manifest(block("swiftui.shape", "SwiftUI.Rectangle")),
            created_at="2026-10-10T00:00:00Z",
        )
        self.assertEqual(artifact["blocks"][0]["symbols"], ["test:0"])
        self.assertEqual(validate_registry(artifact), [])

    def test_does_not_infer_adaptation_or_parity_from_catalogue_symbol_status(self) -> None:
        source = catalogue("SwiftUI.Rectangle")
        source["symbols"][0]["status"] = "adapted"
        artifact = build_registry(source, manifest=manifest(block("swiftui.shape", "SwiftUI.Rectangle")))
        self.assertEqual(artifact["blocks"][0]["inventoryStatus"], "inventory")
        self.assertEqual(artifact["blocks"][0]["progress"], "not-started")

    def test_missing_and_ambiguous_selectors_fail_clearly(self) -> None:
        with self.assertRaisesRegex(RegistryBuildError, "no exact match"):
            build_registry(catalogue("SwiftUI.Rectangle"), manifest=manifest(block("swiftui.shape", "SwiftUI.Image")))
        source = catalogue("SwiftUI.fill", "SwiftUI.fill")
        with self.assertRaisesRegex(RegistryBuildError, "ambiguous"):
            build_registry(source, manifest=manifest(block("swiftui.shape", "SwiftUI.fill")))

    def test_hidden_symbols_are_not_admitted(self) -> None:
        source = catalogue("SwiftUI.Rectangle")
        source["symbols"][0]["status"] = "hidden"
        with self.assertRaisesRegex(RegistryBuildError, "hidden USR"):
            build_registry(source, manifest=manifest(block("swiftui.shape", "SwiftUI.Rectangle")))

    def test_dangling_dependencies_fail(self) -> None:
        spec = block("swiftui.shape", "SwiftUI.Rectangle", semanticDependencies=["swiftui.absent"])
        with self.assertRaisesRegex(RegistryBuildError, "not in this registry"):
            build_registry(catalogue("SwiftUI.Rectangle"), manifest=manifest(spec))

    def test_cycles_require_one_bootstrap_group(self) -> None:
        source = catalogue("SwiftUI.A", "SwiftUI.B")
        a = block("swiftui.a", "SwiftUI.A", semanticDependencies=["swiftui.b"])
        b = block("swiftui.b", "SwiftUI.B", semanticDependencies=["swiftui.a"])
        with self.assertRaisesRegex(RegistryBuildError, "requires one shared bootstrapGroup"):
            build_registry(source, manifest=manifest(a, b))
        a["bootstrapGroup"] = b["bootstrapGroup"] = "core"
        artifact = build_registry(source, manifest=manifest(a, b))
        self.assertEqual(validate_registry(artifact), [])

    def test_blocked_requires_complete_details(self) -> None:
        spec = block("swiftui.shape", "SwiftUI.Rectangle", progress="blocked")
        with self.assertRaisesRegex(RegistryBuildError, "blocked progress requires"):
            build_registry(catalogue("SwiftUI.Rectangle"), manifest=manifest(spec))

    def test_explicit_unsupported_and_blocked_states_are_preserved(self) -> None:
        source = catalogue("SwiftUI.Rectangle", "SwiftUI.Image")
        unsupported = block("swiftui.shape", "SwiftUI.Rectangle", inventoryStatus="unsupported")
        held = block(
            "swiftui.image",
            "SwiftUI.Image",
            progress="blocked",
            blocked={
                "reason": "waiting for required evidence",
                "openedAt": "2026-10-10T00:00:00Z",
                "owner": "factory/registry",
            },
        )
        artifact = build_registry(source, manifest=manifest(unsupported, held))
        self.assertEqual(artifact["blocks"][0]["inventoryStatus"], "unsupported")
        self.assertEqual(artifact["blocks"][1]["progress"], "blocked")
        self.assertEqual(validate_registry(artifact), [])


if __name__ == "__main__":
    unittest.main()
