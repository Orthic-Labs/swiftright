from __future__ import annotations
import copy,json,tempfile
from pathlib import Path
import verify_v7 as v
HERE=Path(__file__).resolve().parent
def reject(label,fn):
 try: fn()
 except (AssertionError,KeyError,TypeError,ValueError,OSError): return {'control':label,'acceptedBaseline':True,'rejected':True}
 raise AssertionError(label)
def main():
 base=v.verify(); d=json.loads((HERE/'mapping-v7-action-overlay.json').read_text()); c=[]
 for label,mut in [('denominator-drift',lambda x:x.update(denominator=106)),('row-omission',lambda x:x['rows'].pop()),('promotion-fault',lambda x:x.update(registryPromotion=1)),('base-overlay-drift',lambda x:x.update(baseOverlaySha256='0'*64)),('registry-hash-drift',lambda x:x.update(registrySnapshotSha256='0'*64)),('resolved-fault',lambda x:x['rows'][0].update(fullDemandResolved=True)),('identity-claim-fault',lambda x:x['rows'][1].update(apiIdentityProven=True))]:
  y=copy.deepcopy(d); mut(y); p=Path(tempfile.mkdtemp())/'v7.json'; p.write_text(json.dumps(y)); c.append(reject(label,lambda p=p:v.verify(p)))
 out={'kind':'extended-demand-mapping-v7-controls','baseline':base,'controls':c,'denominator':107,'newFullDemandResolutions':0,'registryPromotion':0}; (HERE/'evidence/controls-v7.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n'); assert len(c)==7; print({'status':'PASS','controls':7})
if __name__=='__main__': main()
