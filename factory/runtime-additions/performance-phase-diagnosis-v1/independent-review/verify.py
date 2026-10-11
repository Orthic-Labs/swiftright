import json,hashlib,gzip,re,statistics,struct,datetime,calendar,importlib.util,sys
from pathlib import Path
HERE=Path(__file__).resolve().parent;PACKET=HERE.parent;ROOT=PACKET.parents[2]
sha=lambda b:hashlib.sha256(b).hexdigest()
load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
pins={'analyze.py':'d53e623167d142323f09577daac7da104d56e16de9d97bceb7f109a0e5395bbe','diagnosis.json':'6a0f270470efb5acc30da5f0ea27bffe68672a45a5c57a5782c121a65b7b3533','README.md':'f52890170c3bb019e780a76d35dd1353d7b0a472900a81b494b36957d3c7f369','binary-archive-manifest.json':'4688f96c111d42e688b283f1bbce136483863a24d3a1deb65ac869bcafb6a1f7','root-stage-manifest.json':'2bb61520091d5182f261017004be171c48388cbc1bc98496de794f37b597e1a4','SHA256SUMS':'1588b8ef8c4a378d82df8c3d420e11581623db53907163cc59ea21a9443662f3'}
for path,digest in pins.items():assert sha((PACKET/path).read_bytes())==digest,path
manifest=load(PACKET/'root-stage-manifest.json');assert len(manifest['files'])==63
assert len({r['path'] for r in manifest['files']})==63
for row in manifest['files']:
    p=PACKET/row['path'];b=p.read_bytes();assert len(b)==row['bytes'] and sha(b)==row['sha256'],row['path']
