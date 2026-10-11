"""Offline validation & phase summary; never dispatches timing or native execution."""
import gzip,hashlib,json,statistics,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent
REPO=HERE.parents[2]
def sha(b):return hashlib.sha256(b).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def descriptor(p):
 b=p.read_bytes();return {'path':str(p.relative_to(REPO)),'sha256':sha(b),'bytes':len(b)}
def build():
 c=load(HERE/'config.json');r=load(HERE/'captured-corrected/receipt.json')
 assert r['error']=='' and r['order']==['original','current'] and r['limitsMS']==c['limitsMS']=={'typing':2,'scroll':4,'rowEdit':15}
 assert not r['runtimeEdits'] and not r['originalTestsEdits'] and not r['nativeWindowOpened']
 for manifest,dest in [('captured-input-manifest.json','captured'),('captured-corrected-input-manifest.json','captured-corrected')]:
  for row in load(HERE/manifest)['files']:
   b=(HERE/dest/row['path'].replace('\\','/')).read_bytes();assert sha(b)==row['sha256'] and len(b)==row['bytes']
 assert sha((HERE/'PerformancePhaseDiagnosisTests.swift').read_bytes())==c['diagnosticHash']
 for h,actual in zip(c['hosts'],r['hosts']):
  assert h['label']==actual['label'] and h['commit']==actual['commit'] and h['bindings']==actual['sourceBindings'] and h['originalRoot']==actual['originalRoot']
  prior=REPO/h['localReceipt'];assert sha(prior.read_bytes())==h['receiptHash']
  source=prior.parent/'runtime'
  for row in h['bindings']:
   b=(source/row['path']).read_bytes();assert sha(b)==row['sha256'] and len(b)==row['bytes']
 runs=r['processRuns'];assert [x['name'] for x in runs]==['compiler-version','original-build','current-build','original-test','current-test']
 for i,x in enumerate(runs):
  assert x['returncode']==(0 if i<3 else 1) and not x['timedOut'] and x['createNoWindow'] and x['startedAt']<x['endedAt']
  if i:assert runs[i-1]['endedAt']<x['startedAt']
  folder=HERE/'captured-corrected'/x['name'];assert load(folder/'process.json')==x
  for stream in ['stdout','stderr']:assert sha((folder/(stream+'.txt')).read_bytes())==x[stream+'Hash']
  if i<3:assert x['executable']==c['compiler'] and x['executableHash']==c['compilerHash']
  if i in (1,2):
   h=r['hosts'][i-1];assert x['argv']==['build','--package-path',h['runtime'],'--scratch-path',h['runtime'].rsplit('\\',1)[0]+'\\scratch','-c','release','--build-tests','-Xswiftc','-enable-testing']
  if i>=3:
   h=r['hosts'][i-3];assert x['executable']==h['binary'] and x['executableHash']==h['binaryHash'] and x['cwd']==h['binary'].rsplit('\\',1)[0]
   assert x['argv']==['SwiftRightRuntimeTests.PerformancePhaseDiagnosisTests/testMatchedOriginalWorkload']
   assert any(y['pid']==x['pid'] and y['executablePath']==x['executable'] and x['argv'][0] in (y['commandLine'] or '') for y in x['cimOrigins'])
 compiler=REPO/'factory/native/windows/module-origin-37429120-20261011/module-provenance-run-r4/compiler-input/swift.exe'
 assert sha(compiler.read_bytes())==c['compilerHash']
 a=load(HERE/'binary-archive-manifest.json');assert len(a['files'])==4
 for row in a['files']:
  b=(HERE/row['archive']).read_bytes();assert sha(b)==row['archiveSha256'] and len(b)==row['archiveBytes']
  raw=gzip.decompress(b);assert sha(raw)==row['sha256'] and len(raw)==row['bytes']
  h=next(h for h in r['hosts'] if h['label']==row['label']);assert row['sha256']==h['binaryHash' if row['kind']=='runner' else 'dllHash']
 payloads=[]
 for label in ['original','current']:
  text=(HERE/'captured-corrected'/(label+'-test')/'stdout.txt').read_text(encoding='utf-8-sig')
  lines=[x.removeprefix('PHASE_DIAG ') for x in text.splitlines() if x.startswith('PHASE_DIAG ')];assert len(lines)==1
  p=json.loads(lines[0]);assert p['optimized'] and p['rowCount']==200 and p['warmup']==5 and p['runs']==25 and p['limitsMS']==c['limitsMS'] and len(p['observations'])==90
  assert 'Executed 1 test, with 2 failures (0 unexpected)' in text
  for w in c['limitsMS']:
   samples=[x for x in p['observations'] if x['workload']==w];assert [x['sample'] for x in samples]==list(range(30));assert [x['warmup'] for x in samples]==[True]*5+[False]*25
   assert statistics.median(x['wallNS'] for x in samples[5:])/1e6==p['mediansMS'][w]
  payloads.append(p)
 phases=['evaluateNS','layoutNS','diffNS','transactionNS','resolveNS','sinkNS']
 counters=['evaluations','measurements','flushes','commits','liveNodes','resolvedNodes'];summaries=[]
 for w,limit in c['limitsMS'].items():
  samples=[[x for x in p['observations'] if x['workload']==w and not x['warmup']] for p in payloads]
  for left,right in zip(*samples):assert all(left[k]==right[k] for k in counters)
  metrics={k:{'original':statistics.median(x[k] for x in samples[0])/1e6,'current':statistics.median(x[k] for x in samples[1])/1e6} for k in ['wallNS']+phases}
  for m in metrics.values():m['delta']=round(m['current']-m['original'],7)
  residual=[statistics.median(x['wallNS']-sum(x[k] for k in phases) for x in group)/1e6 for group in samples]
  summaries.append({'workload':w,'limitMS':limit,'passes':[metrics['wallNS'][label]<limit for label in ['original','current']],'phaseMediansMS':metrics,'medianWallMinusSummedPhasesMS':dict(zip(['original','current'],residual)),'matchedMeasuredCounters':{k:sorted(set(x[k] for x in samples[0])) for k in counters}})
 failure=load(HERE/'captured/receipt.json');assert not any(x['name'].endswith('-test') for x in failure['processRuns'])
 return {'schema':'performance-phase-diagnosis-result-v1','actualTimedPairs':1,'timedProcessCount':2,'buildBeforeTiming':True,'originalLimitsUnchanged':True,'results':summaries,'processSequence':[{k:x[k] for k in ['name','pid','startedAt','endedAt','returncode','timedOut','executable','executableHash','argv','cwd']} for x in runs],'evidence':[descriptor(HERE/x) for x in ['config.json','PerformancePhaseDiagnosisTests.swift','run-pair.ps1','dispatch.py','fetch.py','archive_binaries.py','captured-corrected/receipt.json','captured-corrected-input-manifest.json','binary-archive-manifest.json','captured/receipt.json','captured-input-manifest.json']]+[descriptor(compiler)],'captureSemantics':'Actual Process StreamReader text decoded then WriteAllText. Archived captured-file bytes exact; original native stdout/stderr byte fidelity not asserted. Numeric PHASE_DIAG parsed directly.','interpretation':['Matched measured evaluation/measurement/flush/commit/live counters; observed current layout & emit resolution phase increases.','Scroll ids(ofKind:) performs another snapshot resolution outside resolveNS; wall-minus-phase residual includes unprofiled work.','resolvedNodes has no source increment; zero does not mean zero resolution work.','sinkNS represents optional nil sink/bookkeeping/lifetime envelope, not renderer cost.','Per-phase medians cannot be summed to explain wall median exactly.','Profile reset & enable-testing release compilation are diagnostic envelopes. Fixed original→current order & environment confound causal inference; this pair does not establish specific feature regression.'],'nextHypothesis':'If current additive resolved-node fields increase snapshot materialization/copy cost, isolated new-field-only variants should change emit resolution & scroll extra snapshot cost while matching work counters. No runtime change or further timing authorized by this packet.','completed':'One matched diagnostic pair completed; failed compile preserved before timing; exact consumed EXE/DLL archived; original runtime/tests/limits preserved.'}
if __name__=='__main__':
 result=build();encoded=json.dumps(result,indent=2)+'\n';p=HERE/'diagnosis.json'
 if '--check' in sys.argv:assert p.read_text()==encoded;print('Offline exact evidence replay passed')
 else:p.write_text(encoded);print('Validated single pair & archived binary closure')
