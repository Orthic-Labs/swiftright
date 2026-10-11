from pathlib import Path
import hashlib,json,gzip,tarfile,re,datetime,collections
ROOT=Path(__file__).resolve().parents[3]
OUT=Path(__file__).resolve().parent
def sha(b):return hashlib.sha256(b).hexdigest()
def read(p):return (ROOT/p).read_bytes()
def js(p):return json.loads(read(p).decode('utf-8-sig'))
def check(p,h,n=None):
 b=read(p);assert sha(b)==h,(p,'hash');assert n is None or len(b)==n,(p,'size');return b
def stage(p,h):
 m=js(p);check(p,h);assert len(m['files'])==m['fileCount'];assert len({x['path'] for x in m['files']})==len(m['files'])
 for x in m['files']:check(x['path'],x['sha256'],x['bytes'])
 return m
M='factory/runtime-additions/copy-cost-macos-candidate-v1/'
W='factory/runtime-additions/copy-cost-windows-candidate-v1/'
ms=stage(M+'STAGE-MANIFEST.json','4bebd68a329b55c3c66ef043739bad8ae56970b48b332f8f007b662ad3e89699')
p=js(M+'evidence/source-plan.json');receipt=js(M+'evidence/run-receipt.json');em=js(M+'evidence/evidence-manifest.json')
variants={x['name']:x for x in p['variants']}
a={x['path']:x for x in variants['current']['bindings']};b={x['path']:x for x in variants['candidate']['bindings']}
assert len(a)==len(b)==52 and a.keys()==b.keys()
diff=[k for k in a if a[k]!=b[k]];assert diff==['Sources/SwiftRightRuntime/Graph.swift']
for v,r in zip(['current','candidate'],receipt['runs']):
 assert r['variant']==v and r['sourcePost']==variants[v]['bindings']
 copy=next(x for x in receipt['sourceCopies'] if x['name']==v)
 assert copy['files']==variants[v]['bindings']
 base=Path(copy['destination']);assert base.resolve().is_relative_to(Path(receipt['internalCacheBase']).resolve())
 assert base.stat().st_dev==16777232!=receipt['dDevice']
 for x in copy['files']:
  q=base/x['path'];assert not q.is_symlink();bb=q.read_bytes();assert len(bb)==x['bytes'] and sha(bb)==x['sha256']
 tests='\n'.join((base/k).read_text() for k in a if k.startswith('Tests/') and k.endswith('.swift'))
 assert len(re.findall(r'func\s+test\w+\s*\(',tests))==175
 assert r['argv']==['/usr/bin/swift','test','--package-path',str(base),'--scratch-path',r['scratch'],'-c','release']
 assert r['cwd']==str(base) and not r['timedOut'] and r['timeoutSeconds']==900
 for k in ['scratchDevice','tmpdirDevice']:assert r[k]==16777232
 for stream in ['stdout','stderr']:
  x=r[stream];check(M+'evidence/'+v+'.'+stream+'.bin',x['sha256'],x['bytes'])
assert receipt['executionOrder']==['current','candidate'] and [x['exitCode'] for x in receipt['runs']]==[0,1]
assert receipt['toolchainBefore']==receipt['toolchainAfter']
archives=[]
for x in em['archives']:
 check(x['archive'],x['archiveSha256'],x['archiveBytes']);h=hashlib.sha256();n=0
 with gzip.open(ROOT/x['archive'],'rb') as f:
  while chunk:=f.read(1048576):n+=len(chunk);h.update(chunk)
 assert n==x['sourceBytes'] and h.hexdigest()==x['sourceSha256'];archives.append({'archive':x['archive'],'rawBytes':n,'rawSha256':h.hexdigest()})
