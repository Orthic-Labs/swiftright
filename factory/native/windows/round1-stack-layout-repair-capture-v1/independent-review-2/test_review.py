#!/usr/bin/env python3
from pathlib import Path
from review import review, mutation_controls

repo = Path(__file__).resolve().parents[5]
r = review(repo)
assert r["status"] == "source-prepared-only-native-capture-held"
assert r["nativeProof"] is False
assert r["stage"]["allRowsMatch"] is True
assert r["stage"]["fileCount"] == 23
assert r["plan"]["planHash"] == "8c89995f6eb23939a365d068b0eb3c8d407194a5cf1f720b9bdc71f01066e1e2"
assert r["packageSources"]["allMembershipAndHashesMatch"] is True
assert all(r["guards"].values())
assert r["rawCaptureInputJoins"]["actualCaptureRan"] is False
assert r["priorFailurePreserved"]["unchanged"] is True
assert len(r["rawCaptureInputJoins"]["missingExpectedPaths"]) == 3
m = mutation_controls(repo)
assert all(m.values())
print("4/4 source-only review checks pass")
