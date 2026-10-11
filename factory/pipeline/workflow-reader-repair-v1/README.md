# Workflow reader repair v1

`workflow.py` now accepts optional `artifact_reader` on collection, report, gate & `gate_evidence`. Every artifact parse under that path consumes bytes returned by reader after exact pre-read hash binding & returned-byte hash recheck; `origin_reader` remains separate for native origin guards. Omitted reader preserves legacy callers without claiming reader verification.

Focused test uses actual gate-seeded Mac20 archive with broad `ArchiveByteReader`, then injects valid JSON ID drift through reader return bytes. Drift is rejected before schema parsing; recorded workflow gate replay uses artifact reader for plan, cases, tuple, config, recipes, manifests & captures.
