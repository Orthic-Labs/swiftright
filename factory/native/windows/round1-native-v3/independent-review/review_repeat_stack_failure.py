"""Offline preserved 15-attempt failure packet & scoped exact-owner release review."""
from pathlib import Path
import hashlib,json,re,base64
P=Path(__file__).resolve().parent.parent;R=P.parents[3]
def h(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def j(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def check():
 t=j(P/'root-repeat-stack-output-scp.json');assert t['scpExit']==0
 for f,pin in t['files'].items():assert h(R/f)==pin,f
 b=P/'repeat-stack-r1';batch=j(b/'batch.json');assert batch['requested']==20 and batch['attempted']==15 and batch['status']=='hold-batch-error' and not batch['retry']
 runs=sorted((b/'replays').iterdir());assert [x.name for x in runs]==['run-%03d'%i for i in range(1,16)]
 hashes=set()
 for row,run in zip(batch['rows'],runs):
  d=j(run/'dispatch.json');conf=j(run/'config.json');out=j(run/'native-01/capture-outcome.json');c=j(run/'observation.json');plan=j(run/'plan.json')
  assert h(run/'dispatch.json')==row['dispatchHash'] and d['owner']==conf['owner']
  assert h(run/'observation.json')==batch['compileReceiptHash']==conf['compileReceiptHash'] and c['exeSha256']==conf['exeHash']==batch['exeHash']
  assert h(run/'plan.json')==c['planSha256'] and c['sourceHash']==plan['sourceHash']
  assert c['exitCode']==0 and c['ownedExited'] and not c['timedOut']
  for name in ['stdout','stderr']:assert h(run/('native-01/host.'+name+'.txt'))==out[name+'Sha256']
  assert out['cleanup']['confirmedOwnedExit']
  if row['index']<15:
   assert d['lockAcquired'] and d['lockReleased'] and not d['cleanupErrors'] and not out['primaryError'] and not out['streamErrors']
   o=j(run/'native-observation.json');pix=j(run/'native-01/native.pixels.json');assert o['hostValid'] and o['exitCode']==0
   assert {x['path'] for x in o['files']}=={f.name for f in (run/'native-01').iterdir() if f.is_file()}
   for x in o['files']:assert h(run/'native-01'/x['path'])==x['sha256']
   assert pix['printWindowRepeatStable'] and not pix['controlledOcclusionQualification'] and pix['nativeParity']=='hold'
   assert h(run/'native-01/native.printwindow.png')==h(run/'native-01/native.printwindow.repeat.png');hashes.add(h(run/'native-01/native.printwindow.png'))
 assert len(hashes)==1
 last=runs[-1];d=j(last/'dispatch.json');out=j(last/'native-01/capture-outcome.json');own=j(last/'native-01/owned-process.json')
 assert out['primaryError']=='Owned renderer child deadline' and out['cleanup']['status']=='already-exited'
 assert out['streamErrors']==['stdout: Raw stream completion deadline','stderr: Raw stream completion deadline']
 assert not (last/'native-observation.json').exists() and d['lockAcquired'] and not d['lockReleased'] and d['lockRetainedForUnconfirmedOwnedExit']
 assert d['cleanupErrors']==['Owned exit unconfirmed: Exited process lacks known Start lineage']
 release=(P/'root-release-run015-r1.ps1').read_text()
 for path,pin in re.findall(r"Get-FileHash -LiteralPath '([^']+)'\)\.Hash\.ToLowerInvariant\(\) -ne '([0-9a-f]{64})'",release):assert h(R/path.split('\\swiftright\\',1)[1].replace('\\','/'))==pin
 assert d['owner'] in release and ('$pidValue='+str(own['pid'])) in release
 assert release.index('Get-CimInstance Win32_Process')<release.index('$q.Count -ne 0')<release.index('$stream=[IO.File]::Open')<release.index('$observed -cne $expectedOwner')<release.index("GetBytes('free')")
 start=j(P/'root-release-run015-start.json');proc=j(P/'root-release-run015-process.json');assert proc['exitCode']==0
 assert start['scriptSha256']==h(P/'root-release-run015-r1.ps1')
 for name in ['stdout','stderr']:assert h(P/('root-release-run015.'+name+'.bin'))==proc[name+'Sha256']
 actual=json.loads((P/'root-release-run015.stdout.bin').read_bytes().decode('utf-8-sig'));assert actual['actualCimCount']==0 and actual['expectedOwner']==actual['observedOwner']==d['owner'] and actual['released'] and actual['noKill']
 return {'status':'failure-packet-forensically-consistent','transferredFilePins':len(t['files']),'requested':20,'attempted':15,'successfulObservations':14,'successfulPrintWindowUniqueHashes':sorted(hashes),'failedRun':'run-015','failure':'Child deadline; both raw stream completion deadlines; failed observation omitted','lockRetainedCause':'Coordinator newly looked-up exited Process lacks known direct Start lineage; does not contradict retained capture Process already-exited proof','manualRelease':'Exact four raw receipt hashes + actual CIM PID absence + exclusive exact timestamped-owner CAS; actual exit0 release receipt verified','nativeParity':'hold','nativeRunsByReviewer':0,'producerEdits':0}
if __name__=='__main__':print(json.dumps(check(),indent=2))
