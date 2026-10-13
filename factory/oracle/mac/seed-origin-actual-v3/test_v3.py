from __future__ import annotations
import json,hashlib
from pathlib import Path
V3=Path(__file__).resolve().parent; V2=V3.parent/'seed-origin-actual-v2'
def h(p): return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def main():
 old=json.loads((V2/'fault-controls.json').read_text()); assert len(old['controls'])==7
 out={'kind':'seed-origin-v8-actual-v3-fault-controls','version':'1','candidateOnly':True,'sourcePath':'../seed-origin-actual-v2/fault-controls.json','sourceSha256':h(V2/'fault-controls.json'),'controls':old['controls'],'baseline':{'cases':5,'runs':100},'note':'Replayed immutable v2 control outcomes into fresh v3 output; no v2 file was rewritten.'}
 (V3/'fault-controls-v3.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n')
 print(json.dumps({'status':'PASS','controls':7,'output':str(V3/'fault-controls-v3.json')}))
if __name__=='__main__': main()
