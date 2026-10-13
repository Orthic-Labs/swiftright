#!/usr/bin/env python3
"""Strict verifier for one seed-origin-v2 compiler process receipt."""
import argparse,datetime,hashlib,json,sys
from pathlib import Path

def sha(p): return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def fail(x): raise ValueError(x)
def instant(x):
 try:return datetime.datetime.fromisoformat(x.replace('Z','+00:00'))
 except Exception as e:fail(f'bad timestamp: {e}')
def check_file(path, expected, label):
 p=Path(path); p.is_file() or fail(f'{label} missing'); sha(p)==expected or fail(f'{label} hash')
def validate(path):
 r=json.loads(Path(path).read_text()); r['kind']=='swift-compiler-process-receipt' and r['version']=='2' or fail('receipt kind/version'); r['status']=='SUCCESS' or fail('receipt not SUCCESS'); r['sourceDrift'] is False or fail('source drift'); r.get('invocationMode') in {'xcrun','direct'} or fail('invocation mode')
 rs=r['resolver']; rs['argv']==['/usr/bin/xcrun','--find','swiftc'] or fail('resolver argv'); isinstance(rs['pid'],int) and rs['pid']>0 or fail('resolver pid'); instant(rs['startedAtUtc'])<=instant(rs['endedAtUtc']) or fail('resolver time'); rs['exitCode']==0 or fail('resolver exit'); check_file(rs['stdoutPath'],rs['stdoutHash'],'resolver stdout'); check_file(rs['stderrPath'],rs['stderrHash'],'resolver stderr')
 c=r['compiler']; lp=Path(c['logicalCompilerPath']); rp=Path(c['realPathBefore']); lp.is_absolute() and rp.is_file() or fail('compiler paths'); str(rp)==str(lp.resolve()) or fail('logical/real binding'); sha(rp)==c['realHashBefore'] and rp.stat().st_size==c['realToolBefore']['bytes'] or fail('real compiler before hash'); c['realToolAfter']==c['realToolBefore'] or fail('real compiler drift'); c['xcrunPath']=='/usr/bin/xcrun' and Path(c['xcrunPath']).is_file() and sha(Path(c['xcrunPath']))==c['xcrunHash'] or fail('xcrun hash')
 if r['invocationMode']=='xcrun': c['argv'][:2]==['/usr/bin/xcrun','swiftc'] or fail('logical xcrun argv')
 else: c['argv'][0]==str(lp) or fail('logical direct argv')
 isinstance(c['pid'],int) and c['pid']>0 and c['pgid']==c['pid'] or fail('owned compiler pid/group'); instant(c['startedAtUtc'])<=instant(c['endedAtUtc']) or fail('compiler time'); c['exitCode']==0 and c['timedOut'] is False or fail('compiler exit'); check_file(c['stdoutPath'],c['stdoutHash'],'compiler stdout'); check_file(c['stderrPath'],c['stderrHash'],'compiler stderr')
 before=r['sourceBefore']; after=r['sourceAfter']; set(before)=={'Witness.swift','CaptureHost.swift'} and set(after)==set(before) or fail('source set')
 for k in before: before[k]==after[k] or fail(f'source drift {k}'); check_file(before[k]['path'],before[k]['sha256'],f'source {k}'); before[k]['bytes']==Path(before[k]['path']).stat().st_size or fail(f'source {k} size')
 c['cwd']==str(Path(before['Witness.swift']['path']).parent) or fail('cwd/source mismatch'); set(c['argv'][-2:])=={before['Witness.swift']['path'],before['CaptureHost.swift']['path']} or fail('argv source binding'); b=c['outputBinary']; b and check_file(b['path'],b['sha256'],'output binary'); b['path']==c['argv'][-3] or fail('output argv binding')
 return {'status':'PASS','mode':r['invocationMode'],'compilerPid':c['pid'],'compilerExit':0,'sourceDrift':False,'realCompilerHash':c['realHashBefore'],'binaryHash':b['sha256']}
if __name__=='__main__':
 ap=argparse.ArgumentParser(); ap.add_argument('receipt'); a=ap.parse_args()
 try: print(json.dumps(validate(a.receipt),sort_keys=True,indent=2))
 except Exception as e: print('FAIL:',e,file=sys.stderr); raise SystemExit(1)
