from pathlib import Path
import json,hashlib,struct,re
R=Path(__file__).resolve().parents[5];B=R/'factory/native/windows/round1-stack-layout-repair-capture-v1';P=B/'actual-stack-overlay-r1';H=R/'factory/native/windows/round1-stack-layout-repair-v1';D=H/'build-actual-r1'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
c=load(P/'observation.json');plan=load(P/'plan.json');n=load(P/'native-observation.json');px=load(P/'native-01/native.pixels.json');cfg=load(P/'config.json');dispatch=load(P/'dispatch.json');proc=load(P/'native-01/owned-process.json')
assert (D/'observation.json').read_bytes()==(P/'observation.json').read_bytes()
for r in c['files']:assert sha(D/r['path'])==r['sha256']
assert c['exitCode']==0 and c['ownedExited'] and not c['timedOut']
exe=(D/'FactoryProbe.exe').read_bytes();pe=struct.unpack_from('<I',exe,60)[0];assert exe[pe:pe+4]==b'PE\0\0' and struct.unpack_from('<H',exe,pe+24+68)[0]==2
assert sha(P/'plan.json')==c['planSha256']=='8c89995f6eb23939a365d068b0eb3c8d407194a5cf1f720b9bdc71f01066e1e2'
assert cfg['compileReceiptHash']==sha(P/'observation.json')==n['compileReceiptHash'] and cfg['exeHash']==c['exeSha256']==n['exeSha256']
expected={r['path'] for r in plan['sourceBindings'] if r['path']=='Package.swift' or r['path'].startswith('Sources/')};actual={'Package.swift'}|{str(p.relative_to(P)) for p in (P/'Sources').rglob('*') if p.is_file()};assert expected==actual
for r in plan['sourceBindings']:
 p=P/r['path'] if r['path']!='witness.manifest.json' else H/'stack-overlay/package'/r['path'];assert sha(p)==r['sha256'].removeprefix('sha256:')
for key in ['sourceHash','rendererSha256','runtimeSourceCommit','runtimeSourceTreeHash']:assert c[key]==plan[key]==n[key]
assert plan['runtimeSourceTreeHash']=='sha256:'+sha(P/'runtime-source-tree.json') and plan['runtimeSourceReceiptHash']=='sha256:'+sha(P/'runtime-source-receipt.json')
manifest=load(H/'stack-overlay/package/witness.manifest.json');assert n['case']==plan['case']==manifest['case']
assert proc['path']==c['exePath'] and px['pid']==proc['pid'];stdout=(P/'native-01/host.stdout.txt').read_text();stderr=(P/'native-01/host.stderr.txt').read_text();ready=re.search(r'FACTORY_RENDERER_READY scale=([\d.]+) width=(\d+) height=(\d+) hwnd=(\d+) pid=(\d+)',stdout);assert int(ready[4])==px['hwnd']==int(re.search(r'window hwnd=0x([0-9a-f]+)',stderr)[1],16) and int(ready[5])==proc['pid']
for r in n['files']:assert sha(P/'native-01'/r['path'])==r['sha256']
for r in px['samples']:
 if 'sha256' in r:assert sha(P/'native-01'/r['path'])==r['sha256']
assert dispatch['lockAcquired'] and dispatch['lockReleased'] and dispatch['owner']==cfg['owner'];assert dispatch['status']==load(P/'task-result.json')['status']=='captured-single-observational-uia-printwindow'
assert n['hostValid'] and n['exitCode']==0 and px['printWindowRepeatStable'] and not px['methodsEqual']
ui=load(P/'native-01/native.uia.json');assert len(ui['children'])==1 and ui['children'][0]['name']=='+'
for row in load(B/'root-parse-actual-r1.json')['rows']:
 p=R/row['path'].replace('D:\\Claude\\swiftright\\','').replace('\\','/');assert sha(p)==row['sha256'] and row['errors']==[]
s=load(H/'root-metadata-supplement-v1.json');assert sha(R/s['origin'])==sha(R/s['destination'])==s['sha256'] and s['compilerInvocationsBeforeRepair']==0
entry=load(B/'root-entry-disposition.json');assert entry['nativeLaunchesBeforeCorrection']==0 and sha(B/'root-dispatch.ps1')==entry['scriptHash']
print(json.dumps({'result':'PASS raw/source/build/native joins','compileReceipt':sha(P/'observation.json'),'exe':c['exeSha256'],'pid':proc['pid'],'hwnd':px['hwnd'],'case':plan['case'],'sourceFileCount':len(actual),'UIAChildren':1,'PrintWindow':sha(P/'native-01/native.printwindow.png'),'foreground':[n['foregroundBeforeLaunch'],n['foregroundAfterWindow']]},indent=2))
