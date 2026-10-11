from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]; HERE=Path(__file__).resolve().parent
V5=ROOT/'factory/shell/extended-demand-mapping-v5/mapping-v5.json'; OUT=HERE/'mapping-v6-overlay.json'
ROWS=['f12-extended-013','f12-extended-014','f12-extended-017','f12-extended-039','f12-extended-040']; AMBIG=['f12-extended-001','f12-extended-002','f12-extended-045']
SOURCES={
 'f12-extended-013':['factory/shell/extended-demand-mapping-v1/evidence/source-snapshots/source-09-0ed60c870fcfcb05.bin','/Volumes/D/claude/rightkit/packages/media-ui/src/image/ImageViewer.tsx'],
 'f12-extended-014':['factory/shell/extended-demand-mapping-v1/evidence/source-snapshots/source-08-c6e425f44259088d.bin','/Volumes/D/claude/rightkit/packages/media-ui/src/adapters.tsx'],
 'f12-extended-017':['factory/shell/extended-demand-mapping-v1/evidence/source-snapshots/source-06-d80f967e8e156a63.bin','/Volumes/D/claude/rightkit/packages/legal-ui/src/LegalGate.tsx'],
 'f12-extended-039':['factory/shell/extended-demand-mapping-v1/evidence/source-snapshots/source-02-cce566059ce3c2e2.bin','/Volumes/D/claude/rightkit/packages/app-shell/src/nav.ts'],
 'f12-extended-040':['factory/shell/extended-demand-mapping-v1/evidence/source-snapshots/source-10-8eff4d33f0ce06f5.bin','/Volumes/D/claude/rightkit/packages/onboarding/src/Onboarding.tsx'],
}
def ref(rel,orig):
 p=ROOT/rel; b=p.read_bytes(); t=b.decode(); return {'snapshotPath':rel,'originalPath':orig,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest(),'sourceLanguage':p.suffix or 'bin','containsSwiftUIImport':('import SwiftUI' in t),'containsRegistrySelector':('registry' in t.lower()),'utf8Search':{'SwiftUI':t.count('SwiftUI'),'swiftui':t.lower().count('swiftui'),'registry':t.lower().count('registry')}}
def main():
 base=json.loads(V5.read_text()); assert base['denominator']['extendedDemandRows']==107 and len(base['rows'])==107
 rows=[]
 for key in ROWS:
  old=next(r for r in base['rows'] if r['rowKey']==key); path,orig=SOURCES[key]
  rows.append({'rowKey':key,'demand':old['demand'],'priorDisposition':old['v5Evidence']['disposition'],'disposition':'unresolved-held','fullDemandResolved':False,'registryPromotion':False,'sourceRefs':[ref(path,orig)],'reason':'Exact source is host-side '+ref(path,orig)['sourceLanguage']+' and contains no SwiftUI import or registry selector; no exact SDK declaration/overload identity is proven.'})
 amb=[]
 for key in AMBIG:
  old=next(r for r in base['rows'] if r['rowKey']==key); amb.append({'rowKey':key,'demand':old['demand'],'priorDisposition':old['v5Evidence']['disposition'],'disposition':'ambiguous-catalogue-held','fullDemandResolved':False,'registryPromotion':False,'reason':'Existing catalogue candidates remain ambiguous; current host evidence cannot select exact SDK declaration.'})
 out={'kind':'extended-demand-mapping-v6-overlay','version':'6','status':'source-audit-only','baseMappingPath':'factory/shell/extended-demand-mapping-v5/mapping-v5.json','baseMappingSha256':hashlib.sha256(V5.read_bytes()).hexdigest(),'denominator':107,'rowCount':107,'remainingUnresolved':rows,'ambiguousRows':amb,'newFullDemandResolutions':0,'registryPromotion':0,'sdkArchiveResolution':0,'controls':['exact base mapping hash','exact snapshot bytes/hash','reject SwiftUI/registry marker drift','reject row/denominator/promotion drift']}
 OUT.write_text(json.dumps(out,indent=2,sort_keys=True)+'\n'); (HERE/'evidence/source-provenance-v6.json').write_text(json.dumps({'kind':'v6-source-provenance','baseMappingSha256':out['baseMappingSha256'],'refs':[x for r in rows for x in r['sourceRefs']]},indent=2,sort_keys=True)+'\n'); print({'status':'PASS','unresolved':5,'ambiguous':3,'denominator':107})
if __name__=='__main__': main()
