from __future__ import annotations

import copy
import hashlib
import json
import tempfile
from pathlib import Path

import generate as g


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def expect_reject(label, packet, sources):
    try:
        g.validate_packet(packet, sources)
    except (ValueError, KeyError, TypeError):
        return {"control": label, "acceptedBaseline": True, "rejected": True}
    raise AssertionError(label)


def main():
    packet = g.main()
    sources = g.source_rows()
    baseline = json.loads(g.V4.read_text())
    for got, old in zip(packet["rows"], baseline["rows"]):
        got_copy = copy.deepcopy(got)
        got_copy.pop("v5Evidence", None)
        assert got_copy == old, got["rowKey"]
    assert packet["denominator"]["extendedDemandRows"] == 107
    assert sum("v5Evidence" in row for row in packet["rows"]) == 32
    g.validate_packet(packet, sources)

    controls = []
    mutated = copy.deepcopy(packet)
    mutated["denominator"]["extendedDemandRows"] = 106
    controls.append(expect_reject("denominator-drift", mutated, sources))
    mutated = copy.deepcopy(packet)
    mutated["rows"] = mutated["rows"][:-1]
    controls.append(expect_reject("row-cardinality-drift", mutated, sources))
    mutated = copy.deepcopy(packet)
    mutated["rows"][3]["v5Evidence"] = copy.deepcopy(mutated["rows"][1]["v5Evidence"])
    controls.append(expect_reject("non-residual-evidence", mutated, sources))
    mutated = copy.deepcopy(packet)
    target = next(r for r in mutated["rows"] if r["rowKey"] == "f12-extended-007")
    target["v5Evidence"]["registryPromotion"] = True
    controls.append(expect_reject("registry-promotion", mutated, sources))
    mutated = copy.deepcopy(packet)
    target = next(r for r in mutated["rows"] if r["rowKey"] == "f12-extended-045")
    target["v5Evidence"]["fullDemandResolved"] = True
    controls.append(expect_reject("ambiguous-full-resolution", mutated, sources))
    mutated = copy.deepcopy(packet)
    target = next(r for r in mutated["rows"] if r["rowKey"] == "f12-extended-011")
    target["v5Evidence"]["sourceEvidence"][0]["sourceId"] = "missing-source"
    controls.append(expect_reject("unknown-source", mutated, sources))
    mutated = copy.deepcopy(packet)
    target = next(r for r in mutated["rows"] if r["rowKey"] == "f12-extended-029")
    target["v5Evidence"]["sourceEvidence"][0]["lines"] = [0, 1]
    controls.append(expect_reject("wrong-source-line", mutated, sources))
    mutated = copy.deepcopy(packet)
    target = next(r for r in mutated["rows"] if r["rowKey"] == "f12-extended-007")
    target["v5Evidence"]["sourceEvidence"][0]["sha256"] = "0" * 64
    controls.append(expect_reject("source-hash-drift", mutated, sources))
    assert len(controls) == 8

    receipt = {
        "kind": "v5-source-bound-offline-controls",
        "productionCallable": "generate.main + generate.validate_packet",
        "acceptedBaseline": True,
        "denominator": 107,
        "residualRows": 32,
        "sourceBoundRows": sum(bool(r.get("v5Evidence", {}).get("sourceBound")) for r in packet["rows"]),
        "registryPromotion": False,
        "newFullDemandResolutions": 0,
        "mappingSha256": hashlib.sha256((g.HERE / "mapping-v5.json").read_bytes()).hexdigest(),
        "controls": controls,
    }
    out = g.HERE / "evidence" / "controls-v5.json"
    out.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"rows": 107, "residual": 32, "sourceBound": receipt["sourceBoundRows"], "controls": len(controls)}))


if __name__ == "__main__":
    main()
