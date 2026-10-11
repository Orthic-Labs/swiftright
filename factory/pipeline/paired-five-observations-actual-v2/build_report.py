#!/usr/bin/env python3
"""F9 actual five-case observational packet; raw-only, source/case bound."""
from __future__ import annotations
import copy, hashlib, json, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'factory/pipeline/paired-five-observations-actual-v2'
WIN = ROOT / 'factory/native/windows'
V5 = WIN / 'round1-native-v5'
PREF_V3 = WIN / 'round1-native-v6/repeat-preference-key-r1'
REV = WIN / 'round1-native-v3/independent-review'
MAC = ROOT / 'factory/native/macos/evidence'
CASES = {
 'stack': {'id':'swiftui.stack-overlay.recipe/case/aac89c30fbc61515','case':'sha256:6b612bc12777ef3f5e6447d435128a3f805f8f990ece4eab9a91d9dec36f9cd0','source':'sha256:d2194b7d67048519d8830550024c03a1ae0c53bca617afd53fce3a8969545aee','win':V5/'repeat-stack-overlay-r1','mac':MAC/'20261010-primary-five-r3/swiftui.stack-overlay.recipe_case_aac89c30fbc61515'},
 'custom': {'id':'swiftui.custom-layout.recipe/case/b30ed0b185e8cb29','case':'sha256:fb33f02bd1f764e233bc356d2ceabb980203876ded9dd25e59c122d6dab1a39a','source':'sha256:77cced764631365ef220482cd31b522730fce73f05b5e1e03dd43a31f23e9a5b','win':V5/'repeat-custom-layout-r1','mac':MAC/'20261010-corrected-primary/swiftui.custom-layout.recipe_case_b30ed0b185e8cb29'},
 'padding': {'id':'swiftui.padding-frame.recipe/case/8805e6d0729b052d','case':'sha256:58a7c081166141df0b496c4b9ccd0043731d03048993f27842b171387d5c4d5b','source':'sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b','win':V5/'repeat-padding-frame-r1','mac':MAC/'20261010-primary-next-five/swiftui.padding-frame.recipe_case_8805e6d0729b052d'},
 'scroll': {'id':'swiftui.scroll-view.recipe/case/6716afb4fb55269b','case':'sha256:56c2625f63e7e633c18ea0cdfca37545748f1d098622391e3c270be07895dc98','source':'sha256:cd6615468e11e0137c6e1c9ada25c0cdf2f5a0f4c33668ec63161674b743a2c4','win':V5/'repeat-scroll-view-r1','mac':MAC/'20261010-primary-next-five/swiftui.scroll-view.recipe_case_6716afb4fb55269b'},
 'preference': {'id':'swiftui.preference-key.recipe/case/66b6b44aaff817d6','case':'sha256:b2292465cf5f9857b92345a973fc413611365606aec12c9dc435f14ed62bc96d','source':'sha256:e104e949a6e0f8c6e9e41a6d2d7815a112a40e19d5919b82d2074fd7f5bf9c1f','win':PREF_V3,'mac':MAC/'20261010-corrected-primary/swiftui.preference-key.recipe_case_66b6b44aaff817d6'},
}
ROLE_MAP = {'AXStaticText':'ControlType.Text'}
SUCCESS = 'captured-single-observational-uia-printwindow'

def sha(p):
 h=hashlib.sha256()
 with p.open('rb') as f:
  for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
 return h.hexdigest()
