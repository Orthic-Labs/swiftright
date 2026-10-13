from __future__ import annotations

import copy
import json
import tempfile
from pathlib import Path

import verify_v8

HERE = Path(__file__).resolve().parent


def rejected(label: str, mutation) -> dict[str, object]:
    original = json.loads((HERE / "mapping-v8-action-overlay.json").read_text(encoding="utf-8"))
    changed = copy.deepcopy(original)
    mutation(changed)
    with tempfile.TemporaryDirectory(prefix="demand-v8-") as directory:
        path = Path(directory) / "mutated.json"
        path.write_text(json.dumps(changed), encoding="utf-8")
        try:
            verify_v8.verify(path)
        except (ValueError, AssertionError, KeyError, TypeError, OSError):
            return {"control": label, "baseline": "accepted", "mutation": "rejected"}
    raise AssertionError(f"mutation unexpectedly accepted: {label}")


def main() -> None:
    baseline = verify_v8.verify()
    controls = [
        ("denominator-drift", lambda value: value.update(denominator=106)),
        ("row-omission", lambda value: value["rows"].pop()),
        ("promotion-fault", lambda value: value.update(registryPromotion=1)),
        ("base-overlay-drift", lambda value: value.update(baseOverlaySha256="0" * 64)),
        ("registry-hash-drift", lambda value: value.update(registrySnapshotSha256="0" * 64)),
        ("resolved-fault", lambda value: value["rows"][0].update(fullDemandResolved=True)),
        ("identity-claim-fault", lambda value: value["rows"][1].update(apiIdentityProven=True)),
        ("disposition-drift", lambda value: value["rows"][0].update(disposition="resolved")),
        ("evidence-text-drift", lambda value: value["rows"][0].update(requiredEvidence=["anything", "anything"])),
        ("boolean-count-fault", lambda value: value.update(newFullDemandResolutions=False)),
    ]
    results = [rejected(label, mutation) for label, mutation in controls]
    report = {
        "kind": "extended-demand-mapping-v8-controls",
        "baseline": baseline,
        "controls": results,
        "denominator": 107,
        "unresolvedHeld": 5,
        "ambiguousHeld": 3,
        "newFullDemandResolutions": 0,
        "registryPromotion": 0,
    }
    (HERE / "evidence" / "controls-v8.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": "PASS", "rejectedMutations": len(results), "controls": [x["control"] for x in results]}))


if __name__ == "__main__":
    main()
