from __future__ import annotations
import json,shutil,tempfile
from pathlib import Path
import verify_actual_v2 as v
ROOT=Path(__file__).resolve().parent

def iso():
 t=Path(tempfile.mkdtemp(prefix='seed-origin-actual-v2-controls-'))/'bundle'; shutil.copytree(ROOT,t,ignore=shutil.ignore_patterns('__pycache__','*.pyc')); return t

def reject(label,fn):
 try: fn()
 except (AssertionError,KeyError,TypeError,ValueError,OSError): return {'control':label,'acceptedBaseline':True,'rejected':True}
 raise AssertionError(label)
def main():
 base=v.verify(ROOT); assert base['status']=='PASS'; c=[]
 b=iso(); (b/'swiftui.disabled.recipe.gate-seeded.ca4e13f820f5d258/summary.json').unlink(); c.append(reject('missing-summary',lambda:v.verify(b)))
 b=iso(); x=json.loads((b/'capture-index.json').read_text()); x['results'][0]['case']['hash']='sha256:'+'0'*64; (b/'capture-index.json').write_text(json.dumps(x)); c.append(reject('case-hash-rebind',lambda:v.verify(b)))
 b=iso(); p=b/'swiftui.image.recipe.gate-seeded.ca4e13f820f5d258/summary.json'; x=json.loads(p.read_text()); x['runs']=x['runs'][:-1]; p.write_text(json.dumps(x)); c.append(reject('run-cardinality',lambda:v.verify(b)))
 b=iso(); p=b/'swiftui.toggle.recipe.gate-seeded.ca4e13f820f5d258/summary.json'; x=json.loads(p.read_text()); x['compilerReceipt']['compiler']['exitCode']=1; p.write_text(json.dumps(x)); c.append(reject('compiler-exit-fault',lambda:v.verify(b)))
 b=iso(); p=b/'swiftui.text.bundled-font.recipe.gate-seeded.ca4e13f820f5d258/summary.json'; x=json.loads(p.read_text()); x['recorder']['permissionRequests']=True; p.write_text(json.dumps(x)); c.append(reject('permission-request-fault',lambda:v.verify(b)))
 b=iso(); p=b/'archive/swiftui.disabled.recipe.gate-seeded.ca4e13f820f5d258/source/Witness.swift'; p.write_text(p.read_text()+'\n// drift\n'); c.append(reject('archived-source-drift',lambda:v.verify(b)))
 b=iso(); p=b/'capture-command-receipt.json'; x=json.loads(p.read_text()); x['caseRoot']='factory/oracle/mac/seed-origin-v7/inputs'; p.write_text(json.dumps(x)); c.append(reject('case-root-drift',lambda:v.verify(b)))
 assert len(c)==7
 out={'kind':'seed-origin-v8-actual-evidence-fault-controls','version':'1','baseline':base,'candidateOnly':True,'controls':c,'scope':'100 candidate runs; controls reject case joins, cardinality, compiler, permission, archive, & command faults'}
 (ROOT/'fault-controls.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n')
 print(json.dumps({'status':'PASS','controls':len(c),'cases':5,'runs':100}))
if __name__=='__main__': main()