libs=js(M+'evidence/xcode-linked-library-binaries.json');tar_count=0;tar_alias_gaps=[]
for item in libs['items']:
 if not item.get('available'):continue
 check(item['archive'],item['archiveSha256'],item['archiveBytes'])
 with tarfile.open(ROOT/item['archive']) as t:
  members={x.name:x for x in t.getmembers() if x.isfile()}
  for x in item['files']:
   if x['relativePath'] not in members:
    tar_alias_gaps.append({'archive':item['archive'],'relativePath':x['relativePath'],'reason':'Descriptor path is symlink with absent Versions/Current target in tar; not reconstructable as named.'});continue
   q=members[x['relativePath']];data=t.extractfile(q).read();assert len(data)==x['bytes'] and sha(data)==x['sha256'];tar_count+=1
  assert set(members).issubset({x['relativePath'] for x in item['files']})
link_mismatch=[]
for x in em['dynamicLinkage']:
 actual=sha(read(x['capture']))
 if actual!=x['stdoutSha256']:link_mismatch.append({'variant':x['variant'],'capture':x['capture'],'declaredStdoutSha256':x['stdoutSha256'],'actualCaptureSha256':actual})
def result(text):
 started=re.findall(r"Test Case ['\"]([^'\"]+)['\"] started",text)
 failed=re.findall(r"Test Case ['\"]([^'\"]+)['\"] failed",text)
 passed=re.findall(r"Test Case ['\"]([^'\"]+)['\"] passed",text)
 assert len(started)==175 and len(set(started))==175 and len(passed)+len(failed)==175
 perf=re.findall(r'PERF 200-row commit medians \(ms\): typing ([\d.]+), scroll-only ([\d.]+), row edit ([\d.]+)',text);assert len(perf)==1
 errors=[x for x in text.splitlines() if 'XCTAssertLessThan failed:' in x]
 return {'methodsExecuted':len(started),'methodsPassed':len(passed),'methodsFailed':len(failed),'failedMethods':failed,'failedAssertions':len(errors),'assertions':errors,'medianMilliseconds':dict(zip(['typing','scrollOnly','rowEdit'],map(float,perf[0])))}
macresults={v:result(read(M+'evidence/'+v+'.stdout.bin').decode()) for v in variants}
mac={'schema':'copy-cost-macos-independent-review-v1','stageSha256':sha(read(M+'STAGE-MANIFEST.json')),'stageFilesVerified':len(ms['files']),'sourceBindingsPerVariant':52,'soleSourceDifference':diff,'sourceTestMethods':175,'internalDiskSourceCopiesVerified':True,'archives':archives,'linkedLibraryRegularFilesVerified':tar_count,'dynamicLinkageCaptureHashDisagreements':link_mismatch,'libraryArchiveAliasGaps':tar_alias_gaps,'results':macresults,'scope':'Single serial release pair; static otool dependencies & archived libraries do not prove runtime loaded-image paths. Mac XCTest runner child PID/path not captured independently of Swift driver. No causal regression or production promotion.'}
(OUT/'macos-review-v1/report.json').write_text(json.dumps(mac,indent=2)+'\n')
ws=stage(W+'execution/final-stage-manifest.json','f215b3f770bac234633f1cf5d4959a8dcd6786b1a52c5e1d746d741aed19ac71')
wr=js(W+'execution/results/receipt.json');assert [x['name'] for x in wr['variants']]==['current','candidate'];assert wr['error'] is None and wr['fullSuite'] is True
for v in wr['variants']:
 name=v['name'];binding={x['path']:{k:x[k] for k in ['path','bytes','sha256']} for x in v['sourceBindings']};assert binding=={x['path']:x for x in variants[name]['bindings']}
 assert v['sourceDrift'] is False and v['diagnosticMarker']=='no-diagnostic-marker'
 pr=js(W+'execution/results/'+name+'/process/process.json');assert pr==v['process']
 for stream in ['stdout','stderr']:check(W+'execution/results/'+name+'/process/'+stream+'.txt',pr[stream+'Hash'],pr[stream+'Bytes'])
 assert pr['argv']==v['command']['argv'] and pr['cwd']==v['runtimePath'] and pr['executableHash']==v['command']['executableHash']
 assert not pr['timedOut']
 for x in v['executables']:check(W+'execution/results/'+name+'/artifacts/'+x['path'].split('\\')[-1],x['sha256'],x['bytes'])
 runner=v['testRunner'][0]['path'];observed=pr['cimObserved'];assert any(x['executablePath'].lower()==runner.lower() and x['commandLine'].lower()==runner.lower() for x in observed)
