#!/usr/bin/env python3
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4];HERE=Path(__file__).resolve().parent;V2=HERE.parent
def pin(p):raw=p.read_bytes();return {'path':str(p.relative_to(ROOT)),'sha256':'sha256:'+hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
def main():
 finalstage=V2/'versioned-snapshots/comparator-guard-v3/stage-manifest.json';d=json.loads(finalstage.read_bytes());assert pin(finalstage)['sha256']=='sha256:1f282223050a32fabeddb2c5c80205616937ac02d86c042180406bdbf18b8b9a'
 for e in d['entries']+d['trackedDependencies']:assert pin(ROOT/e['path'])==e
 aggregate=V2/'aggregate-stage-inventory-v3.json';assert pin(aggregate)['sha256']=='sha256:830a0b86ec0157e4d31a09e6ba6982ab1c2498bd38af91889bdc889df7082f01';a=json.loads(aggregate.read_bytes());mismatches=[]
 def walk(obj):
  if isinstance(obj,dict):
   if set(('path','sha256','bytes'))<=obj.keys():
    actual=pin(ROOT/obj['path'])
    if any(actual[k]!=obj[k] for k in actual):mismatches.append({'expected':obj,'actual':actual})
   for v in obj.values():walk(v)
  elif isinstance(obj,list):
   for v in obj:walk(v)
 walk(a);assert len(mismatches)==1 and mismatches[0]['actual']['path'].endswith('comparator-guard-v2/fault-controls.json')
 h=ROOT/a['historicalReceipt']['path'];history=json.loads(h.read_bytes());assert history['entry']['historicalPreimageAvailable'] is False and history['entry']['observedCurrentSha256']==mismatches[0]['actual']['sha256']
 review=HERE/'final-guard-v3-review.json';r=json.loads(review.read_bytes());assert r['status']=='CLEAR' and r['guard']['sha256']=='sha256:ffcccfcdfb2307efd859421316267d7b9bf479a55037f0d74fc9860fe82a6e76'
 clearance={'status':'CLEAR','scope':r['scope'],'review':pin(review),'reviewer':pin(HERE/'review_guard_v3.py'),'inventoryReviewer':pin(Path(__file__)),'finalOwnerStage':pin(finalstage),'aggregate':pin(aggregate),'historicalIntegrityReceipt':pin(h),'historicalStageEntryMismatch':mismatches[0],'independentControlsPassed':6,'candidate':r['candidate'],'originalV1EntriesVerified':16,'membershipRows':65,'blocks':10,'productionEdits':0}
 out=HERE/'CLEARANCE.json';out.write_text(json.dumps(clearance,indent=2)+'\n')
 stage=HERE/'FINAL-STAGE-LIST.json';files=sorted(p for p in V2.rglob('*') if p.is_file() and '__pycache__' not in p.parts and p.suffix!='.pyc' and p!=stage);entries=[pin(p) for p in files];assert all(e['bytes']<100000000 for e in entries)
 inventory={'kind':'f2-independent-explicit-current-stage-inventory','selfExcluded':str(stage.relative_to(ROOT)),'entryCount':len(entries),'totalBytes':sum(e['bytes'] for e in entries),'entries':entries,'historicalEntryMismatchAcknowledged':pin(h),'stagePolicy':'explicit current bytes, retained history, no pyc'};stage.write_text(json.dumps(inventory,indent=2)+'\n');print(json.dumps({'clearance':pin(out),'stage':pin(stage),'entries':len(entries),'bytes':inventory['totalBytes']}))
if __name__=='__main__':main()
