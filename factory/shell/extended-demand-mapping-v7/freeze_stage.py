from __future__ import annotations
import hashlib,json
from pathlib import Path
HERE=Path(__file__).resolve().parent
OUT=HERE/'stage-manifest-v7.json'; SUM=HERE/'SHA256SUMS-v7.txt'
SKIP={OUT.name,SUM.name}
files=[]
for p in sorted(HERE.rglob('*')):
    if not p.is_file() or p.name in SKIP or '__pycache__' in p.parts or p.suffix=='.pyc': continue
    rel=p.relative_to(HERE).as_posix(); b=p.read_bytes()
    files.append({'path':rel,'bytes':len(b),'sha256':hashlib.sha256(b).hexdigest()})
manifest={'kind':'extended-demand-mapping-v7-stage','version':'7','status':'requirements-only','denominator':107,'rowCount':107,'newFullDemandResolutions':0,'registryPromotion':0,'files':files,'dependencies':[{'path':'factory/shell/extended-demand-mapping-v6/mapping-v6-overlay.json','sha256':hashlib.sha256((HERE.parent/'extended-demand-mapping-v6/mapping-v6-overlay.json').read_bytes()).hexdigest()},{'path':'factory/registry/evidence/block-registry.json','sha256':hashlib.sha256((HERE.parents[2]/'factory/registry/evidence/block-registry.json').read_bytes()).hexdigest()}]}
OUT.write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
SUM.write_text(''.join(f"{x['sha256']}  {x['path']}\n" for x in files))
print(json.dumps({'status':'PASS','files':len(files),'bytes':sum(x['bytes'] for x in files)},sort_keys=True))
