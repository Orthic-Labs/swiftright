#!/usr/bin/env python3
import argparse,datetime,hashlib,json,sys
from pathlib import Path
def sha(p):return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def fail(x):raise ValueError(x)
def validate(root):
 root=Path(root); d=json.loads((root/'evidence/compiler-receipt.json').read_text()); d['status']=='FAILED' and d['compiler']['exitCode']==1 or fail('control is not preserved exit1 failure'); d['compiler']['outputBinary'] is None or fail('unexpected binary'); d['compiler']['timedOut'] is False or fail('timeout'); isinstance(d['compiler']['pid'],int) and d['compiler']['pid']>0 or fail('missing compiler pid'); d['compiler']['argv'][:2]==['/usr/bin/xcrun','swiftc'] or fail('argv'); d['sourceDrift'] is False or fail('source drift')
 for p,h in [(d['compiler']['stdoutPath'],d['compiler']['stdoutHash']),(d['compiler']['stderrPath'],d['compiler']['stderrHash']),(d['resolver']['stdoutPath'],d['resolver']['stdoutHash']),(d['resolver']['stderrPath'],d['resolver']['stderrHash'])]: Path(p).is_file() and sha(Path(p))==h or fail(f'raw stream {p}')
 return {'status':'PASS','controlStatus':d['status'],'compilerExit':1,'attempts':1,'binary':None}
if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('root');a=ap.parse_args()
 try:print(json.dumps(validate(a.root),sort_keys=True,indent=2))
 except Exception as e:print('FAIL:',e,file=sys.stderr);raise SystemExit(1)
