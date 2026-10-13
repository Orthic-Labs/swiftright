from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]; HERE=Path(__file__).resolve().parent; V6=ROOT/'factory/shell/extended-demand-mapping-v6/mapping-v6-overlay.json'; REG=ROOT/'factory/registry/evidence/block-registry.json'
EXPECTED={'f12-extended-001','f12-extended-002','f12-extended-013','f12-extended-014','f12-extended-017','f12-extended-039','f12-extended-040','f12-extended-045'}
def h(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def verify(path=HERE/'mapping-v7-action-overlay.json'):
 d=json.loads(path.read_text()); base=json.loads(V6.read_text()); assert d['kind']=='extended-demand-mapping-v7-action-overlay' and d['status']=='requirements-only'; assert d['denominator']==107 and d['rowCount']==107 and d['baseRowCountPreserved']==107 and d['partialOverlapsPreserved'] is True; assert base['denominator']==107 and base['rowCount']==107; assert d['baseOverlaySha256']==h(V6) and d['registrySnapshotSha256']==h(REG) and d['registryBlocksPresent']==10; assert d['newFullDemandResolutions']==0 and d['registryPromotion']==0
 base_rows={x['rowKey']:x for x in base['remainingUnresolved']+base['ambiguousRows']}; assert len(base_rows)==8
 assert len({x['rowKey'] for x in d['rows']})==8
 for x in d['rows']: assert x['rowKey'] in base_rows and x['demand']==base_rows[x['rowKey']]['demand'] and x['priorDisposition']==base_rows[x['rowKey']]['disposition']
 rows=d['rows']; assert len(rows)==8 and {x['rowKey'] for x in rows}==EXPECTED
 for x in rows:
  assert x['fullDemandResolved'] is False and x['registryPromotion'] is False and x['apiIdentityProven'] is False and isinstance(x['requiredEvidence'],list) and len(x['requiredEvidence'])>=2
 return {'status':'PASS','denominator':107,'rows':8,'newFullDemandResolutions':0,'registryPromotion':0}
if __name__=='__main__': print(json.dumps(verify(),indent=2,sort_keys=True))
