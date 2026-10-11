from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]; PACKET=ROOT/'factory/shell/extended-demand-mapping-v6'; OUT=Path(__file__).resolve().parent
def h(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 failures=[]; p=PACKET/'mapping-v6-overlay.json'; d=json.loads(p.read_text());
 if d.get('denominator')!=107 or d.get('rowCount')!=107: failures.append('denominator/row count')
 if d.get('newFullDemandResolutions')!=0 or d.get('registryPromotion')!=0 or d.get('sdkArchiveResolution')!=0: failures.append('promotion gate')
 if len(d.get('remainingUnresolved',[]))!=5 or len(d.get('ambiguousRows',[]))!=3: failures.append('residual cardinality')
 expected={'f12-extended-013','f12-extended-014','f12-extended-017','f12-extended-039','f12-extended-040'}
 if {x.get('rowKey') for x in d.get('remainingUnresolved',[])}!=expected: failures.append('unresolved identities')
 for row in d.get('remainingUnresolved',[]):
  if row.get('disposition')!='unresolved-held' or row.get('fullDemandResolved') is not False or row.get('registryPromotion') is not False: failures.append(f"row gate:{row.get('rowKey')}")
  for ref in row.get('sourceRefs',[]):
   q=ROOT/ref['snapshotPath']; txt=q.read_text();
   if h(q)!=ref['sha256'] or q.stat().st_size!=ref['bytes']: failures.append(f"source pin:{row.get('rowKey')}")
   if ref.get('containsSwiftUIImport') is not False or ref.get('containsRegistrySelector') is not False or 'import SwiftUI' in txt or 'registry' in txt.lower(): failures.append(f"source marker:{row.get('rowKey')}")
 controls=json.loads((PACKET/'evidence/controls-v6.json').read_text()).get('controls',[])
 if len(controls)!=7 or any(c.get('acceptedBaseline') is not True or c.get('rejected') is not True for c in controls): failures.append('controls')
 report={'kind':'extended-demand-mapping-v6-independent-review','version':'1','packetSha256':h(p),'baseMappingSha256':d.get('baseMappingSha256'),'denominator':107,'unresolvedRows':5,'ambiguousRows':3,'newFullDemandResolutions':0,'registryPromotion':0,'failures':failures,'decision':'PENDING_INDEPENDENT_LUNA_REVIEW','reviewScope':'offline source/hash/denominator/fault audit; no mapping promotion'}
 (OUT/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n'); print(json.dumps(report,indent=2,sort_keys=True))
if __name__=='__main__': main()