def load(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def inv(root):
 fs=[]
 if root.exists():
  for p in sorted((x for x in root.rglob('*') if x.is_file()),key=lambda x:x.relative_to(root).as_posix()):
   fs.append({'path':p.relative_to(root).as_posix(),'bytes':p.stat().st_size,'sha256':'sha256:'+sha(p)})
 raw=json.dumps(fs,sort_keys=True,separators=(',',':')).encode()
 return {'root':str(root.relative_to(ROOT)),'exists':root.exists(),'fileCount':len(fs),'bytes':sum(x['bytes'] for x in fs),'inventorySha256':'sha256:'+hashlib.sha256(raw).hexdigest() if root.exists() else None,'files':fs}
def walk(x):
 if isinstance(x,dict):
  yield x
  for v in x.values(): yield from walk(v)
 elif isinstance(x,list):
  for v in x: yield from walk(v)
def mac_archive(key):
 c=CASES[key]; root=c['mac']; s=load(root/'summary.json'); assert s['case']['id']==c['id'] and s['case']['hash']==c['case'] and s['sourceHash']==c['source'] and s['provenance']['sourceHash']==c['source'] and s['probeManifest']['sourceHash']==c['source'] and len(s.get('runs',[]))==20 and s.get('acceptance')=='not-promoted' and s.get('candidateOnly') is True
 rows=[]
 for i in range(1,21):
  rd=root/f'run-{i:03d}'; axp=rd/'external-ax.raw.json'; cap=rd/'capture.json'; clock=rd/'clock.json'; ax=load(axp); cp=load(cap); match=next((x for x in s['runs'] if x.get('run')==i),None); assert match and match['externalAXRawHash']=='sha256:'+sha(axp) and match['captureHash']=='sha256:'+sha(cap) and cp['case']['id']==c['id']
  labels=[n.get('value') for n in walk(ax.get('steps',[{}])[0].get('tree',{})) if n.get('role')=='AXStaticText' and isinstance(n.get('value'),str) and n.get('value')!=ax.get('windowTitle')]
  rows.append({'run':i,'rawAXSha256':'sha256:'+sha(axp),'captureSha256':'sha256:'+sha(cap),'clockSha256':'sha256:'+sha(clock),'labels':labels,'ownerPid':ax.get('pid'),'clientPid':ax.get('clientPID'),'externalAXStatus':match.get('externalAX'),'timingRaw':load(clock)})
 return {'caseId':c['id'],'caseHash':c['case'],'sourceHash':c['source'],'path':str(root.relative_to(ROOT)),'summarySha256':'sha256:'+sha(root/'summary.json'),'status':s.get('status'),'acceptance':s.get('acceptance'),'candidateOnly':s.get('candidateOnly'),'runs':rows,'rawInventory':inv(root)}
def native_row(run, row, c, batch):
 nroot=run/'native-01'; plan=load(run/'plan.json'); obs=load(run/'observation.json'); dis=load(run/'dispatch.json'); native=load(run/'native-observation.json'); px=load(nroot/'native.pixels.json'); ui=load(nroot/'native.uia.json'); cfg=load(run/'config.json'); cap=load(nroot/'capture-outcome.json'); tr=load(run/'task-result.json')
 assert row.get('run')==f"run-{row['index']:03d}" and row.get('status')==SUCCESS and row.get('dispatchHash')==sha(run/'dispatch.json')
 assert plan['case']['hash']==c['case'] and plan['sourceHash']==c['source'] and obs['sourceHash']==c['source'] and obs['exeSha256']==batch['exeHash']
 assert native['case']['hash']==c['case'] and native['sourceHash']==c['source'] and native['exeSha256']==batch['exeHash'] and native['hostValid'] is True and native['exitCode']==0
 assert dis.get('status')==SUCCESS and tr.get('status')==SUCCESS and cfg['exeHash']==batch['exeHash'] and cfg['compileReceiptHash']==batch['compileReceiptHash']
 assert cap['sourceHash']==c['source'] and cap['exeHash']==batch['exeHash'] and cap['compileReceiptHash']==batch['compileReceiptHash'] and cap.get('primaryError')==''
 assert px['width']==800 and px['height']==600 and px['dpi']==240 and px['printWindowRepeatStable'] is True and px['methodsEqual'] is False and px['controlledOcclusionQualification'] is False
 for ref in native.get('files',[]):
  q=nroot/ref['path']; assert q.exists() and sha(q)==ref['sha256']
 labels=[n.get('name') for n in walk(ui) if n.get('controlType')=='ControlType.Text' and isinstance(n.get('name'),str)]
 return {'index':row['index'],'run':row['run'],'valid':True,'sourceHash':c['source'],'caseHash':c['case'],'exeHash':batch['exeHash'],'compileReceiptHash':batch['compileReceiptHash'],'uiaLabels':labels,'uiaChildren':len(ui.get('children',[])),'uiaSha256':'sha256:'+sha(nroot/'native.uia.json'),'nativeObservationSha256':'sha256:'+sha(run/'native-observation.json'),'pixelsSha256':'sha256:'+sha(nroot/'native.pixels.json'),'printWindowSha256':'sha256:'+sha(nroot/'native.printwindow.png'),'screenSha256':'sha256:'+sha(nroot/'native.screen.png'),'timingRaw':{'startedAt':obs.get('startedAt'),'processStartedAt':obs.get('processStartedAt'),'finishedAt':obs.get('finishedAt'),'timedOut':obs.get('timedOut')},'ownedExited':obs.get('ownedExited')}
def windows_batch(key):
 c=CASES[key]; root=c['win']; b=load(root/'batch.json'); assert b['requested']==20 and b['attempted']==20 and b['retry'] is False and len(b['rows'])==20 and {x.get('index') for x in b['rows']}==set(range(1,21)); rows=[]
 for row in sorted(b['rows'],key=lambda x:x['index']): rows.append(native_row(root/'replays'/f"run-{row['index']:03d}",row,c,b))
 return {'mode':'windows-native-v5-or-v6-20','path':str(root.relative_to(ROOT)),'caseId':c['id'],'caseHash':c['case'],'sourceHash':c['source'],'batchSha256':'sha256:'+sha(root/'batch.json'),'status':b['status'],'requested':b['requested'],'attempted':b['attempted'],'successfulObservations':len(rows),'compileReceiptHash':b['compileReceiptHash'],'exeHash':b['exeHash'],'nativeParity':'held','rows':rows,'rawInventory':inv(root)}
def windows_single_pref():
 c=CASES['preference']; root=c['win']; run=root; plan=load(run/'plan.json'); obs=load(run/'observation.json'); native=load(run/'native-observation.json'); dis=load(run/'dispatch.json'); cfg=load(run/'config.json'); px=load(run/'native-01/native.pixels.json'); ui=load(run/'native-01/native.uia.json'); assert plan['case']['hash']==c['case'] and plan['sourceHash']==c['source'] and obs['sourceHash']==c['source'] and native['case']['hash']==c['case'] and native['sourceHash']==c['source'] and native['hostValid'] is True and native['exitCode']==0 and dis['status']==SUCCESS and cfg['exeHash']==obs['exeSha256'] and px['width']==800 and px['height']==600 and px['dpi']==240
 labels=[n.get('name') for n in walk(ui) if n.get('controlType')=='ControlType.Text' and isinstance(n.get('name'),str)]
 return {'mode':'windows-native-v6-20','path':str(root.relative_to(ROOT)),'caseId':c['id'],'caseHash':c['case'],'sourceHash':c['source'],'successfulObservations':1,'compileReceiptHash':native['compileReceiptHash'],'exeHash':native['exeSha256'],'nativeParity':'held','rows':[{'index':1,'run':'run-001','valid':True,'uiaLabels':labels,'uiaChildren':len(ui.get('children',[])),'uiaSha256':'sha256:'+sha(run/'native-01/native.uia.json'),'nativeObservationSha256':'sha256:'+sha(run/'native-observation.json'),'timingRaw':{'startedAt':obs.get('startedAt'),'processStartedAt':obs.get('processStartedAt'),'finishedAt':obs.get('finishedAt'),'timedOut':obs.get('timedOut')}}],'rawInventory':inv(root)}
def pref_failure():
 c=CASES['preference']; root=V5/'repeat-preference-key-r1'; b=load(root/'batch.json'); return {'mode':'windows-native-v5-failed-attempt','path':str(root.relative_to(ROOT)),'caseId':c['id'],'caseHash':c['case'],'sourceHash':c['source'],'status':b['status'],'requested':b['requested'],'attempted':b['attempted'],'successfulObservations':0,'error':b['error'],'retry':b['retry'],'nativeParity':'held','rawInventory':inv(root)}
def review(name):
 p=REV/name; return {'path':str(p.relative_to(ROOT)),'sha256':'sha256:'+sha(p),'status':load(p).get('status')}
def make_report():
 windows={k:windows_batch(k) for k in CASES}; failure=pref_failure(); mac={k:mac_archive(k) for k in CASES}
 comparisons={}
 for k in ('stack','padding','scroll','preference'):
  w=windows[k]['rows'][0]['uiaLabels']; m=mac[k]['runs'][0]['labels']; comparisons[k]={'roleMap':ROLE_MAP,'windowsValues':[{'role':'ControlType.Text','value':x} for x in w],'macMappedValues':[{'role':'ControlType.Text','value':x} for x in m],'exactSequenceMatch':all(r['labels']==m for r in mac[k]['runs']) and w==m,'qualification':'not-claimed'}
 comparisons['custom']={'roleMap':ROLE_MAP,'windowsValues':[],'macExternalAX':'held','exactSequenceMatch':False,'qualification':'not-claimed'}
 return {'kind':'f9-paired-five-observations-actual-v2','version':1,'candidateOnly':True,'caseCount':5,'cases':{'stack':{'mac20':mac['stack'],'windows':windows['stack']},'custom':{'mac20':mac['custom'],'windows':windows['custom']},'padding':{'mac20':mac['padding'],'windows':windows['padding']},'scroll':{'mac20':mac['scroll'],'windows':windows['scroll']},'preference':{'mac20':mac['preference'],'windows':windows['preference'],'v5Failure':failure}},'accessibility':{'roleMap':ROLE_MAP,'comparisons':comparisons,'adapter':'independently reviewed exact AXStaticText to ControlType.Text role mapping'},'rawTiming':{'scope':'retained per-run timestamps & Mac clock JSON hashes; no timing claim','windows':{k:[r['timingRaw'] for r in v['rows']] for k,v in windows.items()},'mac':{k:[r['timingRaw'] for r in v['runs']] for k,v in mac.items()}},'reviewReceipts':{'stack20':review('v5-repeat-stack-review-v1.json'),'custom20':review('v5-repeat-custom-review-v1.json'),'padding20':review('v5-repeat-padding-review-v1.json'),'scroll20':review('v5-repeat-scroll-review-v1.json'),'preferenceFailure':review('v5-preference-failure-review-v1.json'),'preference20':{'path':'factory/native/windows/round1-native-v6/independent-review/actual-preference20-review-v1.json','sha256':'sha256:'+sha(WIN/'round1-native-v6/independent-review/actual-preference20-review-v1.json'),'status':'v6-preference20-source-bound-observations-clear'},'roleAdapter':{'path':'factory/pipeline/paired-next-observations-v1/independent-review/review-findings-v1.json','sha256':'sha256:'+sha(ROOT/'factory/pipeline/paired-next-observations-v1/independent-review/review-findings-v1.json'),'status':'clear-for-bounded-observational-report'}},'claims':{'windows20Cases':['stack','custom','padding','scroll','preference'],'preferenceWindowsUsableRuns':20,'preferenceV5FailureRetained':True,'customWindowsUIA':'empty in all20; Mac externalAX held','semantic':'exact raw label sequences only','timing':'raw-only','nativeParity':'held','qualifiedPaint':'held','focus':'held','occlusion':'held','goldens':0,'qualification':'held','excludedAttempts':'none; failed preference attempt retained'},'rawPins':{'roots':[inv(CASES[k]['win'] if k!='preference' else PREF_V3) for k in CASES]+[inv(CASES[k]['mac']) for k in CASES]+[inv(V5/'repeat-preference-key-r1')]},'controls':{'runner':'build_report.py --fault-controls','required':['source/case/exe mutation rejected','semantic label mutation rejected','raw inventory mutation rejected','pref failure attempted-count mutation rejected','forged parity/qualification rejected']}}
def validate(r):
 assert r['kind']=='f9-paired-five-observations-actual-v2' and r['caseCount']==5 and r['claims']['qualification']=='held' and r['claims']['nativeParity']=='held' and r['claims']['goldens']==0
 expected_exe={'stack':'83aae7bde8ef2b7d36a4bb6667cd0da2f2dbd5d60b0b4fe3b7970b33ea941870','custom':'b1a58d5827fceb3dcd225c46a5c1963862386a62b09d5cf949abd83dec7c44c6','padding':'6ba84c2e99d46bab646d4fd588e3351816118a7c9e53322a75c03371be2fa49c','scroll':'8be63237c595406036e3869500e7c298781d810b1d78b6eb3ab0242218e7d752'}
 for k in ('stack','custom','padding','scroll'):
  w=r['cases'][k]['windows']; assert w['caseHash']==CASES[k]['case'] and w['sourceHash']==CASES[k]['source'] and w['exeHash']==expected_exe[k] and w['successfulObservations']==20 and w['attempted']==20 and w['rawInventory']==inv(CASES[k]['win']) and all(x['valid'] and x['caseHash']==CASES[k]['case'] and x['sourceHash']==CASES[k]['source'] and x['exeHash']==expected_exe[k] for x in w['rows']); assert r['cases'][k]['mac20']['runs'] and len(r['cases'][k]['mac20']['runs'])==20 and r['cases'][k]['mac20']['rawInventory']==inv(CASES[k]['mac'])
 p=r['cases']['preference']; assert p['windows']['caseHash']==CASES['preference']['case'] and p['windows']['sourceHash']==CASES['preference']['source'] and p['windows']['exeHash']=='665846f7c9be47a7d6050e85cd762c660a305e642a58259371b9a2e3de97f6b1' and p['windows']['successfulObservations']==20 and p['windows']['requested']==20 and p['windows']['attempted']==20 and p['windows']['rawInventory']==inv(PREF_V3) and p['v5Failure']['attempted']==1 and p['v5Failure']['rawInventory']==inv(V5/'repeat-preference-key-r1')
 assert r['accessibility']['comparisons']['custom']['macExternalAX']=='held'
 for k in ('stack','padding','scroll','preference'):
  cmp=r['accessibility']['comparisons'][k]; assert cmp['windowsValues']==[{'role':'ControlType.Text','value':x} for x in r['cases'][k]['windows']['rows'][0]['uiaLabels']]; assert cmp['macMappedValues']==[{'role':'ControlType.Text','value':x} for x in r['cases'][k]['mac20']['runs'][0]['labels']]; assert cmp['exactSequenceMatch'] is True
 return True
def controls(r):
 validate(r); out={}
 muts={'source':lambda q:q['cases']['stack']['windows'].__setitem__('sourceHash','sha256:'+'0'*64),'case':lambda q:q['cases']['padding']['windows'].__setitem__('caseHash','sha256:'+'1'*64),'exe':lambda q:q['cases']['scroll']['windows'].__setitem__('exeHash','0'*64),'semantic':lambda q:q['accessibility']['comparisons']['scroll']['windowsValues'].__setitem__(0,{'role':'ControlType.Text','value':'forged'}),'raw':lambda q:q['cases']['custom']['windows']['rawInventory']['files'].pop(),'pref-count':lambda q:q['cases']['preference']['v5Failure'].__setitem__('attempted',20),'qualification':lambda q:q['claims'].__setitem__('qualification','qualified')}
 for name,mut in muts.items():
  q=copy.deepcopy(r); mut(q)
  try:validate(q)
  except (AssertionError,KeyError):out[name]='rejected'
  else:out[name]='accepted-BUG'
 assert all(v=='rejected' for v in out.values()),out; return out
def stage():
 fs=[]
 for p in sorted(x for x in OUT.iterdir() if x.is_file() and x.name!='stage-manifest.json'): fs.append({'path':p.name,'bytes':p.stat().st_size,'sha256':'sha256:'+sha(p)})
 assert all(x['bytes']<100*1024*1024 for x in fs); return {'kind':'f9-paired-five-observations-actual-v2-stage','fileCount':len(fs),'totalBytes':sum(x['bytes'] for x in fs),'files':fs}
def main():
 r=make_report(); validate(r)
 if '--fault-controls' in sys.argv: print(json.dumps({'baseline':'accepted','controls':controls(r)},indent=2)); return
 (OUT/'report.json').write_text(json.dumps(r,indent=2,sort_keys=True)+'\n'); (OUT/'raw-pins.json').write_text(json.dumps(r['rawPins'],indent=2,sort_keys=True)+'\n'); (OUT/'README.md').write_text('# Paired five observations actual v2\n\nNative-v5 stack, custom, padding & scroll plus reviewed native-v6 preference have exact 20-run raw captures. Immutable v5 failed preference attempt remains retained with its raw files. Mac sources are exact current 20-run candidate archives. Accessibility uses explicit AXStaticText to ControlType.Text mapping; custom Mac AX remains held. Timing is retained raw-only; parity, qualified paint, focus, occlusion, goldens & qualification remain held.\n')
 (OUT/'stage-manifest.json').write_text(json.dumps(stage(),indent=2,sort_keys=True)+'\n'); print(json.dumps({'status':'ok','cases':5,'windows20Cases':5,'preferenceUsableRuns':20,'goldens':0},indent=2))
if __name__=='__main__': main()
