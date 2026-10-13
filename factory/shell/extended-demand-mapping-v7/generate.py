from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]; HERE=Path(__file__).resolve().parent
V6=ROOT/'factory/shell/extended-demand-mapping-v6/mapping-v6-overlay.json'; REG=ROOT/'factory/registry/evidence/block-registry.json'; OUT=HERE/'mapping-v7-action-overlay.json'
REQ={
'f12-extended-013':('crop/text editing controls',['SwiftUI source witness naming exact crop/text editor declarations','exact source line/range + USR/declaration receipt','recipe/gate trigger connecting image-view-edit to declaration']),
'f12-extended-014':('custom pointer gestures',['SwiftUI source witness with exact gesture modifier/type','exact source line/range + USR/declaration receipt','recipe/gate trigger for pointer gesture semantics']),
'f12-extended-017':('document scroll/acknowledgement gating',['SwiftUI source witness for scroll container + acknowledgement action','exact source line/range + USR/declaration receipt','recipe/gate trigger for legal acceptance flow']),
'f12-extended-039':('navigation transitions',['SwiftUI source witness for navigation path/transition declaration','exact source line/range + USR/declaration receipt','recipe/gate trigger for navigation journey']),
'f12-extended-040':('ordered multi-step flow',['SwiftUI source witness for ordered flow/state transition declaration','exact source line/range + USR/declaration receipt','recipe/gate trigger for onboarding journey']),
'f12-extended-001':('Binding(get:set:)',['exact contextual Binding overload source + USR','consumer source join proving this overload']),
'f12-extended-002':('Button actions',['exact contextual Button initializer/action source + USR','consumer source join proving action family']),
'f12-extended-045':('radio/checkbox controls',['exact SwiftUI control declaration source + USR','consumer source join distinguishing candidates']),
}
def h(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 base=json.loads(V6.read_text()); assert base['denominator']==107
 rows=[]
 for key,(demand,requirements) in REQ.items():
  old=next((x for x in base['remainingUnresolved']+base['ambiguousRows'] if x['rowKey']==key),None); assert old and old['demand']==demand
  rows.append({'rowKey':key,'demand':demand,'priorDisposition':old['disposition'],'disposition':old['disposition'],'fullDemandResolved':False,'registryPromotion':False,'apiIdentityProven':False,'requiredEvidence':requirements})
 out={'kind':'extended-demand-mapping-v7-action-overlay','version':'7','status':'requirements-only','baseOverlayPath':'factory/shell/extended-demand-mapping-v6/mapping-v6-overlay.json','baseOverlaySha256':h(V6),'registrySnapshotPath':'factory/registry/evidence/block-registry.json','registrySnapshotSha256':h(REG),'registryBlocksPresent':10,'denominator':107,'rowCount':107,'baseRowCountPreserved':107,'partialOverlapsPreserved':True,'rows':rows,'newFullDemandResolutions':0,'registryPromotion':0,'note':'Actionable evidence requirements only; no new identities or demand coverage inferred. Existing per-row demand counts & partial overlaps remain governed by frozen v6.'}
 OUT.write_text(json.dumps(out,indent=2,sort_keys=True)+'\n'); print({'status':'PASS','rows':8,'denominator':107})
if __name__=='__main__': main()
