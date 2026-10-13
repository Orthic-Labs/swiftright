from __future__ import annotations
import json
from pathlib import Path
import verify_v4 as v
ROOT=Path(__file__).resolve().parent
def reject(label,fn):
 try: fn()
 except (AssertionError,ValueError): return {'control':label,'acceptedBaseline':True,'rejected':True}
 raise AssertionError(label)
def main():
 controls=[reject('absolute-reference-rejected',lambda:v.resolve('/tmp/not-evidence')),reject('outside-root-reference-rejected',lambda:v.resolve('../../outside'))]
 out={'kind':'seed-origin-v8-actual-v4-path-controls','version':'1','controls':controls,'scope':'explicit v4 path-base traversal controls'}
 (ROOT/'path-controls-v4.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n'); print(json.dumps({'status':'PASS','controls':2}))
if __name__=='__main__': main()
