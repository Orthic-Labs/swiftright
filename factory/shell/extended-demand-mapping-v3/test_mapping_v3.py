#!/usr/bin/env python3
from __future__ import annotations
import copy, hashlib, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = ROOT / "factory/shell/extended-demand-mapping-v3"


def sha(p: Path) -> str:
    return hashlib.sha256(p.read_bytes()).hexdigest()


def load(name: str):
    return json.loads((HERE / name).read_text())


def validate(mapping, raw):
    assert mapping["kind"] == "f12-extended-demand-source-evidence-v3"
    assert mapping["version"] == 3 and mapping["status"] == "source-evidence-candidate-no-registry-promotion"
    assert mapping["denominator"]["extendedDemandRows"] == 107
    assert mapping["denominator"]["registryMappedRows"] == 0
    assert len(mapping["rows"]) == 107 and sum(mapping["resolutionCounts"].values()) == 107
    assert mapping["preservation"]["v1Denominator"]["extendedDemandRows"] == 107
    assert mapping["preservation"]["v2Denominator"]["extendedDemandRows"] == 107
    assert sha(ROOT / "factory/shell/extended-demand-mapping-v1/evidence/mapping-candidate.json") == mapping["preservation"]["v1CandidateSha256"]
    assert sha(ROOT / "factory/shell/extended-demand-mapping-v2/evidence/current-source-candidate.json") == mapping["preservation"]["v2CandidateSha256"]
    catalogue = json.loads((ROOT / "factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json").read_text())
    by_usr = {x["usr"]: x for x in catalogue["symbols"]}
    v2_manifest = json.loads((ROOT / "factory/shell/extended-demand-mapping-v2/evidence/source-snapshot-manifest.json").read_text())
    source_by_path = {x["sourcePath"]: x for x in v2_manifest["sources"]}
    for row in mapping["rows"]:
        ev = row["v3Evidence"]
        assert ev["registryPromotion"] is False
        assert not row.get("registryBlockId") and not row.get("registryBlockIds")
        for ref in ev["sourceSnapshots"]:
            p = ROOT / ref["snapshotPath"]
            assert p.is_file() and p.stat().st_size == ref["bytes"] and sha(p) == ref["sha256"]
        for check in ev["catalogueUsrChecks"]:
            hit = by_usr.get(check["usr"])
            assert check["cataloguePresent"] is (hit is not None)
            if hit:
                assert check["cataloguePath"] == hit["path"] and check["catalogueStatus"] == hit["status"]
        for usage in row.get("currentUsageReferences", []):
            hit = by_usr.get(usage["usr"])
            assert hit and usage["path"] == hit["path"] and usage["catalogueStatus"] == hit["status"]
            source = source_by_path.get(usage["sourcePath"])
            assert source and usage["sourceSha256"] == source["sha256"] and usage["sourceBytes"] == source["bytes"]
            snapshot = ROOT / "factory/shell/extended-demand-mapping-v2/evidence" / Path(source["snapshotPath"]).relative_to("evidence")
            lines = snapshot.read_text().splitlines()
            assert 1 <= usage["line"] <= len(lines) and lines[usage["line"] - 1] == usage["exactLine"]
    for f in raw["files"]:
        p = ROOT / f["path"]
        assert p.is_file() and p.stat().st_size == f["bytes"] and sha(p) == f["sha256"]
    assert raw["mappingSha256"] == sha(HERE / "mapping-v3.json")
    return True


def controls(mapping, raw):
    outcomes = {}
    mutations = {
        "denominator-omission": lambda q: q["rows"].pop(),
        "current-source-usr": lambda q: q["rows"][3]["currentUsageReferences"][0].__setitem__("usr", "bad-usr"),
        "registry-promotion": lambda q: q["rows"][0]["v3Evidence"].__setitem__("registryPromotion", True),
        "source-snapshot-hash": lambda q: q["rows"][0]["v3Evidence"]["sourceSnapshots"][0].__setitem__("sha256", "0" * 64),
    }
    for name, mutate in mutations.items():
        q = copy.deepcopy(mapping)
        mutate(q)
        try:
            validate(q, raw)
        except (AssertionError, KeyError, IndexError):
            outcomes[name] = "rejected"
        else:
            outcomes[name] = "accepted-BUG"
    assert all(v == "rejected" for v in outcomes.values()), outcomes
    return outcomes


mapping = load("mapping-v3.json")
raw = load("raw-pins-v3.json")
assert validate(mapping, raw)
assert controls(mapping, raw) == {k: "rejected" for k in ("denominator-omission", "current-source-usr", "registry-promotion", "source-snapshot-hash")}
print("6/6 v3 mapping checks pass")
