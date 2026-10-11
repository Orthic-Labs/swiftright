#!/usr/bin/env python3
import hashlib,json,re,sys
from pathlib import Path
from PIL import Image
ROOT=Path(__file__).resolve().parents[5];HERE=Path(__file__).resolve().parent;BASE=HERE.parent;RAW=BASE/'actual-first-r1';N=RAW/'native-01'
sys.path.insert(0,str(ROOT))
def pin(p):raw=p.read_bytes();return {'path':str(p.relative_to(ROOT)),'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
def obj(p):return json.loads(p.read_bytes().decode('utf-8-sig'))
def main():
 from factory.tools.canonical_json import sha256
 record=obj(RAW/'native-observation.json');assert isinstance(record,dict) and record['index']==1 and record['exitCode']==0 and record['hostValid'] is True
 for f in record['files']:assert pin(N/f['path'])['sha256']==f['sha256']
 plan=obj(RAW/'plan.json');compiled=obj(RAW/'observation.json');assert pin(RAW/'plan.json')['sha256']==compiled['planSha256'];assert compiled['exitCode']==0
 for b in plan['sourceBindings']:assert 'sha256:'+pin(RAW/b['path'])['sha256']==b['sha256']
 assert record['case']==plan['case'];assert record['sourceHash']==plan['sourceHash']==compiled['sourceHash'];assert record['exeSha256']==compiled['exeSha256'];assert record['rendererSha256']==plan['rendererSha256']==compiled['rendererSha256']
 cases_path=ROOT/'factory/pipeline/inputs/cases.json';cases=obj(cases_path);assert len(cases)==81;match=[c for c in cases if c['id']==plan['case']['id']];assert len(match)==1 and sha256(match[0])==plan['case']['hash'];assert match[0]['inputs']['disabled'] is False
 dispatch=obj(RAW/'dispatch.json');assert dispatch['status']=='captured-single-observational-uia-printwindow' and dispatch['lockAcquired'] and dispatch['lockReleased'];assert obj(RAW/'config.json')['owner']==dispatch['owner'];assert obj(RAW/'task-result.json')['error']=='';assert obj(RAW/'scheduled-task-receipt.json')['LastTaskResult']==0
 preflight=obj(BASE/'root-preflight.stdout.txt');preproc=obj(BASE/'root-preflight-process.json');launch=obj(BASE/'root-launch-process.json');assert preproc['exitCode']==launch['exitCode']==0
 for stem,receipt in [('root-preflight',preproc),('root-launch',launch)]:
  assert pin(BASE/(stem+'.stdout.txt'))['sha256']==receipt['stdoutSha256'];assert pin(BASE/(stem+'.stderr.txt'))['sha256']==receipt['stderrSha256']
 assert obj(BASE/'root-launch.stdout.txt')==dispatch
 for s in preflight['scripts']:
  local=BASE/Path(s['path'].replace('\\','/')).name;assert pin(local)['sha256']==s['sha256'] and s['parseErrors']==0
 remote={i['path']:i['sha256'] for i in preflight['inputs']};assert compiled['exeSha256']==remote[compiled['exePath']];assert plan['rendererSha256']==remote['D:\\Claude\\sr0-r09\\renderer\\swiftright_render.dll'];assert obj(BASE/'root-launch-start.json')['reviewedCaptureSha256']==pin(BASE/'capture-first.ps1')['sha256']
 owned=obj(N/'owned-process.json');pixels=obj(N/'native.pixels.json');window=obj(N/'launch-observation.json');stderr=(N/'host.stderr.txt').read_text();stdout=(N/'host.stdout.txt').read_text();hwnd=int(re.search(r'window hwnd=(0x[0-9a-f]+)',stderr)[1],16);assert hwnd==pixels['hwnd']==window['ownedWindow']==52562814;assert owned['pid']==pixels['pid']==33700 and owned['path']==compiled['exePath']
 assert 'FACTORY_BACKGROUND_GUARD thread-cbt-activation-veto' in stdout and 'FACTORY_RENDERER_READY' in stdout
 uia=obj(N/'native.uia.json');nodes=[]
 def walk(n):
  nodes.append(n)
  for ch in n.get('children',[]):walk(ch)
 walk(uia);buttons=[n for n in nodes if n['name']=='Continue' and n['controlType']=='ControlType.Button'];assert len(buttons)==1 and buttons[0]['enabled'] is True
 imagefacts=[]
 for s in pixels['samples']:
  if 'method' in s:
   p=N/s['path'];assert pin(p)['sha256']==s['sha256'];im=Image.open(p).convert('RGBA');colors=len(im.getcolors(im.width*im.height));assert im.size==(800,600) and colors>1;imagefacts.append({'file':pin(p),'method':s['method'],'repeat':s['repeat'],'width':im.width,'height':im.height,'uniqueRGBAColors':colors})
 assert pixels['printWindowRepeatStable'] and pixels['screenRepeatStable'] and not pixels['methodsEqual'];assert imagefacts[0]['uniqueRGBAColors']==42
 assert window['foregroundBefore']==record['foregroundBeforeLaunch']==395622 and window['foregroundAfter']==record['foregroundAfterWindow']==0 and not record['probeForegroundAtCapture']
 macbase=ROOT/'factory/native/macos/evidence/20261010-primary-next-five/swiftui.disabled.recipe_case_f113195a59446fc4';mac=obj(macbase/'summary.json');assert mac['case']==plan['case'] and mac['sourceHash']==plan['sourceHash'] and len(mac['runs'])==20
 macpins=[]
 for row in mac['runs']:
  p=macbase/('run-%03d'%row['run'])/'capture.json';assert 'sha256:'+pin(p)['sha256']==row['captureHash'];assert obj(p)['case']==plan['case'];macpins.append(pin(p))
 ready=re.search(r'FACTORY_RENDERER_READY scale=([\d.]+) width=(\d+) height=(\d+)',stdout);client=re.search(r'client=(\d+)x(\d+)px',stderr)
 assert [int(ready[2]),int(ready[3])]==[800,1396] and [int(client[1]),int(client[2])]==[2560,1396]
 report={'verdict':'VERIFIED-FIRST-SOURCE-BOUND-OBSERVATION-PARITY-HELD','reviewer':pin(Path(__file__)),'rawPacketFiles':[pin(p) for p in sorted(RAW.rglob('*')) if p.is_file()],'hashedNativeFilesVerified':len(record['files']),'requestAndReceipts':[pin(BASE/n) for n in ['root-preflight.stdout.txt','root-preflight-process.json','root-transfer-scp.json','root-launch-start.json','root-launch-process.json','root-launch.stdout.txt']],'scriptPins':preflight['scripts'],'sourceHash':plan['sourceHash'],'case':plan['case'],'caseInput':pin(cases_path),'caseDenominator':81,'exeSha256':compiled['exeSha256'],'rendererSha256':compiled['rendererSha256'],'ownedProcess':owned,'hwnd':hwnd,'uiaButton':buttons[0],'matchesDisabledFalse':True,'images':imagefacts,'printWindowRepeatStable':True,'screenRepeatStable':True,'PrintWindowEqualsScreen':False,'foreground':{'before':395622,'afterWindow':0,'ownedForegroundObserved':False,'unchangedForegroundClaim':False},'viewportObservations':{'rendererReady':[800,1396],'initialRendererClient':[2560,1396],'actualReadback':[800,600],'uiaRootBounds':uia['bounds'],'dpi':pixels['dpi'],'normalizationApplied':False,'mismatchHeld':True},'visualObservation':'PrintWindow shows Continu inside blue button with final e on next line outside button; nonblank/repeat stability does not establish correct text layout','macSameSource':{'summary':pin(macbase/'summary.json'),'runs':20,'capturePins':macpins},'remainingGaps':['Viewport/client metrics disagree with actual800x600 readback','Continue text visibly wraps outside button','One Windows replay vs20 Mac runs; no equal replay denominator','Natural occlusion grid/repeats do not certify controlled occluded readback or provider exports','No frozen tuple/closure binding or native semantic parity qualification'],'lockAcquired':True,'lockReleased':True,'nativeParity':'hold','frozenTupleBound':False,'closureBinding':None,'newNativeLaunches':0,'productionEdits':0}
 out=HERE/'actual-first-r1-verdict.json';out.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(pin(out)))
if __name__=='__main__':main()
