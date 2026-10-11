from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]; HERE=Path(__file__).resolve().parent; V5=ROOT/'factory/shell/extended-demand-mapping-v5/mapping-v5.json'
UNRES={'f12-extended-013','f12-extended-014','f12-extended-017','f12-extended-039','f12-extended-040'}; AMB={'f12-extended-001','f12-extended-002','f12-extended-045'}
def h(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p): return json.loads(p.read_text())
def verify(path=HERE/'mapping-v6-overlay.json'):
 d=load(path); assert d['kind']=='extended-demand-mapping-v6-overlay' and d['status']=='source-audit-only'; assert d['denominator']==107 and d['rowCount']==107; assert d['baseMappingSha256']==h(V5)
 assert d['newFullDemandResolutions']==0 and d['registryPromotion']==0 and d['sdkArchiveResolution']==0
 ur=d['remainingUnresolved']; assert {x['rowKey'] for x in ur}==UNRES and len(ur)==5
 assert {x['rowKey'] for x in d['ambiguousRows']}==AMB and len(d['ambiguousRows'])==3
 for x in ur:
  assert x['disposition']=='unresolved-held' and x['fullDemandResolved'] is False and x['registryPromotion'] is False and len(x['sourceRefs'])>=1
  for ref in x['sourceRefs']:
   p=ROOT/ref['snapshotPath']; b=p.read_bytes(); t=b.decode(); assert len(b)==ref['bytes'] and h(p)==ref['sha256']; assert ref['containsSwiftUIImport'] is False and ref['containsRegistrySelector'] is False; assert 'import SwiftUI' not in t and 'registry' not in t.lower()
 return {'status':'PASS','denominator':107,'unresolved':5,'ambiguous':3,'newFullDemandResolutions':0,'registryPromotion':0}
if __name__=='__main__': print(json.dumps(verify(),indent=2,sort_keys=True))
