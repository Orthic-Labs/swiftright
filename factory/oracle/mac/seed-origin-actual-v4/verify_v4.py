#!/usr/bin/env python3
from __future__ import annotations
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parent; V2=ROOT.parent/'seed-origin-actual-v2'
EXPECTED_STALE={'path':'fault-controls.json','bytes':1153,'sha256':'sha256:202cd05db010a4329708a73167b9971ace22009702d3678d4db2d897435bf892'}
def h(p): return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def load(p): return json.loads(p.read_text())
def resolve(rel):
 assert isinstance(rel,str) and not Path(rel).is_absolute() and '..' in Path(rel).parts
 p=(ROOT/rel).resolve(); assert p.is_relative_to(ROOT.parent.resolve()); return p
def verify():
 idx=load(ROOT/'admission-index-v4.json'); assert idx['pathBase']=='factory/oracle/mac/seed-origin-actual-v4' and idx['candidateOnly'] is True
 amap=resolve(idx['immutableArchiveMap']); assert h(amap)==idx['immutableArchiveMapSha256']; m=load(amap); assert m['cases']==5 and m['runsPerCase']==20
 stale=[]
 for row in m['files']:
  p=V2/row['path']; actual=h(p) if p.is_file() else None
  if row['path']=='fault-controls.json': assert row==EXPECTED_STALE and actual=='sha256:233714ad190f266a54ea0946bb41fd14c8b7b4a308f5a6c1a829cffabc4a1095'; stale.append({'path':row['path'],'expectedSha256':row['sha256'],'actualSha256':actual})
  else: assert p.is_file() and p.stat().st_size==row['bytes'] and actual==row['sha256'], row['path']
 capture=resolve(idx['captureIndex']); assert h(capture)==idx['captureIndexSha256']; ci=load(capture); assert len(ci['results'])==5
 for row in idx['cases']:
  p=resolve(row['summaryPath']); assert h(p)==row['summarySha256']; s=load(p); assert len(s['runs'])==20 and s['candidateOnly'] is True and s['status']=='CANDIDATE_CAPTURED'; c=s['compilerReceipt']['compiler']; assert c['exitCode']==0 and c['sourceDrift'] is False and c['realToolDrift'] is False
 cmd=resolve(idx['captureCommand']); assert h(cmd)==idx['captureCommandSha256']; x=load(cmd); assert x['caseRoot']=='factory/oracle/mac/seed-origin-v8/inputs' and x['candidateOnly'] is True
 f=ROOT/'fault-controls-v4.json'; assert h(f)==idx['faultControlsSha256']; z=load(f); assert len(z['controls'])==7 and all(c['acceptedBaseline'] and c['rejected'] for c in z['controls']); pc=ROOT/'path-controls-v4.json'; assert h(pc)==idx['pathControlsSha256']; q=load(pc); assert len(q['controls'])==2 and all(c['acceptedBaseline'] and c['rejected'] for c in q['controls'])
 return {'status':'PASS','decision':'BLOCKED_ARCHIVE_HISTORY_ONLY','cases':5,'runs':100,'archiveRows':len(m['files']),'staleHistoricalRows':stale,'archiveMapSha256':h(amap),'controlsSha256':h(f)}
if __name__=='__main__': print(json.dumps(verify(),indent=2,sort_keys=True))
