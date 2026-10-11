#!/usr/bin/env python3
from review import review

r = review()
assert r["status"] == "independently-verified-candidate-observation-held"
assert r["producerStage"]["sha256"] == "47cc44505c72e5feaa96250c83cbb37bc60d42e0d2e7f79707741b308146fe62"
assert r["producerStage"]["allRowsMatch"] is True
assert r["rawJoins"] == {"baseline": "accepted", "rawWindows": 2, "rawMacArchives": 2, "rawFileCount": 881}
assert r["faultControls"] == {k: "rejected" for k in ("mismatched-source", "mismatched-case", "missing-raw", "forged-status")}
assert r["nativeDiff"] is False and r["candidateOnly"] is True
print("5/5 independent review checks pass")
