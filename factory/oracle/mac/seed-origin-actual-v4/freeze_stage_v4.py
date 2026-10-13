from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parent; OUT=ROOT/'stage-manifest-v4.json'
def h(p): return hashlib.sha256(p.read_bytes()).hexdigest()
files=[]
for p in sorted(ROOT.rglob('*')):
 if not p.is_file() or p in {OUT,ROOT/'SHA256SUMS-v4'} or '__pycache__' in p.parts or p.suffix=='.pyc': continue
 files.append({'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':h(p)})
out={'kind':'seed-origin-v8-actual-v4-successor-stage','version':'1','candidateOnly':True,'decision':'BLOCKED_ARCHIVE_HISTORY_ONLY','files':files,'dependencies':['../seed-origin-actual-v2 immutable evidence root']}
OUT.write_text(json.dumps(out,indent=2,sort_keys=True)+'\n'); (ROOT/'SHA256SUMS-v4').write_text('\n'.join([f"{x['sha256']}  {x['path']}" for x in files]+[f"{h(OUT)}  stage-manifest-v4.json"])+'\n'); print(json.dumps({'status':'PASS','files':len(files),'bytes':sum(x['bytes'] for x in files),'stageSha256':h(OUT)}))
