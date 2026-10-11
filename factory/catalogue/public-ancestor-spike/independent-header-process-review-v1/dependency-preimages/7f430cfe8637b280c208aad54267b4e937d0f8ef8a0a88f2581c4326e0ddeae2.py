#!/usr/bin/env python3
import copy,json,subprocess,tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent; V=HERE/'verify_process_receipts.py'; E=HERE/'process-evidence-v2.json'; ROOT=HERE.parents[4]
def run(d):
 with tempfile.NamedTemporaryFile('w',delete=False,suffix='.json') as f: json.dump(d,f); p=f.name
 r=subprocess.run(['python3',str(V),'--evidence',p],capture_output=True,text=True); Path(p).unlink(); return r.returncode
def main():
 base=json.loads(E.read_text()); assert run(base)==0
 faults=[]
 for label,mut in [('status',lambda d:d.update(status='eligible')),('target',lambda d:d.update(target='x86_64-apple-macosx27.0')),('link',lambda d:d['immutableLink'].update(sha256='sha256:'+'0'*64)),('missingReceipt',lambda d:d['modules'][0].update(receipt='missing.json'))]:
  x=copy.deepcopy(base); mut(x); assert run(x)!=0; faults.append(label)
 rpath=ROOT/base['modules'][0]['receipt']; original=json.loads(rpath.read_text()); fault=rpath.with_name('.process-v2-fault.json'); bad=copy.deepcopy(original); bad['process']['returncode']=1; fault.write_text(json.dumps(bad)); x=copy.deepcopy(base); x['modules'][0]['receipt']=str(fault.relative_to(ROOT)); assert run(x)!=0; fault.unlink(); faults.append('receiptReturncode')
 print(f'process-v2 receipt tests: baseline pass; {len(faults)} single-field faults rejected ({", ".join(faults)})')
if __name__=='__main__':main()
