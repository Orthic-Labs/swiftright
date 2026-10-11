from pathlib import Path
import json,hashlib,struct
R=Path('/Volumes/D/claude/swiftright');P=R/'factory/native/windows/padding-settled-capture-v4';A=P/'actual-single-r1';N=A/'native-01';O=P/'actual-single-review-v1';B=R/'factory/native/windows/padding-settled-build-v5/root-build-r1/actual'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def load(p):return json.loads(p.read_text(encoding='utf-8-sig'))
checks=0
for fn in ('fetch-coordinator-single-r1.json','fetch-actual-single-r1.json'):
 f=load(P/fn);assert f['scpExit']==0
 for rel,h in f['files'].items():assert sha(R/rel)==h;checks+=1
c=load(P/'coordinator-single-r1/coordinator.json');d=load(A/'dispatch.json');n=load(A/'native-observation.json');out=load(N/'capture-outcome.json');pixel=load(N/'native.pixels.json');owned=load(N/'owned-process.json');close=load(N/'owned-close.json')
assert c['count']==d['count']==1 and c['lockAcquired'] and c['lockReleased'] and c['wholeBatchExitConfirmed'] and c['terminalResultConfirmed']
assert not c['error'] and not c['cleanupErrors'] and not out['primaryError'] and not out['streamErrors']
for x in (c,d,n,out):assert x['compileReceiptHash']==sha(A/'observation.json')==sha(B/'observation.json')=='90f50b3fa049d4b21a0c5ad5eca78d8c024b961aa102fbc345767c151e503365'
for x in (c,d,out):assert x['exeHash']==sha(B/'FactoryProbe.exe')=='9ed4e7ed376cf2ad20879e99326291dcad31634156934e69d86094b2685fb5a4'
assert n['exeSha256']==c['exeHash'];assert c['serializerControlSha256']==sha(R/'factory/native/windows/padding-settled-build-v5/root-controls-r1/actual/serializer-control-actual-r2/control.json')=='952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
assert owned==out['ownedIdentity'] and out['lockOwner']==c['owner']
assert close['posted'] and not close['activationRequested'] and close['pid']==owned['pid']==pixel['pid']
assert close['hwnd']==pixel['hwnd']==1116140
assert out['cleanup']['confirmedOwnedExit'] and out['cleanup']['kernelExitSignaled'] and out['cleanup']['kernelWaitResult']==0
assert out['rawHashesQualification']=='sealed-raw'
for s in out['rawStreams']:assert s['sealed'] and s['destinationClosed'] and s['taskStatus']==s['closureTaskStatus']=='RanToCompletion'
for field,name in [('stdoutSha256','host.stdout.txt'),('stderrSha256','host.stderr.txt')]:assert sha(N/name)==out[field]
for row in n['files']:assert sha(N/row['path'])==row['sha256']
plan=load(A/'plan.json');assert sha(A/'plan.json')=='fe088dc1318e6ebc319c95ee169c2c91aa7e630fd19d81729389ebedb8397b20'
for row in plan['sourceBindings']:
 source=A/row['path'] if (A/row['path']).exists() else R/'factory/native/windows/padding-settled-build-v5/package'/row['path']
 assert sha(source)==row['sha256'].removeprefix('sha256:')
assert sha(R/'factory/native/windows/padding-settled-launch-preflight-v1/preflight.ps1')=='b54160b5902ced62c51b6f836f27a4ed40991dd8617e89fffc268105f81f6d9f'
for row in pixel['samples']:
 if 'path' in row:assert sha(N/row['path'])==row['sha256']
assert pixel['printWindowRepeatStable'] and pixel['screenRepeatStable'] and not pixel['methodsEqual'] and not pixel['controlledOcclusionQualification']
for filename in ('native.printwindow.png','native.printwindow.repeat.png','native.screen.png','native.screen.repeat.png'):
 raw=(N/filename).read_bytes();assert raw[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',raw[16:24])==(800,600)
uia=load(N/'native.uia.json');assert uia['children'][0]['name']=='Box' and uia['children'][0]['controlType']=='ControlType.Text'
text=(N/'host.stdout.txt').read_text();metrics=[json.loads(line.split(' ',1)[1]) for line in text.splitlines() if line.startswith('FACTORY_METRICS ')]
ready,layout,event,closed=metrics;assert ready['phase']=='onReady' and layout['record']=='first-layout' and event['phase']=='first-window-metrics-event' and closed['status']=='observed-actual-windowMetrics-event'
assert ready['monotonicNS']<layout['monotonicNS']<event['monotonicNS']<closed['monotonicNS']
assert not layout['windowMetricsEventSeen']
for m in metrics:assert m['pid']==owned['pid'] and m['hwnd']==pixel['hwnd']
assert ready['bridge']==event['bridge']=={'active':False,'heightPx':1396,'scale':2.5,'widthPx':800}
assert ready['ownedClient']==event['ownedClient']=={'dpi':240,'heightPx':600,'logicalHeight':240,'logicalWidth':320,'scale':2.5,'widthPx':800}
assert event['event']['i0']==800 and event['event']['i1']==600 and event['event']['x']==2.5
assert 'width: 320, height: 240' in (A/'Sources/FactoryProbe/main.swift').read_text()
assert 'hwnd=0x1107ec' in (N/'host.stderr.txt').read_text() and int('1107ec',16)==pixel['hwnd']
report={'verdict':'CLEAR_SINGLE_SOURCE_BOUND_OBSERVATION','fetchPinsVerified':checks,'findings':[],'lineage':{'compileReceiptSha256':c['compileReceiptHash'],'exeSha256':c['exeHash'],'serializerControlSha256':c['serializerControlSha256'],'planSha256':sha(A/'plan.json'),'launchGuardSha256':'b54160b5902ced62c51b6f836f27a4ed40991dd8617e89fffc268105f81f6d9f'},'metrics':metrics,'requestedDIP':[320,240],'rendererStartupStderrClientPx':[2560,1396],'interpretation':'Ready/event ABI readback800x1396 differs from owned client800x600; real event i0/i1 matches owned client. First layout precedes first real metrics event. Original dimensions preserved.','native':{'pid':owned['pid'],'hwnd':pixel['hwnd'],'uia':'Box Text child observed','pixelDimensions':[800,600],'printwindowRepeatStable':True,'screenRepeatStable':True,'methodsEqual':False,'foreground':[n['foregroundBeforeLaunch'],n['foregroundAfterWindow']],'foregroundUnchanged':False,'ownedExit':'Retained kernel signaled, two sealed/closed streams','lockReleased':True,'qualification':'Single observation only; no parity/provider or controlled occlusion qualification'},'execution':'Offline raw/hash Python review; no native/compiler/remote actions','inputPins':{str(p.relative_to(R)):sha(p) for p in [P/'fetch-actual-single-r1.json',P/'fetch-coordinator-single-r1.json',P/'coordinator-single-r1/coordinator.json',A/'native-observation.json',N/'capture-outcome.json',N/'host.stdout.txt',N/'host.stderr.txt',N/'native.pixels.json',N/'native.uia.json']}}
(O/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(sha(O/'report.json'))
