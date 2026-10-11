from pathlib import Path
import json,hashlib,re,datetime,collections,statistics
H=Path(__file__).resolve().parent;P=H.parent;R=P.parents[2];sha=lambda b:hashlib.sha256(b).hexdigest();load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
plan=load(P/'packet/source-plan.json');r=load(H/'results/receipt.json');assert r['error'] is None
assert [v['name'] for v in r['variants']]==['current','candidate']
assert [v['process']['exitCode'] for v in r['variants']]==[0,1]
assert sha((P/'packet/run-pair.ps1').read_bytes())==plan['runnerSha256']
obs=next((H/'results').glob('factory-swiftright-copycost-observe-*'));samples=[json.loads(l) for l in (obs/'samples.jsonl').read_text().splitlines()]
assert load(obs/'observer-end.json')['exitCode']==0
assert sha((H/'observe.ps1').read_bytes())==load(obs/'observer-start.json')['samplerHash']
for group in ('toolBindingsBefore','toolBindingsAfter'):
 assert [(x['originalPath'].lower(),x['bytes'],x['sha256']) for x in r[group]]==[(x['originalPath'].lower(),x['bytes'],x['sha256']) for x in plan['toolBindings']]
parse=lambda s:datetime.datetime.fromisoformat(s.replace('Z','+00:00'));variants=[];last=None
for v,pin in zip(r['variants'],plan['variants']):
 assert not v['sourceDrift'] and not v['process']['timedOut']
 assert sorted([{k:b[k] for k in ('path','bytes','sha256')} for b in v['sourceBindings']],key=lambda x:x['path'])==pin['bindings']
 assert len(v['sourceBindings'])==52
 assert v['command']['argv']==['test','--package-path',v['runtimePath'],'--scratch-path',v['scratchPath'],'-c','release']
 d=H/'results'/v['name'];process=load(d/'process/process.json');assert process==v['process']
 for name in ('stdout','stderr'):
  data=(d/'process'/(name+'.txt')).read_bytes();assert sha(data)==process[name+'Hash'] and len(data)==process[name+'Bytes']
 for b in v['executables']:
  f=d/'artifacts'/b['path'].replace('\\','/').split('/')[-1];assert f.stat().st_size==b['bytes'] and sha(f.read_bytes())==b['sha256']
 text=(d/'process/stdout.txt').read_text();started=re.findall(r"Test Case '([^']+)' started",text);ended=re.findall(r"Test Case '([^']+)' (passed|failed)",text)
 assert len(started)==175 and len(set(started))==175 and collections.Counter(started)==collections.Counter(x[0] for x in ended)
 errors=[l for l in text.splitlines() if ': error:' in l];failures=[x[0] for x in ended if x[1]=='failed'];assert len(errors)==(0 if v['name']=='current' else 2)
 assert failures==([] if v['name']=='current' else ['PerformanceTests.testSingleRowEditCommitTime'])
 assert "TaskIDTests.testSameIdDoesNotRestartTask' passed" in text
 perf=re.search(r'PERF 200-row commit medians \(ms\): typing ([\d.]+), scroll-only ([\d.]+), row edit ([\d.]+)  optimized=true',text);assert perf
 start=parse(process['startedAt']);end=parse(process['endedAt']);assert start<end and(last is None or last<=start);last=end
 phase=[s for s in samples if start<=parse(s['utc'])<=end];loads=[p['LoadPercentage'] for s in phase for p in s['processorLoad']]
 external=collections.Counter(x['name'] for s in phase for x in s['processes'] if not x['ownedPair'] and x['name'].lower() in ('rustc.exe','cl.exe','clang.exe','clang-cl.exe','link.exe','lld-link.exe'))
 t=re.search(r"Test Case 'PerformanceTests.testSingleRowEditCommitTime' started at ([\d\- :.]+)",text);w=datetime.datetime.fromisoformat(t[1].strip()).replace(tzinfo=datetime.timezone(datetime.timedelta(minutes=load(H/'clock-context.stdout.bin')['testDateOffsetMinutes']))).astimezone(datetime.timezone.utc)
 before=max((s for s in samples if parse(s['utc'])<=w),key=lambda s:s['utc'],default=None);after=min((s for s in samples if parse(s['utc'])>=w),key=lambda s:s['utc'],default=None)
 def compact(s):
  return None if s is None else dict(utc=s['utc'],processorLoad=s['processorLoad'],externalCompilerCounts=dict(collections.Counter(x['name'] for x in s['processes'] if not x['ownedPair'] and x['name'].lower() in ('rustc.exe','cl.exe','clang.exe','clang-cl.exe','link.exe','lld-link.exe'))))
 variants.append(dict(name=v['name'],exitCode=process['exitCode'],sourceFiles=52,testCount=175,passedTests=175-len(failures),failedTests=failures,assertionFailures=errors,performanceMilliseconds=dict(zip(('typing','scrollOnly','rowEdit'),map(float,perf.groups()))),performanceBoundsMilliseconds=[2,4,15],TaskIDSameIdPassed=True,startedAt=process['startedAt'],endedAt=process['endedAt'],sourceDrift=False,stdoutSha256=process['stdoutHash'],stderrSha256=process['stderrHash'],ambient=dict(samples=len(phase),cpuLoadMin=min(loads),cpuLoadMax=max(loads),cpuLoadMean=statistics.mean(loads),externalCompilerObservations=dict(external),performanceStartedUTC=w.isoformat(),bracketingBefore=compact(before),bracketingAfter=compact(after))))
result=dict(schema='copycost-windows-actual-pair-v1',status='actual-pair-candidate-performance-failures',sourcePlanSha256=sha((P/'packet/source-plan.json').read_bytes()),runnerSha256=plan['runnerSha256'],receiptSha256=sha((H/'results/receipt.json').read_bytes()),observerSamplesSha256=sha((obs/'samples.jsonl').read_bytes()),quiescenceSha256=sha((H/'quiescence.stdout.bin').read_bytes()),variants=variants,fullReleaseInvocations=2,order=['current','candidate'],retries=0,sourceOnlyDifference='Graph.swift',originalTestBytesPreserved=True,productionEdits=0,causalCertification=False,ambientCompilerActivityAfterQuiescence=True)
(H/'verified-capture.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ('status','receiptSha256','observerSamplesSha256')},indent=2))
for v in variants:print(v['name'],v['passedTests'],len(v['failedTests']),v['performanceMilliseconds'],v['ambient'])