assert wr['toolBindingsBefore']==wr['toolBindingsAfter']
def ticks(value):
 m=re.fullmatch(r'(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.(\d{1,7}))?(Z|[+-]\d\d:\d\d)',value);assert m
 d=datetime.datetime.fromisoformat(m[1]+m[3].replace('Z','+00:00'));delta=d.astimezone(datetime.timezone.utc)-datetime.datetime(1970,1,1,tzinfo=datetime.timezone.utc)
 return (delta.days*86400+delta.seconds)*10000000+int((m[2] or '').ljust(7,'0'))
assert ticks(wr['variants'][0]['process']['endedAt'])<ticks(wr['variants'][1]['process']['startedAt'])
samples=[json.loads(x) for x in read(W+'execution/results/factory-swiftright-copycost-observe-46e039abb746/samples.jsonl').decode('utf-8-sig').splitlines()]
clock=js(W+'execution/clock-context.stdout.bin');ambient={}
for v in wr['variants']:
 name=v['name'];text=read(W+'execution/results/'+name+'/process/stdout.txt').decode('utf-8-sig')
 local=re.search(r"Test Case 'PerformanceTests.testSingleRowEditCommitTime' started at ([\d\- :.]+)",text)[1].strip()
 dt=datetime.datetime.fromisoformat(local).replace(tzinfo=datetime.timezone(datetime.timedelta(minutes=clock['testDateOffsetMinutes']))).astimezone(datetime.timezone.utc);when=ticks(dt.isoformat())
 before=max((x for x in samples if ticks(x['utc'])<=when),key=lambda x:ticks(x['utc']));after=min((x for x in samples if ticks(x['utc'])>=when),key=lambda x:ticks(x['utc']))
 phase=[x for x in samples if ticks(v['process']['startedAt'])<=ticks(x['utc'])<=ticks(v['process']['endedAt'])]
 ambient[name]={'performanceStartUTC':dt.isoformat(),'timingStartBrackets':[{'utc':x['utc'],'externalCompilerCounts':dict(collections.Counter(y['name'] for y in x['processes'] if not y['ownedPair'] and y['name'].lower() in ['rustc.exe','link.exe','clang.exe','clang-cl.exe','cl.exe','lld-link.exe']))} for x in [before,after]],'phaseCPURange':[min(y['LoadPercentage'] for x in phase for y in x['processorLoad']),max(y['LoadPercentage'] for x in phase for y in x['processorLoad'])]}
winresults={v:result(read(W+'execution/results/'+v+'/process/stdout.txt').decode('utf-8-sig')) for v in variants}
combined={'schema':'copy-cost-two-host-independent-review-v1','windowsStageSha256':sha(read(W+'execution/final-stage-manifest.json')),'windowsFilesVerified':len(ws['files']),'sharedSourcePlanSha256':sha(read(M+'evidence/source-plan.json')),'same52SourceBindingsOnBothHosts':True,'macOS':macresults,'windows':winresults,'windowsAmbient':ambient,'macLibraryArchiveAliasGaps':tar_alias_gaps,'macDynamicLinkageCaptureHashDisagreements':link_mismatch,'limitations':['Mac static linkage capture metadata hashes disagree; frozen files themselves match stage hashes.','Mac runner/library runtime loaded-image identities not independently captured.','Windows runner CIM path/argv & archived EXE/DLL hashes join actual run; archived libraries alone do not prove loaded-image identity.','Serial one-pair observations, unlike host/compiler/storage & Dell ambient Rust activity prevent source-only causal attribution.'],'productionPromotion':False,'causalCertification':False,'nativeQualification':False}
(OUT/'combined-review-v1/report.json').write_text(json.dumps(combined,indent=2)+'\n')
print(json.dumps({'macMethods':macresults,'windowsMethods':winresults,'macStageFiles':21,'windowsStageFiles':len(ws['files']),'linkMismatches':link_mismatch},indent=2))
