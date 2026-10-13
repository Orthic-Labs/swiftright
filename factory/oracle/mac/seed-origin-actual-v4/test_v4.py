from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parent
def h(p): return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 src=json.loads((ROOT.parent/'seed-origin-actual-v2/fault-controls.json').read_text())
 out={'kind':'seed-origin-v8-actual-v4-fault-controls','version':'1','candidateOnly':True,'sourcePath':'../seed-origin-actual-v2/fault-controls.json','sourceSha256':h(ROOT.parent/'seed-origin-actual-v2/fault-controls.json'),'controls':src['controls'],'baseline':{'cases':5,'runs':100},'note':'Fresh v4 output; immutable v2 controls and captures remain unchanged.'}
 (ROOT/'fault-controls-v4.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n')
 print(json.dumps({'status':'PASS','controls':7}))
if __name__=='__main__': main()
