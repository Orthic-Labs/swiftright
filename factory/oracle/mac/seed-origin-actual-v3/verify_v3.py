#!/usr/bin/env python3
"""Offline successor index verifier; reads immutable actual-v2 evidence only."""
from __future__ import annotations
import hashlib,json
from pathlib import Path
V3=Path(__file__).resolve().parent; V2=V3.parent/'seed-origin-actual-v2'
EXPECTED_STALE='sha256:202cd05db010a4329708a73167b9971ace22009702d3678d4db2d897435bf892'
def digest(p): return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def load(p): return json.loads(p.read_text())
def verify():
 assert V2.is_dir(); amap=load(V2/'archive-map.json'); assert amap['candidateOnly'] is True and amap['cases']==5 and amap['runsPerCase']==20
 stale=[]
 for row in amap['files']:
  p=V2/row['path']; actual=digest(p) if p.is_file() else None
  if row['path']=='fault-controls.json':
   assert row['sha256']==EXPECTED_STALE and actual=='sha256:233714ad190f266a54ea0946bb41fd14c8b7b4a308f5a6c1a829cffabc4a1095'
   stale.append({'path':row['path'],'expectedSha256':row['sha256'],'actualSha256':actual,'bytes':row['bytes']})
  else: assert p.is_file() and p.stat().st_size==row['bytes'] and actual==row['sha256'], row['path']
 idx=load(V2/'capture-index.json'); assert len(idx['results'])==5
 for result in idx['results']:
  cid=result['case']['id']; d=V2/cid; s=load(d/'summary.json'); assert result['status']=='CANDIDATE_CAPTURED' and s['status']=='CANDIDATE_CAPTURED' and s['candidateOnly'] is True and len(s['runs'])==20
  c=s['compilerReceipt']['compiler']; assert c['exitCode']==0 and c['timedOut'] is False and c['sourceDrift'] is False and c['realToolDrift'] is False
  assert s['recorder']['permissionRequests'] is False and s['freshAXClient']['permissionRequests'] is False
 cmd=load(V2/'capture-command-receipt.json'); assert cmd['caseRoot']=='factory/oracle/mac/seed-origin-v8/inputs' and cmd['candidateOnly'] is True
 f=load(V3/'fault-controls-v3.json'); assert f['candidateOnly'] is True and len(f['controls'])==7 and all(x['acceptedBaseline'] and x['rejected'] for x in f['controls'])
 return {'status':'PASS','decision':'BLOCKED_ARCHIVE_HISTORY_ONLY','immutableV2':str(V2),'cases':5,'runs':100,'v2ArchiveRows':len(amap['files']),'v2ArchiveMapSha256':digest(V2/'archive-map.json'),'staleHistoricalRows':stale,'v3FaultControlsSha256':digest(V3/'fault-controls-v3.json')}
if __name__=='__main__': print(json.dumps(verify(),indent=2,sort_keys=True))
