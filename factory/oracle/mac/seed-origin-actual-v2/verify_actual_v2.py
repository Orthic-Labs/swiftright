#!/usr/bin/env python3
"""Offline verifier for v8 candidate-only five-case capture evidence."""
from __future__ import annotations
import hashlib,json
from pathlib import Path
EXPECTED={
 'swiftui.disabled.recipe.gate-seeded.ca4e13f820f5d258':'sha256:68c63ea77bd20a82644b951a8335e98f6717ac138a6c6b218b6d05dadd0848ba',
 'swiftui.image.recipe.gate-seeded.ca4e13f820f5d258':'sha256:a3e936cc5f688ebd885ba817e4f0b3b4df84e3b48f6bf6b0e2c92632f5dc93b4',
 'swiftui.shapes.fill-stroke.recipe.gate-seeded.ca4e13f820f5d258':'sha256:c2a99399c435d6c1e16bbb2d80675f1f8a4ab1aa3e654b7dcf4ff1ffd0410491',
 'swiftui.text.bundled-font.recipe.gate-seeded.ca4e13f820f5d258':'sha256:29dfb27ddce10411c9fa742d5ebaf7ebef22134e1d35e64036b5952cf2254156',
 'swiftui.toggle.recipe.gate-seeded.ca4e13f820f5d258':'sha256:7113610be80860ddf6b73d6b640fd19729288131f0b0ce712740f874f726da2f',
}
def sha(p): return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def load(p): return json.loads(p.read_text())
def verify(root:Path):
 idx=load(root/'capture-index.json'); assert idx.get('candidateOnly') is True
 results=idx.get('results'); assert isinstance(results,list) and len(results)==5
 ids=[x['case']['id'] for x in results]; assert set(ids)==set(EXPECTED) and len(ids)==len(set(ids))
 for x in results:
  cid=x['case']['id']; assert x['status']=='CANDIDATE_CAPTURED' and x['case']['hash']==EXPECTED[cid]
  d=root/cid; summary=load(d/'summary.json'); assert summary['candidateOnly'] is True and summary['status']=='CANDIDATE_CAPTURED'
  assert summary['case']==x['case'] and summary['probeManifest']['case']['hash']==EXPECTED[cid]
  assert len(summary['runs'])==20 and summary['independentProcessesPerRun'] is True
  comp=summary['compilerReceipt']['compiler']; assert comp['exitCode']==0 and comp['timedOut'] is False and comp['sourceDrift'] is False and comp['realToolDrift'] is False
  assert comp['sourceBefore']==comp['sourceAfter'] and comp['ownedProcessGroup'] is True
  assert summary['freshAXClient']['compilerExitCode']==0 and summary['freshAXClient']['permissionRequests'] is False
  assert summary['recorder']['permissionRequests'] is False
  assert summary['sourceHash']==summary['probeManifest']['sourceHash']
  # every run carries actual run PID plus raw capture joins; no synthetic empty run list.
  for run in summary['runs']:
   assert isinstance(run.get('run'),int) and run['run']>=1 and isinstance(run.get('captureHash'),str)
  for n in ('Witness.swift','CaptureHost.swift','capture-host'):
   p=(root/'archive'/cid/('binary' if n=='capture-host' else 'source')/n); assert p.is_file() and p.stat().st_size>0
 cmd=load(root/'capture-command-receipt.json'); assert cmd['caseRoot']=='factory/oracle/mac/seed-origin-v8/inputs' and cmd['candidateOnly'] is True and cmd['permissionRequests'] is False
 amap=load(root/'archive-map.json'); assert amap['candidateOnly'] is True and amap['captureStatus']=='CANDIDATE_CAPTURED'
 for row in amap['files']:
  p=root/row['path']; assert p.is_file() and p.stat().st_size==row['bytes'] and sha(p)==row['sha256']
 return {'status':'PASS','cases':5,'runs':100,'candidateOnly':True,'archiveFiles':len(amap['files']),'archiveBytes':sum(x['bytes'] for x in amap['files'])}
if __name__=='__main__':
 import argparse
 p=argparse.ArgumentParser(); p.add_argument('root',type=Path,nargs='?',default=Path(__file__).resolve().parent); a=p.parse_args(); print(json.dumps(verify(a.root),indent=2,sort_keys=True))
