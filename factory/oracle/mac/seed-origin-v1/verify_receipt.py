#!/usr/bin/env python3
"""Strict verifier for one actual swiftc process receipt."""
from __future__ import annotations
import argparse,datetime,hashlib,json,sys
from pathlib import Path

def sha(p): return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def fail(x): raise ValueError(x)
def instant(x):
 try: return datetime.datetime.fromisoformat(x.replace('Z','+00:00'))
 except Exception as e: fail(f'bad timestamp {x}: {e}')
def file_field(item, label):
 p=Path(item['path']); p.is_file() or fail(f'{label} missing {p}'); sha(p)==item['sha256'] or fail(f'{label} hash'); p.stat().st_size==item['bytes'] or fail(f'{label} size')
def validate(path):
 r=json.loads(Path(path).read_text()); r['kind']=='swift-compiler-process-receipt' or fail('kind'); r['status']=='SUCCESS' or fail('receipt not SUCCESS'); r['sourceDrift'] is False or fail('source drift')
 rs=r['resolver']; rs['argv']==['/usr/bin/xcrun','--find','swiftc'] or fail('resolver argv'); isinstance(rs['pid'],int) and rs['pid']>0 or fail('resolver pid'); instant(rs['startedAtUtc'])<=instant(rs['endedAtUtc']) or fail('resolver time'); rs['exitCode']==0 or fail('resolver exit'); file_field({'path':rs['stdoutPath'],'sha256':rs['stdoutHash'],'bytes':Path(rs['stdoutPath']).stat().st_size},'resolver stdout'); file_field({'path':rs['stderrPath'],'sha256':rs['stderrHash'],'bytes':Path(rs['stderrPath']).stat().st_size},'resolver stderr')
 c=r['compiler']; cp=Path(c['path']); cp.is_file() or fail('compiler missing'); sha(cp)==c['sha256'] and cp.stat().st_size==c['bytes'] or fail('compiler tool hash'); Path(c['xcrunPath']).is_file() and sha(Path(c['xcrunPath']))==c['xcrunHash'] or fail('xcrun hash'); c['argv'][0]==str(cp) or fail('argv/compiler mismatch'); isinstance(c['pid'],int) and c['pid']>0 or fail('compiler pid'); instant(c['startedAtUtc'])<=instant(c['endedAtUtc']) or fail('compiler time'); c['exitCode']==0 and c['timedOut'] is False or fail('compiler exit'); file_field({'path':c['stdoutPath'],'sha256':c['stdoutHash'],'bytes':Path(c['stdoutPath']).stat().st_size},'compiler stdout'); file_field({'path':c['stderrPath'],'sha256':c['stderrHash'],'bytes':Path(c['stderrPath']).stat().st_size},'compiler stderr')
 before=r['sourceBefore']; after=r['sourceAfter']; set(before)=={'Witness.swift','CaptureHost.swift'} and set(after)==set(before) or fail('source set');
 for k in before:
  before[k]==after[k] or fail(f'source drift {k}'); file_field(before[k],f'source {k}')
 c['cwd']==str(Path(before['Witness.swift']['path']).parent) or fail('cwd/source mismatch'); set(c['argv'][4:])>=set(x['path'] for x in before.values()) or fail('argv missing sources')
 b=c['outputBinary']; b and file_field(b,'output binary'); b['path']==c['argv'][4] or fail('output argv mismatch')
 return {'status':'PASS','compilerPid':c['pid'],'compilerExit':c['exitCode'],'sourceDrift':False,'binaryHash':b['sha256']}
if __name__=='__main__':
 ap=argparse.ArgumentParser(); ap.add_argument('receipt'); a=ap.parse_args()
 try: print(json.dumps(validate(a.receipt),sort_keys=True,indent=2))
 except Exception as e: print('FAIL:',e,file=sys.stderr); raise SystemExit(1)
