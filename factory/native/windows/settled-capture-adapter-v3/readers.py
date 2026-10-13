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

