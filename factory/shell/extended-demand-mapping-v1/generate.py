from __future__ import annotations

import json
from pathlib import Path

from mapping import build_mapping, load_pinned_inputs, load_pinned_source_snapshots

HERE = Path(__file__).resolve().parent
inputs = load_pinned_inputs()
snapshots = load_pinned_source_snapshots()
candidate = build_mapping(*(inputs[key] for key in inputs), snapshots)
out = HERE / "evidence/mapping-candidate.json"
out.write_text(json.dumps(candidate, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps({"path": str(out), "rows": candidate["denominator"]["extendedDemandRows"], "registryMapped": candidate["denominator"]["registryMappedRows"], "dispositions": candidate["dispositionCounts"], "f1References": candidate["f1CatalogueIdentityCount"], "ambiguousCandidates": candidate["ambiguousCandidateCount"]}, sort_keys=True))
