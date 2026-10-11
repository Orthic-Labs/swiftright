from pathlib import Path
import json,hashlib,re,datetime,gzip
H=Path(__file__).resolve().parent
sha=lambda b:hashlib.sha256(b).hexdigest()
load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
plan=load(H/'packet/source-plan.json');receipt=load(H/'results/receipt.json')
assert receipt['error'] is None and len(receipt['variants'])==3
assert [x['name'] for x in receipt['variants']]==['original','retained','terminal']
assert [x['process']['exitCode'] for x in receipt['variants']]==[1,0,0]
last=None;out=[]
for v,expected in zip(receipt['variants'],plan['variants']):
 assert not v['sourceDrift'] and not v['process']['timedOut']
 assert v['command']['argv']==['test','--package-path',v['runtimePath'],'--scratch-path',v['scratchPath'],'-c','release','--filter',plan['commonPins']['filter']]
 assert sorted([{k:b[k] for k in ('path','bytes','sha256')} for b in v['sourceBindings']],key=lambda b:b['path'])==sorted(expected['bindings'],key=lambda b:b['path'])
 d=H/'results'/v['name'];p=load(d/'process/process.json');assert p==v['process']
 for stream in ('stdout','stderr'):
  raw=(d/'process'/(stream+'.txt')).read_bytes();assert len(raw)==p[stream+'Bytes'] and sha(raw)==p[stream+'Hash']
 text=(d/'process/stdout.txt').read_text()
 assert len(re.findall(r"Test Case 'TaskIDTests.testSameIdDoesNotRestartTask' started",text))==1
 assert ('Executed 1 test, with 1 failure' if v['name']=='original' else 'Executed 1 test, with 0 failures') in text
 if v['name']=='original':assert 'XCTAssertEqual failed: ("[]") is not equal to ("["a"]")' in text
 else:assert 'commit=true a' in text and 'results=["a"]' in text
 if v['name']=='terminal':assert 'terminal=true' in text
 b=v['testRunner'][0];raw=(d/'test-runner-0.exe').read_bytes();assert len(raw)==b['bytes'] and sha(raw)==b['sha256']
 start=datetime.datetime.fromisoformat(p['startedAt'].replace('Z','+00:00'));end=datetime.datetime.fromisoformat(p['endedAt'].replace('Z','+00:00'))
 assert start<end and (last is None or last<=start);last=end
 out.append(dict(name=v['name'],exitCode=p['exitCode'],startedAt=p['startedAt'],endedAt=p['endedAt'],testInvocations=1,sourceFiles=len(v['sourceBindings']),sourceDrift=False,runnerSha256=b['sha256'],stdoutSha256=p['stdoutHash'],stderrSha256=p['stderrHash'],diagnosticMarker=v['diagnosticMarker']))
for n in ('swift','swiftc'):
 raw=(H/'results'/(n+'.exe')).read_bytes();assert sha(raw)==receipt['toolchain'][n+'Hash']
archive=H/'native-artifact-archive.json'
if archive.exists():
 for b in load(archive)['files']:
  rawPath=H/b['localPath']
  raw=rawPath.read_bytes() if rawPath.exists() else None
  if raw is not None:assert len(raw)==b['bytes'] and sha(raw)==b['sha256']
  if b['chunks']:
   rebuilt=[]
   for c in b['chunks']:
    data=(H/c['path']).read_bytes();assert len(data)==c['bytes'] and sha(data)==c['sha256'];part=gzip.decompress(data);assert len(part)==c['rawBytes'] and sha(part)==c['rawSha256'];rebuilt.append(part)
   whole=b''.join(rebuilt);assert len(whole)==b['bytes'] and sha(whole)==b['sha256']
   if raw is not None:assert whole==raw
  else:assert raw is not None
result=dict(schema='taskid-direct-scp-verified-capture-v1',status='actual-three-focused-observations',sourcePlanSha256=sha((H/'packet/source-plan.json').read_bytes()),runnerSha256=sha((H/'packet/run-three-variants.ps1').read_bytes()),receiptSha256=sha((H/'results/receipt.json').read_bytes()),variants=out,bodyMilliseconds=40,settleMilliseconds=120,terminalVariant='diagnostic-only',causalCertification=False,retries=0,protectedSourceEdits=0)
(H/'verified-capture.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
