#!/usr/bin/env python3
import copy, json, subprocess, tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent; V=HERE/'verify_external_indexes.py'; E=HERE/'external-owner-header-index-evidence.json'
def run(d):
 with tempfile.NamedTemporaryFile('w',suffix='.json',delete=False) as f:
  json.dump(d,f); path=f.name
 r=subprocess.run(['python3',str(V),'--evidence',path],capture_output=True,text=True); return r.returncode,r.stdout+r.stderr
def main():
 base=json.loads(E.read_text()); rc,out=run(base); assert rc==0,out
 faults=[]
 for label,mut in [
  ('status',lambda d:d.update(status='eligible')),
  ('sourceHash',lambda d:d['modules'][0]['source'].update(sha256='sha256:'+('0'*64))),
  ('failedExit',lambda d:d['modules'][0]['process'].update(exit=1)),
  ('wrongProductionTarget',lambda d:d['modules'][0]['headers'].update(productionTarget='x86_64-apple-macosx27.0')),
  ('wrongCompilerTarget',lambda d:d['modules'][0]['headers']['compilerArgs'].__setitem__(-1,'x86_64-apple-macosx27.0')),
  ('rawHash',lambda d:d['modules'][0]['process']['stdout'].update(sha256='sha256:'+('1'*64))),
  ('wrongUSR',lambda d:d['modules'][0]['targetRecords'][0].update(usr='wrong')),
  ('missingTarget',lambda d:d['modules'][0].update(targetRecords=[])),
  ('missingModule',lambda d:d.update(modules=d['modules'][:-1])),
 ]:
  x=copy.deepcopy(base); mut(x); rc,msg=run(x); assert rc!=0,label; faults.append(label)
 print(f'external-owner-header-index-v1 verifier tests: baseline pass; {len(faults)} nonvacuous single-field faults rejected ({", ".join(faults)})')
if __name__=='__main__': main()
