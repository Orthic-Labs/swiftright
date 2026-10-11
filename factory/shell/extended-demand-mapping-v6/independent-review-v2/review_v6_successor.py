from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]
STAGE=ROOT/"factory/shell/extended-demand-mapping-v6"
V5=ROOT/"factory/shell/extended-demand-mapping-v5/mapping-v5.json"
def h(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def j(p): return json.loads(p.read_text())
def run():
 d=j(STAGE/"mapping-v6-overlay.json"); base=j(V5); ctl=j(STAGE/"evidence/controls-v6.json"); prov=j(STAGE/"evidence/source-provenance-v6.json"); man=j(STAGE/"stage-manifest-v6.json")
 old={r["rowKey"]:r for r in base["rows"]}; held=d["remainingUnresolved"]+d["ambiguousRows"]; failures=[]
 if d["denominator"]!=107 or d["rowCount"]!=107 or base["denominator"]["extendedDemandRows"]!=107 or len(base["rows"])!=107: failures.append("denominator")
 if len(d["remainingUnresolved"])!=5 or len(d["ambiguousRows"])!=3 or len({r["rowKey"] for r in held})!=8: failures.append("held-cardinality")
 if any(r["rowKey"] not in old or r["demand"]!=old[r["rowKey"]]["demand"] or r["priorDisposition"]!=old[r["rowKey"]]["v5Evidence"]["disposition"] for r in held): failures.append("v5-pin")
 if d["baseMappingSha256"]!=h(V5): failures.append("base-hash")
 if d["newFullDemandResolutions"]!=0 or d["registryPromotion"]!=0 or d["sdkArchiveResolution"]!=0: failures.append("promotion")
 for row in d["remainingUnresolved"]:
  if row["disposition"]!="unresolved-held" or row["fullDemandResolved"] is not False or row["registryPromotion"] is not False: failures.append("unresolved-gate:"+row["rowKey"])
  for ref in row["sourceRefs"]:
   p=ROOT/ref["snapshotPath"]; txt=p.read_text();
   if h(p)!=ref["sha256"] or p.stat().st_size!=ref["bytes"] or ref["containsSwiftUIImport"] is not False or ref["containsRegistrySelector"] is not False or "import SwiftUI" in txt or "registry" in txt.lower(): failures.append("source-pin:"+row["rowKey"])
 if prov["refs"] != [x for r in d["remainingUnresolved"] for x in r["sourceRefs"]]: failures.append("provenance")
 if len(ctl["controls"])!=7 or any(x["acceptedBaseline"] is not True or x["rejected"] is not True for x in ctl["controls"]): failures.append("controls")
 for x in man["files"]:
  p=STAGE/x["path"]
  if not p.exists() or p.stat().st_size!=x["bytes"] or h(p)!=x["sha256"]: failures.append("stage-pin:"+x["path"])
 for line in (STAGE/"SHA256SUMS-v6.txt").read_text().splitlines():
  digest,path=line.split("  ",1); p=STAGE/path
  if not p.exists() or h(p)!=digest: failures.append("checksum:"+path)
 return {"kind":"extended-demand-mapping-v6-independent-review-successor","version":"2","decision":"CLEAR_SCOPED_NO_PROMOTION" if not failures else "HOLD","failures":failures,"denominator":107,"unresolvedRows":5,"ambiguousRows":3,"heldDispositions":8,"controls":7,"newFullDemandResolutions":d["newFullDemandResolutions"],"registryPromotion":d["registryPromotion"],"baseMappingSha256":h(V5),"overlaySha256":h(STAGE/"mapping-v6-overlay.json"),"stageManifestSha256":h(STAGE/"stage-manifest-v6.json"),"controlsSha256":h(STAGE/"evidence/controls-v6.json"),"provenanceSha256":h(STAGE/"evidence/source-provenance-v6.json"),"checksumsSha256":h(STAGE/"SHA256SUMS-v6.txt"),"reviewScope":"independent offline denominator/held-row/source-pin/control audit; no promotion"}
if __name__=="__main__": print(json.dumps(run(),indent=2,sort_keys=True))
