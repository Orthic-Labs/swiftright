from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parent; OUT=ROOT/'stage-manifest.json'
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
files=[]
for p in sorted(ROOT.rglob('*')):
 if not p.is_file() or p in {OUT,ROOT/'SHA256SUMS'} or '__pycache__' in p.parts or p.suffix=='.pyc': continue
 files.append({'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':sha(p)})
manifest={'kind':'seed-origin-v8-actual-candidate-stage','version':'1','candidateOnly':True,'captureStatus':'CANDIDATE_CAPTURED','cases':5,'runs':100,'files':files,'exclusions':['promotion/qualification','permission requests','prior seed-origin-actual-v1','__pycache__','*.pyc']}
OUT.write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
(ROOT/'SHA256SUMS').write_text('\n'.join([f"{x['sha256']}  {x['path']}" for x in files]+[f"{sha(OUT)}  stage-manifest.json"])+'\n')
print(json.dumps({'status':'PASS','files':len(files),'bytes':sum(x['bytes'] for x in files),'stageSha256':sha(OUT)}))
