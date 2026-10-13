"""In-memory positive & fault fixture for assembler source controls only."""
from __future__ import annotations

CONFIGS = (
    ("F1", ""), ("F2", ""),
    ("F3", "list-0s"), ("F3", "list-1s"), ("F3", "list-3s"),
    ("F3", "vstack-1s"), ("F3", "vstack-3s"), ("F3", "lazy-1s"),
    ("F3", "lazy-3s"), ("F4", ""), ("F5", ""), ("F6", ""),
    ("F6", "reduced"), ("F7", ""), ("F8", ""), ("F9", ""),
)
PINS = {
    "exe": "1" * 64, "renderer": "2" * 64, "driver": "3" * 64,
    "worker": "4" * 64, "coordinator": "5" * 64,
}


def _row(fixture: str, variant: str, run: int, status: str = "passed") -> dict[str, object]:
    return {
        "kind": "sr0-tuple12-matrix-run-v8", "mode": "Full",
        "fixture": fixture, "variant": variant, "run": run, "runs": 20,
        "status": status, "abortRemaining": False, "lockReleased": False,
        "driverSha256": PINS["driver"], "workerSha256": PINS["worker"],
        "coordinatorSha256": PINS["coordinator"], "exeSha256": PINS["exe"],
        "rendererSha256": PINS["renderer"], "coordinatorExit": 0,
        "targetedDelivery": True, "noActivate": True,
        "workerReceipt": f"receipts/worker-{fixture}-{variant or 'default'}-{run}.json",
        "coordinatorKernel": {
            "assigned": True, "terminal": True, "streamsDrained": True,
            "originalHandleRetained": True, "jobHandleRetained": True,
            "activeReadable": True, "activeProcesses": 0, "cleanupZero": True,
            "timedOut": False, "outputExceeded": False, "rssExceeded": False,
            "processId": 1, "peakRssBytes": 1, "rssSamples": 1,
            "deadlineSeconds": 1200, "streamCapBytes": 8388608,
            "rssCapBytes": 2147483648,
        },
    }


def positive_fixture() -> list[dict[str, object]]:
    return [_row(fixture, variant, run) for fixture, variant in CONFIGS for run in range(1, 21)]


def fault_fixture() -> list[dict[str, object]]:
    rows = positive_fixture()
    rows[0]["status"] = "failed"
    rows[0]["coordinatorKernel"]["cleanupZero"] = False  # type: ignore[index]
    rows[0]["coordinatorKernel"]["activeProcesses"] = 1  # type: ignore[index]
    return rows
