#!/usr/bin/env python3
from pathlib import Path
import json
from review import review

out = Path(__file__).resolve().parent / "report-independent-v1.json"
out.write_text(json.dumps(review(), indent=2) + "\n", encoding="utf-8")
print(json.dumps({"status": "ok", "output": str(out)}))
