from pathlib import Path
import json,hashlib,struct,re
ROOT=Path(__file__).resolve().parents[5]
BASE=ROOT/'factory/native/windows/round1-stack-layout-native-v1'
HOST=ROOT/'factory/native/windows/round1-stack-layout-hosts-v1'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
transfer=load(BASE/'root-output-scp.json')
assert all(x['exitCode']==0 for x in transfer['processes'])
for r in transfer['files']:
 p=BASE/r['path'];assert sha(p)==r['sha256'] and p.stat().st_size==r['bytes']
results=[]
for name in ['stack-overlay','custom-layout']:
 p=BASE/('actual-'+name+'-r1');build=HOST/'build-actual-r1'/name
 plan=load(p/'plan.json');c=load(p/'observation.json');cfg=load(p/'config.json');d=load(p/'dispatch.json');proc=load(p/'native-01/owned-process.json')
 assert (p/'observation.json').read_bytes()==(build/'observation.json').read_bytes()
 assert sha(p/'plan.json')==c['planSha256'] and cfg['compileReceiptHash']==sha(p/'observation.json') and cfg['exeHash']==c['exeSha256']
 assert c['exitCode']==0 and c['ownedExited'] and not c['timedOut']
 for r in c['files']:assert sha(build/r['path'])==r['sha256']
 exe=(build/'FactoryProbe.exe').read_bytes();pe=struct.unpack_from('<I',exe,60)[0];assert exe[pe:pe+4]==b'PE\0\0' and struct.unpack_from('<H',exe,pe+24+68)[0]==2
 expected={r['path'] for r in plan['sourceBindings'] if r['path']=='Package.swift' or r['path'].startswith('Sources/')}
 actual={'Package.swift'}|{str(q.relative_to(p)) for q in (p/'Sources').rglob('*') if q.is_file()};assert actual==expected
 for r in plan['sourceBindings']:
  q=p/r['path'] if r['path']!='witness.manifest.json' else HOST/name/'package'/r['path']
  assert sha(q)==r['sha256'].removeprefix('sha256:')
 assert plan['sourceHash']==c['sourceHash']=='sha256:'+sha(p/'Sources/FactoryProbe/Witness.swift')
 assert plan['runtimeSourceCommit']==c['runtimeSourceCommit']=='37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'
 assert plan['rendererSha256']==c['rendererSha256']=='e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'
 assert c['runtimeSourceTreeHash']==plan['runtimeSourceTreeHash']=='sha256:'+sha(p/'runtime-source-tree.json')
 assert plan['runtimeSourceReceiptHash']=='sha256:'+sha(p/'runtime-source-receipt.json')
 assert cfg['owner']==d['owner'] and d['lockAcquired'] and d['lockReleased']
 assert proc['path']==c['exePath']
 stdout=(p/'native-01/host.stdout.txt').read_text();stderr=(p/'native-01/host.stderr.txt').read_text()
 ready=re.search(r'FACTORY_RENDERER_READY scale=([\d.]+) width=(\d+) height=(\d+) hwnd=(\d+) pid=(\d+)',stdout);assert ready and int(ready[5])==proc['pid']
 rawhwnd=int(re.search(r'window hwnd=0x([0-9a-f]+)',stderr)[1],16);assert rawhwnd==int(ready[4])
 facts={'host':name,'compileReceiptSha256':sha(p/'observation.json'),'exeSha256':c['exeSha256'],'pid':proc['pid'],'hwnd':rawhwnd,'case':plan['case'],'dispatchStatus':d['status'],'rawABI':'width=800 height=1396 scale=2.5','actualOwnedClient':[int(ready[2]),int(ready[3])],'sourceFiles':len(actual)}
 if name=='stack-overlay':
  assert d['status']=='hold-harness-error' and 'Overlay' in stdout and 'FACTORY_RENDER_ERROR' in stdout
  assert not (p/'native-observation.json').exists() and not (p/'native-01/native.uia.json').exists()
  facts['verdict']='Failed before capture: unsupported Overlay; no UIA/PW result'
 else:
  n=load(p/'native-observation.json');px=load(p/'native-01/native.pixels.json');ui=load(p/'native-01/native.uia.json')
  assert n['case']==plan['case'] and n['exeSha256']==c['exeSha256'] and n['compileReceiptHash']==sha(p/'observation.json') and n['hostValid'] and n['exitCode']==0
  for r in n['files']:assert sha(p/'native-01'/r['path'])==r['sha256']
  for r in px['samples']:
   if 'sha256' in r:assert sha(p/'native-01'/r['path'])==r['sha256']
  assert px['pid']==proc['pid'] and px['hwnd']==rawhwnd and px['width']==800 and px['height']==600 and px['dpi']==240
  assert px['printWindowRepeatStable'] and px['screenRepeatStable'] and not px['methodsEqual']
  assert ui['children']==[] and n['nativeParity']=='hold' and not n['frozenTupleBound'] and n['closureBinding'] is None
  facts.update(verdict='Single observational capture; empty UIA child inventory',foreground=[n['foregroundBeforeLaunch'],n['foregroundAfterWindow']],printWindowSha256=sha(p/'native-01/native.printwindow.png'),UIAChildren=0)
 results.append(facts)
print(json.dumps({'transferFilesVerified':len(transfer['files']),'results':results},indent=2))
