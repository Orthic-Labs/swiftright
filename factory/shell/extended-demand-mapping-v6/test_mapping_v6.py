from __future__ import annotations
import copy,json,tempfile
from pathlib import Path
import verify_v6 as v
HERE=Path(__file__).resolve().parent
def reject(label,fn):
 try: fn()
 except (AssertionError,KeyError,TypeError,ValueError,OSError): return {'control':label,'acceptedBaseline':True,'rejected':True}
 raise AssertionError(label)
def main():
 base=v.verify(); controls=[]
 d=json.loads((HERE/'mapping-v6-overlay.json').read_text())
 for label,mut in [('denominator-drift',lambda x:x.update(denominator=106)),('row-omission',lambda x:x['remainingUnresolved'].pop()),('promotion-fault',lambda x:x.update(registryPromotion=1)),('base-hash-drift',lambda x:x.update(baseMappingSha256='0'*64)),('swiftui-marker-fault',lambda x:x['remainingUnresolved'][0]['sourceRefs'][0].update(containsSwiftUIImport=True)),('snapshot-hash-drift',lambda x:x['remainingUnresolved'][1]['sourceRefs'][0].update(sha256='0'*64)),('ambiguous-closure-fault',lambda x:x['ambiguousRows'].pop())]:
  y=copy.deepcopy(d); mut(y); p=Path(tempfile.mkdtemp())/'mapping.json'; p.write_text(json.dumps(y)); controls.append(reject(label,lambda p=p:v.verify(p)))
 out={'kind':'extended-demand-mapping-v6-controls','baseline':base,'controls':controls,'denominator':107,'newFullDemandResolutions':0,'registryPromotion':0}; (HERE/'evidence/controls-v6.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n'); assert len(controls)==7; print({'status':'PASS','controls':7})
if __name__=='__main__': main()
