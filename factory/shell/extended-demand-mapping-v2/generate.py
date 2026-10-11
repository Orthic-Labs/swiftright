from __future__ import annotations

import json
from pathlib import Path

from mapping_v2 import build_candidate, load_inputs

HERE = Path(__file__).resolve().parent
candidate = build_candidate(*load_inputs())
out = HERE / "evidence/current-source-candidate.json"
out.write_text(json.dumps(candidate, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
print(json.dumps({"path": str(out), **candidate["denominator"], "status": candidate["status"]}, sort_keys=True))
