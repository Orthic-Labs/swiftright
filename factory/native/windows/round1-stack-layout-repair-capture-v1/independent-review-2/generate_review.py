#!/usr/bin/env python3
from pathlib import Path
from review import review
import json

repo = Path(__file__).resolve().parents[5]
out = Path(__file__).resolve().parent / "report-v2.json"
out.write_text(json.dumps(review(repo), indent=2) + "\n", encoding="utf-8")
print(json.dumps({"output": str(out), "status": "ok"}))
