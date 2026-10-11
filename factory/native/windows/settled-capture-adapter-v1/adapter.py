"""Reader-backed actual channels. No invented capture identity/provenance/tuple."""
from __future__ import annotations
import hashlib,json,math,re,struct,importlib.util
from pathlib import Path
_cspec=importlib.util.spec_from_file_location("settled_canonical",Path(__file__).resolve().parent/"dependencies/canonical_json.py")
_canonical=importlib.util.module_from_spec(_cspec);_cspec.loader.exec_module(_canonical)
from decimal import Decimal
from pathlib import PurePosixPath
from typing import Callable

def digest(raw):return 'sha256:'+hashlib.sha256(raw).hexdigest()
def integer(x):return type(x) is int

def parse(raw):
 def pairs(rows):
  d={}
  for k,v in rows:
   if k in d:raise ValueError('duplicate JSON key')
   d[k]=v
  return d
 def bad(x):raise ValueError('nonfinite JSON constant')
 return json.loads(raw.decode('utf-8-sig'),object_pairs_hook=pairs,parse_constant=bad)

def stream(s):
 c=s.get('closure') or {}
 return all(s.get(k) is True for k in ('copyCompleted','destinationClosed','sealed','taskIsCompleted')) and all(s.get(k) is False for k in ('taskIsFaulted','taskIsCanceled')) and s.get('taskStatus')=='RanToCompletion' and s.get('closureTaskStatus')=='RanToCompletion' and s.get('taskException')=='' and s.get('hashQualification')=='sealed-raw' and all(c.get(k) is True for k in ('flushCompleted','destinationClosed','completedWithinDeadline')) and c.get('deadlineExpired') is False and c.get('deadlineMilliseconds')==5000 and c.get('error')==''

def kernel(c,natural=False):
 return c.get('confirmedOwnedExit') is True and c.get('kernelExitSignaled') is True and integer(c.get('kernelWaitResult')) and c['kernelWaitResult']==0 and c.get('exitCertification')=='retained-kernel-handle' and (not natural or (c.get('status')=='already-signaled' and c.get('killAttempted') is False and c.get('error')==''))

def channels(uia,png,stdout):
 ax=[]
 def number(x):
  if type(x) not in (int,float) or not math.isfinite(x):raise ValueError('finite measured coordinates required')
  d=Decimal(str(x));return int(d) if d==d.to_integral_value() else {'$decimal':format(d.normalize(),'f')}
 def walk(n,loc='root',depth=0):
  if depth>40 or set(n)!=set(('name','automationId','controlType','enabled','patterns','offscreen','bounds','children')):raise ValueError('exact scalar UIA schema required')
  if any(type(n[k]) is not str for k in ('name','automationId','controlType')) or any(type(n[k]) is not bool for k in ('enabled','offscreen')):raise ValueError('UIA scalar type')
  if any(type(n[k]) is not list for k in ('patterns','bounds','children')) or len(n['bounds'])!=4 or len(n['children'])>1000 or any(type(p) is not str for p in n['patterns']):raise ValueError('UIA array type/bound')
  identity=n['automationId'] or loc
  ax.append({'identity':identity,'role':n['controlType'].removeprefix('ControlType.'),'label':n['name'],'value':{'isEnabled':n['enabled'],'isOffscreen':n['offscreen']},'actions':[action for pattern,action in [('InvokePatternIdentifiers.Pattern','invoke'),('TogglePatternIdentifiers.Pattern','toggle')] if pattern in n['patterns']],'bounds':dict(zip(('x','y','width','height'),map(number,n['bounds']))),'source':'external','children':[c.get('automationId') or f'{loc}/{i}' for i,c in enumerate(n['children'])]})
  for i,c in enumerate(n['children']):walk(c,f'{loc}/{i}',depth+1)
 walk(uia)
 if len(png)<24 or png[:8]!=b'\x89PNG\r\n\x1a\n':raise ValueError('PNG required')
 width,height=struct.unpack('>II',png[16:24])
 scale=re.search(rb'FACTORY_RENDERER_READY scale=([0-9.]+)',stdout)
 if not scale:raise ValueError('measured scale missing')
 return {'ax':ax,'printWindow':{'hash':digest(png),'widthPx':width,'heightPx':height,'captureScale':number(float(scale[1]))},'layout':[],'events':[],'anim':[],'text':[]}