c=load(PACKET/'config.json');r=load(PACKET/'captured-corrected/receipt.json');assert load(PACKET/'captured-corrected/config.json')==c
assert c['limitsMS']=={'typing':2,'scroll':4,'rowEdit':15}
diag=(PACKET/'PerformancePhaseDiagnosisTests.swift').read_bytes();assert sha(diag)==c['diagnosticHash']
source_joins=[]
for h,actual in zip(c['hosts'],r['hosts'],strict=True):
    assert h['label']==actual['label'] and h['commit']==actual['commit'] and h['bindings']==actual['sourceBindings']
    headless=ROOT/h['localReceipt'];assert sha(headless.read_bytes())==h['receiptHash']
    prior=load(headless);sr=load(headless.parent/'runtime-source-receipt.json');tree=load(headless.parent/'runtime-source-tree.json')
    assert prior['sourceCommit']==sr['sourceCommit']==h['commit']
    assert prior['sourceTreeHash']==sr['sourceTreeHash']
    assert [{'path':x['path'],'sha256':'sha256:'+x['sha256']} for x in h['bindings'] if x['path']=='Package.swift' or x['path'].startswith('Sources/')]==tree
    assert 'sha256:'+sha(json.dumps(tree,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode())==prior['sourceTreeHash']
    source=headless.parent/'runtime';observed={p.relative_to(source).as_posix() for part in ['Sources','Tests'] for p in (source/part).rglob('*.swift')}|{'Package.swift'}
    assert observed=={x['path'] for x in h['bindings']}
    for x in h['bindings']:
        b=(source/x['path']).read_bytes();assert sha(b)==x['sha256'] and len(b)==x['bytes']
    source_joins.append({'label':h['label'],'commit':h['commit'],'sourceFiles':len(h['bindings']),'sourceTreeHash':prior['sourceTreeHash'],'headlessReceiptSha256':h['receiptHash']})
def ticks(s):
    m=re.fullmatch(r'(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.(\d{7})Z',s);assert m,s
    base=datetime.datetime.fromisoformat(m[1]);return calendar.timegm(base.timetuple())*10000000+int(m[2])
runs=r['processRuns'];assert [x['name'] for x in runs]==['compiler-version','original-build','current-build','original-test','current-test']
for i,x in enumerate(runs):
    assert ticks(x['endedAt'])>ticks(x['startedAt'])
    if i:assert ticks(x['startedAt'])>ticks(runs[i-1]['endedAt'])
    assert x['returncode']==(0 if i<3 else 1) and x['timedOut'] is False
    assert x['createNoWindow'] is True
    folder=PACKET/'captured-corrected'/x['name'];assert load(folder/'process.json')==x
    for stream in ['stdout','stderr']:assert sha((folder/(stream+'.txt')).read_bytes())==x[stream+'Hash']
    roots=[a for a in x['cimOrigins'] if a['pid']==x['pid']]
    if i:assert len(roots)==1 and roots[0]['executablePath']==x['executable']
    else:assert roots==[] # Short --version process exited before first CIM sample.
    if i in (1,2):
        h=r['hosts'][i-1];assert x['cwd']==h['runtime']
        assert x['argv']==['build','--package-path',h['runtime'],'--scratch-path',h['runtime'].rsplit('\\',1)[0]+'\\scratch','-c','release','--build-tests','-Xswiftc','-enable-testing']
        assert any('-enable-testing' in (a['commandLine'] or '') and '-module-name SwiftRightRuntime ' in (a['commandLine'] or '') for a in x['cimOrigins'])
    if i>=3:
        h=r['hosts'][i-3];assert x['executable']==h['binary'] and x['executableHash']==h['binaryHash']
        assert x['argv']==['SwiftRightRuntimeTests.PerformancePhaseDiagnosisTests/testMatchedOriginalWorkload']
        assert all(argument in roots[0]['commandLine'] for argument in x['argv'])
compiler=ROOT/'factory/native/windows/module-origin-37429120-20261011/module-provenance-run-r4/compiler-input/swift.exe';assert sha(compiler.read_bytes())==c['compilerHash']
archives=load(PACKET/'binary-archive-manifest.json');assert {(x['label'],x['kind']) for x in archives['files']}=={(a,b) for a in ['original','current'] for b in ['runner','testLibrary']}
for x in archives['files']:
    b=(PACKET/x['archive']).read_bytes();assert sha(b)==x['archiveSha256'] and len(b)==x['archiveBytes'];raw=gzip.decompress(b);assert sha(raw)==x['sha256'] and len(raw)==x['bytes']
    assert raw[:2]==b'MZ';off=struct.unpack_from('<I',raw,0x3c)[0];assert raw[off:off+4]==b'PE\0\0' and struct.unpack_from('<H',raw,off+4)[0]==0x8664
    host=next(a for a in r['hosts'] if a['label']==x['label']);assert x['sha256']==host['binaryHash' if x['kind']=='runner' else 'dllHash']
payloads=[];stats=[]
for label in ['original','current']:
    text=(PACKET/'captured-corrected'/(label+'-test')/'stdout.txt').read_text();lines=[a[len('PHASE_DIAG '):] for a in text.splitlines() if a.startswith('PHASE_DIAG ')];assert len(lines)==1
    p=json.loads(lines[0]);assert p==load(PACKET/'captured-corrected'/(label+'-phase.json'))
    assert p['optimized'] is True and p['rowCount']==200 and p['runs']==25 and p['warmup']==5 and len(p['observations'])==90
    assert p['limitsMS']==c['limitsMS'];assert 'Executed 1 test, with 2 failures (0 unexpected)' in text
    for w in ['typing','scroll','rowEdit']:
        xs=[a for a in p['observations'] if a['workload']==w];assert [a['sample'] for a in xs]==list(range(30));assert [a['warmup'] for a in xs]==[True]*5+[False]*25
        for a in xs:assert all(type(a[k]) is int and a[k]>=0 for k in a if k not in ['workload','warmup'])
        assert statistics.median(a['wallNS'] for a in xs[5:])/1e6==p['mediansMS'][w]
    payloads.append(p)
for w in ['typing','scroll','rowEdit']:
    xs=[[a for a in p['observations'] if a['workload']==w and not a['warmup']] for p in payloads]
    counters=['evaluations','measurements','flushes','commits','liveNodes','resolvedNodes']
    assert all(all(a[k]==b[k] for k in counters) for a,b in zip(*xs,strict=True))
    stats.append({'workload':w,'originalMS':payloads[0]['mediansMS'][w],'currentMS':payloads[1]['mediansMS'][w],'matchedCounters':{k:sorted({a[k] for a in xs[0]}) for k in counters}})
failed=load(PACKET/'captured/receipt.json');assert not any(a['name'].endswith('-test') for a in failed['processRuns']);assert failed['error']
assert 'module' in (PACKET/'captured/original-build/stdout.txt').read_text().lower()+(PACKET/'captured/original-build/stderr.txt').read_text().lower()
report={'status':'CLEAR-observational-evidence','producerPins':pins,'stageFilesVerified':63,'sourceJoins':source_joins,'processRuns':5,'strictUTC100nsProcessOrdering':True,'cimPIDPathArgvJoins':True,'cimTimestampScope':'original locale/unzoned second precision retained; no exact UTC conversion inferred','actualCompilerByteJoin':True,'actualRunnerDLLArchivesVerified':4,'phaseSamplesPerRuntime':90,'totalSamples':180,'retainedSamplesPerRuntime':75,'initialFailedCompilePreserved':True,'nativeSamplingReruns':0,'results':stats,'interpretation':['Original workload mutation indices0..29, rowcount200, root960x640, scale2.5 &limits2/4/15 unchanged.','Resetting profile &reading measurement counts precede wall timer; dictionary collection follows wall timer; JSONserialization follows allloops.','Both diagnostic builds add runtime-enable-testing; thresholds still fail typing/scroll on both. This envelope cannot establish original uninstrumented binary timings.','Phase timers cover emit resolution only. ids(ofKind:) performs extra scroll snapshot outside resolveNS.','resolvedNodes0 is uninstrumented; sinkNS is nil-sink/bookkeeping/lifetime envelope, not renderer cost.','Matched observed evaluation/measurement counts &increased current layout/emit-resolution timings support phase concentration; fixed sequentialorder/environment &timer/lifetime placement prevent causal feature-regression attribution.']}
(HERE/'independent-clearance.json').write_text(json.dumps(report,indent=2)+'\n');print('verified63file pins, sourceclosure/process/exejoins &180actualsamples')
