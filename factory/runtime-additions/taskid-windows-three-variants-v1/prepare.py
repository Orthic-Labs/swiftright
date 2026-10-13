"""Build fresh preflight bindings for deferred Windows TaskID experiment.
No compiler, SSH, or test process is started here.
"""
from __future__ import annotations
import hashlib, json
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SOURCE_MANIFEST = REPO / "factory/runtime-additions/next-runtime-diagnosis-v1/scratch-source-manifest.json"
SOURCE_ROOT = REPO / "factory/runtime-additions/next-runtime-diagnosis-v1/scratch"
VARIANTS = ("original", "retained", "terminal")
REMOTE_INPUT = r"D:\Claude\factory-swiftright-taskid-three-input-20261011"
REMOTE_RUN = r"D:\Claude\factory-swiftright-taskid-three-run-20261011"


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def file_binding(root: Path, path: Path) -> dict[str, object]:
    data = path.read_bytes()
    rel = path.relative_to(root).as_posix()
    return {"path": rel, "bytes": len(data), "sha256": sha(data)}


def canonical_json(value: object) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()


def main() -> None:
    if not SOURCE_MANIFEST.is_file():
        raise SystemExit(f"missing source manifest: {SOURCE_MANIFEST}")
    manifest_raw = SOURCE_MANIFEST.read_bytes()
    manifest = json.loads(manifest_raw)
    if manifest.get("kind") != "taskid-scratch-source-manifest":
        raise SystemExit("unexpected source manifest kind")
    rows = []
    for variant in VARIANTS:
        root = SOURCE_ROOT / variant
        if not root.is_dir():
            raise SystemExit(f"missing variant root: {root}")
        # Package inputs only: docs/logs remain frozen external evidence, never build inputs.
        paths = [p for p in sorted(root.rglob("*")) if p.is_file() and (
            p.name == "Package.swift" or "Sources" in p.relative_to(root).parts or "Tests" in p.relative_to(root).parts
        )]
        bindings = [file_binding(root, p) for p in paths]
        if len(bindings) != 45:
            raise SystemExit(f"{variant}: expected 45 package files, got {len(bindings)}")
        task = next(b for b in bindings if b["path"] == "Tests/SwiftRightRuntimeTests/TaskIDTests.swift")
        task_text = (root / "Tests/SwiftRightRuntimeTests/TaskIDTests.swift").read_text()
        required = [
            'Task.sleep(for: .milliseconds(40))',
            'XCTAssertEqual(log.results, ["a"])',
            'XCTAssertEqual(log.events.filter { $0 == "start a" }.count, 1',
        ]
        if any(marker not in task_text for marker in required):
            raise SystemExit(f"{variant}: original task body/assertions drift")
        if variant == "original" and any(marker in task_text for marker in ("retainedGraph", "waitForTerminalCommit", "DIAG variant=")):
            raise SystemExit("original variant contains diagnostic markers")
        if variant == "retained" and ("let retainedGraph = graph" not in task_text or "waitForTerminalCommit" in task_text):
            raise SystemExit("retained variant marker mismatch")
        if variant == "terminal" and ("let retainedGraph = graph" not in task_text or "waitForTerminalCommit" not in task_text or "DIAG variant=terminal" not in task_text):
            raise SystemExit("terminal variant marker mismatch")
        expected = manifest["variants"][variant]
        for b in bindings:
            if b["path"] == "Tests/SwiftRightRuntimeTests/TaskIDTests.swift":
                continue
            # All non-TaskID package files must be byte-identical across variants.
            original = file_binding(SOURCE_ROOT / "original", SOURCE_ROOT / "original" / b["path"])
            if variant != "original" and b["sha256"] != original["sha256"]:
                raise SystemExit(f"unexpected {variant} source delta: {b['path']}")
        rows.append({
            "name": variant,
            "localRoot": str(root.relative_to(REPO)),
            "remoteInputRoot": f"{REMOTE_INPUT}\\variants\\{variant}",
            "declaredTreeSha256": expected["treeSha256"],
            "declaredFileCount": expected["fileCount"],
            "packageFileCount": len(bindings),
            "taskIDSourceSha256": task["sha256"],
            "taskIDSourceBytes": task["bytes"],
            "markers": {"sleep40": True, "originalAssertions": True, "retainedGraph": variant in ("retained", "terminal"), "terminalBarrier": variant == "terminal"},
            "bindings": bindings,
            "bindingsSha256": sha(canonical_json(bindings)),
        })
    out = {
        "schema": "taskid-windows-three-variants-source-plan-v1",
        "status": "prepared-deferred-no-Windows-execution",
        "sourceManifest": {
            "path": str(SOURCE_MANIFEST.relative_to(REPO)),
            "sha256": sha(manifest_raw),
        },
        "sourceRoot": str(SOURCE_ROOT.relative_to(REPO)),
        "remoteInputRoot": REMOTE_INPUT,
        "remoteRunRoot": REMOTE_RUN,
        "variants": rows,
        "commonPins": {
            "filter": "SwiftRightRuntimeTests.TaskIDTests/testSameIdDoesNotRestartTask",
            "configuration": "release",
            "taskBodySleepMilliseconds": 40,
            "settleSleepMilliseconds": 120,
            "testAssertionsPreserved": True,
            "runtimeEdits": 0,
            "fullSuite": False,
            "eachVariantExactlyOnce": True,
        },
    }
    (HERE / "source-plan.json").write_text(json.dumps(out, indent=2) + "\n")
    print(HERE / "source-plan.json")


if __name__ == "__main__":
    main()