def inspect(inputs:dict,read_bytes:Callable[[dict],bytes])->dict:
 """All refs explicit; reader receives safe paths & exact SHA, never receipt paths."""
 issues=[];consumed={};docs={};raws={};rows=[]
 def read(ref,label):
  if not isinstance(ref,dict) or set(ref)-{'path','sha256','bytes'} or not isinstance(ref.get('path'),str) or not re.fullmatch(r'sha256:[0-9a-f]{64}',str(ref.get('sha256'))):raise ValueError('missing/bad ref '+label)
  p=PurePosixPath(ref['path'])
  if p.is_absolute() or '..' in p.parts or '\\' in ref['path'] or ':' in ref['path'] or str(p)!=ref['path']:raise ValueError('unsafe ref '+label)
  raw=read_bytes(dict(ref))
  if type(raw) is not bytes or digest(raw)!=ref['sha256'] or ('bytes' in ref and (not integer(ref['bytes']) or len(raw)!=ref['bytes'])):raise ValueError('reader bytes/hash/size '+label)
  consumed[label]=ref;return raw
 def load(ref,label):return parse(read(ref,label))
 def check(v,message):
  if not v:raise ValueError(message)
 result={'kind':'settled-actual-channel-analysis-v1','canonicalCapture':None,'issues':issues,'rows':rows,'consumed':consumed,'qualified':False,'nativeParity':'hold'}
 try:
  batch=load(inputs.get('batch'),'batch');n=batch.get('requested')
  check(integer(n) and n in (1,20) and integer(batch.get('attempted')) and batch.get('attempted')==n and len(batch.get('rows',[]))==n and batch.get('status')==f'completed-{n}-observational' and batch.get('error')=='' and batch.get('retry') is False,'complete Count1/20 batch required')
  check(len(inputs.get('runs',[]))==n and [x.get('index') for x in batch['rows']]==list(range(1,n+1)),'complete ordered run bindings required')
  for i,bindings in enumerate(inputs['runs'],1):
   rowissues=[];row={'index':i,'availability':{'uia':'external-observation','printWindow':'window-targeted-observation','providerPaint':False,'layout':False,'events':False,'animation':False,'text':False,'occlusionQualified':False},'settled':False,'sourceJoined':False,'channels':None,'issues':rowissues};rows.append(row)
   try:
    def get(k):return load(bindings.get(k),f'run{i}:{k}')
    plan=get('plan');obs=get('observation');out=get('outcome');owned=get('owned');close=get('close');pixels=get('pixels');dispatch=get('dispatch');compile=get('compile');launch=get('launch')
    contract=get('driverContract')
    check(consumed[f'run{i}:driverContract']['sha256']=='sha256:'+batch.get('contractHash',''),'actual driver contract join')
    check(batch.get('contractHash')=='5285021869f6f21ee0013c434d1171a25830b6161f98b8ddcbed2fca5bc65861','missing reviewed capture driver profile for successor')
    hosts=[h for h in contract.get('hosts',[]) if h.get('label')==batch.get('case') and h.get('planHash')==consumed[f'run{i}:plan']['sha256'][7:]]
    check(len(hosts)==1,'exact case/plan driver admission join')
    for b in hosts[0]['bindings']:check(digest(read((bindings.get('driverSource') or {}).get(b['path']),f'run{i}:driver:{b["path"]}'))=='sha256:'+b['sha256'],'driver/helper/source raw join')
    check(dispatch.get('status')==batch['rows'][i-1].get('status')=='captured-single-observational-uia-printwindow','dispatch/batch terminal capture status')
    check(batch['rows'][i-1]['dispatchHash']==consumed[f'run{i}:dispatch']['sha256'][7:],'batch dispatch hash join')
    check(integer(obs.get('index')) and obs.get('index')==1 and obs.get('case')==plan.get('case') and obs.get('sourceHash')==plan.get('sourceHash')==out.get('sourceHash')==compile.get('sourceHash'),'case/source join')
    check(out.get('primaryError')=='' and out.get('streamErrors')==[] and integer((out.get('preCleanupExitObservation') or {}).get('kernelWaitResult')) and out['preCleanupExitObservation']['kernelWaitResult']==0 and kernel(out.get('cleanup') or {},True),'original native deadline/natural kernel0 failure')
    check(out.get('ownedIdentity')==owned and owned.get('path')==compile.get('exePath') and integer(owned.get('pid')) and owned['pid']>0 and bool(owned.get('startedAt')),'owned process identity join')
    check(close.get('pid')==pixels.get('pid')==owned['pid'] and close.get('hwnd')==pixels.get('hwnd')==launch.get('ownedWindow') and close.get('posted') is True and close.get('message')==16 and close.get('activationRequested') is False,'owned HWND/WM_CLOSE/pixels join')
    check(dispatch.get('owner')==out.get('lockOwner') and dispatch.get('lockAcquired') is True and dispatch.get('lockReleased') is True and dispatch.get('lockRetainedForUnconfirmedOwnedExit') is False and dispatch.get('error')=='' and dispatch.get('cleanupErrors')==[],'lock ownership/release join')
    check(obs.get('hostValid') is True and obs.get('probeForegroundAtCapture') is False and obs.get('backgroundPlacementRequested') is True and launch.get('createNoWindow') is True,'background/noactivate observation')
    states=out.get('rawStreams',[]);check(len(states)==2 and {s.get('name') for s in states}=={'stdout','stderr'} and all(stream(s) for s in states),'exact2 sealed terminal raw streams')
    raw={}
    for b in obs.get('files',[]):
     name=b['path'];check(name not in raw,'duplicate raw binding');raw[name]=read((bindings.get('raw') or {}).get(name),f'run{i}:raw:{name}');check(digest(raw[name])=='sha256:'+b['sha256'],'native raw receipt hash join')
    for name,key in [('host.stdout.txt','stdoutSha256'),('host.stderr.txt','stderrSha256')]:check(digest(raw[name])=='sha256:'+out[key],'terminal raw byte join')
    check(raw['capture-outcome.json']==read(bindings['outcome'],f'run{i}:outcome-join'),'outcome raw join')
    for sample in pixels['samples']:
     if 'path' in sample:check(digest(raw[sample['path']])=='sha256:'+sample['sha256'],'pixel sample byte join')
    check(pixels.get('printWindowFlags')==3 and pixels.get('providerReadbackExport') is False,'PrintWindow method/source')
    check(integer(compile.get('exitCode')) and compile.get('exitCode')==0 and compile.get('timedOut') is False and compile.get('streamDrainComplete') is True and compile.get('exeSha256')==obs.get('exeSha256')==out.get('exeHash')==batch.get('exeHash') and consumed[f'run{i}:compile']['sha256']=='sha256:'+obs['compileReceiptHash']=='sha256:'+out['compileReceiptHash']=='sha256:'+batch['compileReceiptHash'],'compiler/exe receipt joins')
    row['settled']=True
    row['channels']=channels(parse(raw['native.uia.json']),raw['native.printwindow.png'],raw['host.stdout.txt'])
    case=get('case');recipe=get('recipe')
    check(_canonical.sha256(case)==plan['case']['hash'] and case.get('id')==plan['case']['id'],'actual case bytes/canonical hash join')
    manifest=load((bindings.get('source') or {}).get('witness.manifest.json'),f'run{i}:manifest')
    check(manifest.get('case')==plan['case'] and manifest.get('sourceHash')==plan['sourceHash'] and manifest.get('recipe',{}).get('hash')==_canonical.sha256(recipe),'actual manifest/recipe/source join')
    for b in plan['sourceBindings']:check(digest(read((bindings.get('source') or {}).get(b['path']),f'run{i}:source:{b["path"]}'))==b['sha256'],'source archive hash join')
    check(digest(read(bindings.get('exe'),f'run{i}:exe'))=='sha256:'+obs['exeSha256'],'actual exe bytes join')
    check(digest(read(bindings.get('renderer'),f'run{i}:renderer'))=='sha256:'+obs['rendererSha256']=='sha256:'+plan['rendererSha256'],'actual renderer bytes join')
    proof=get('macSourceProof');check(consumed[f'run{i}:macSourceProof']['sha256']=='sha256:'+out['macSourceProofHash'],'Mac source proof raw join')
    matches=[c for c in proof.get('cases',[]) if c.get('case')==plan['case'] and c.get('witnessHash')==plan['sourceHash']];check(len(matches)==1,'Mac source proof case/witness join')
    row['sourceJoined']=True
    mode=bindings.get('uiaMode');check(mode in ('parent-retained','isolated-worker'),'explicit UIA ownership mode required')
    if mode=='isolated-worker':
     worker=get('uiaWorker');check(worker.get('status')=='completed-natural-uiasnapshot' and worker.get('primaryError')=='' and integer(worker.get('exitCode')) and worker.get('exitCode')==0 and worker.get('timedOut') is False and integer(worker.get('preCleanupKernelWaitResult')) and worker['preCleanupKernelWaitResult']==0 and kernel(worker.get('cleanup') or {},True),'worker natural exit before capture required')
     check(worker.get('target',{}).get('pid')==owned['pid'] and worker['target'].get('hwnd')==pixels['hwnd'] and worker['target'].get('path')==owned['path'] and worker['target'].get('startedAt')==owned['startedAt'] and worker['target'].get('lockOwner')==out['lockOwner'],'worker target join')
     ws=worker.get('rawStreams',[]);check(len(ws)==2 and {s.get('name') for s in ws}=={'stdout','stderr'} and all(stream(s) for s in ws) and worker.get('streamErrors')==[],'worker sealed streams')
     check(worker.get('uiaSha256')==digest(raw['native.uia.json'])[7:],'worker UIA scalar byte join')
     for name in ('stdout','stderr'):check(digest(read(bindings.get('workerRaw',{}).get(name),f'run{i}:worker:{name}'))=='sha256:'+worker[name+'Sha256'],'worker raw join')
     rowissues.append('missing-source-owned-worker-before-pixels-ordering-receipt')
    row['channels']=channels(parse(raw['native.uia.json']),raw['native.printwindow.png'],raw['host.stdout.txt'])
   except (ValueError,KeyError,TypeError,IndexError) as e:rowissues.append(str(e))
  if any(r['issues'] for r in rows):issues.append('incomplete-actual-channel-joins')
  issued=inputs.get('issuedMetadata')
  if issued is None:issues.append('missing-prelaunch-issued-capture-metadata')
  else:
   metadata=load(issued,'issuedMetadata');issues.append('missing-source-owned-issued-metadata-launch-receipt')
  issues.append('canonical-emission-held-until-prospective-source-contract-joins')
 except (ValueError,KeyError,TypeError,IndexError) as e:issues.append(str(e))
 return result
