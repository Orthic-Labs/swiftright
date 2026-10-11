from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parent; OUT=ROOT/'stage-manifest-v6.json'
def h(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 files=[]
 for p in sorted(ROOT.rglob('*')):
  if not p.is_file() or p in {OUT,ROOT/'SHA256SUMS-v6.txt'} or '__pycache__' in p.parts or p.suffix=='.pyc': continue
  files.append({'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':h(p)})
 out={'kind':'extended-demand-mapping-v6-stage','version':'6','denominator':107,'newFullDemandResolutions':0,'registryPromotion':0,'files':files,'dependencies':['factory/shell/extended-demand-mapping-v5/mapping-v5.json','existing v1 source snapshot bytes']}
 OUT.write_text(json.dumps(out,indent=2,sort_keys=True)+'\n'); (ROOT/'SHA256SUMS-v6.txt').write_text('\n'.join([f"{x['sha256']}  {x['path']}" for x in files]+[f"{h(OUT)}  stage-manifest-v6.json"])+'\n'); print({'status':'PASS','files':len(files),'bytes':sum(x['bytes'] for x in files),'stageSha256':h(OUT)})
if __name__=='__main__': main()
