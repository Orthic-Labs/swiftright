from __future__ import annotations
import json
from pathlib import Path
from review import load_and_audit
HERE=Path(__file__).resolve().parent
report=load_and_audit()
(HERE/"independent-review.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
print(json.dumps({"status":report["status"],"freshRuns":report["producerPacket"]["freshRuns"],"enabledTrue":report["observation"]["enabledTrueCount"],"checks":len(report["checks"])},sort_keys=True))
