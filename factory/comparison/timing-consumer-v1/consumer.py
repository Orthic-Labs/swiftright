"""Strict offline timing consumer. Observational evidence never establishes parity."""
from __future__ import annotations
import hashlib,json,re
from decimal import Decimal,InvalidOperation
from typing import Any

def digest(raw: bytes)->str:return 'sha256:'+hashlib.sha256(raw).hexdigest()
def canonical(value: Any)->bytes:return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False).encode()
def ref(value: Any)->str:return digest(canonical(value))
class Rejected(ValueError):pass

def require(ok: bool,reason: str):
 if not ok:raise Rejected(reason)
def parse(raw: bytes):
 def pairs(rows):
  out={}
  for k,v in rows:
   require(k not in out,'duplicate JSON key');out[k]=v
  return out
 def bad(v):raise Rejected('nonfinite JSON number')
 try:return json.loads(raw.decode('utf-8'),object_pairs_hook=pairs,parse_constant=bad)
 except (UnicodeError,json.JSONDecodeError) as e:raise Rejected('invalid UTF8 JSON') from e

def integer(v,name):require(type(v) is int and v>=0,'invalid '+name);return v
def numeric(v):
 require(type(v) in (int,float) or (isinstance(v,dict) and set(v)=={'$decimal'}),'nonnumeric sample')
 try:d=Decimal(str(v['$decimal'] if isinstance(v,dict) else v))
 except (ValueError,InvalidOperation,TypeError) as e:raise Rejected('invalid decimal sample') from e
 require(d.is_finite(),'nonfinite sample');return d

def interval(v,name):
 require(isinstance(v,dict) and set(v)=={'min','max'},'invalid '+name+' bounds')
 lo=integer(v['min'],name);hi=integer(v['max'],name);require(lo<=hi,'reversed '+name+' bounds');return lo,hi

def time(record,clock):
 require(isinstance(record,dict),'missing timestamp record')
 require(record.get('clockId')==clock,'timestamp clock mismatch')
 require(record.get('unit')=='ns','unknown timestamp unit')
 return integer(record.get('timeNs'),'timestamp')

class TimingConsumer:
 """Expected raw pins come from review-bound manifest, never supplied status flags."""
 def __init__(self,expected_pins:dict[str,str],case_ref:dict,tuple_hash:str):
  require(isinstance(expected_pins,dict) and set(expected_pins)>={'case','context','bounds','acceptance'},'missing protected pins')
  require(all(isinstance(v,str) and bool(re.fullmatch(r'sha256:[0-9a-f]{64}',v)) for v in expected_pins.values()),'invalid expected pin')
  self.pins=dict(expected_pins);self.case_ref=dict(case_ref);self.tuple_hash=tuple_hash
 def validate(self,inputs:dict[str,bytes])->dict:
  require(set(inputs)==set(self.pins),'raw input closure mismatch')
  require(all(type(v) is bytes for v in inputs.values()),'raw bytes required')
  for key,pin in self.pins.items():require(digest(inputs[key])==pin,'raw hash mismatch: '+key)
  docs={k:parse(v) for k,v in inputs.items()}
  case,ctx,bounds,acceptance=docs['case'],docs['context'],docs['bounds'],docs['acceptance']
  require(isinstance(case,dict) and isinstance(ctx,dict) and isinstance(bounds,dict) and isinstance(acceptance,dict),'invalid protected input object')
  require(acceptance.get('schema')=='timing-acceptance-v1','unknown acceptance schema')
  require((case.get('tuple') if isinstance(case.get('tuple'),dict) else {}).get('acceptanceConfigHash')==ref(acceptance),'protected acceptance hash mismatch')
  require(bounds.get('acceptanceConfigHash')==ref(acceptance) and ctx.get('acceptanceConfigHash')==ref(acceptance),'protected policy context mismatch')
  require({k:bounds.get(k) for k in ['durationNs','interruptionVelocityMilliPerSecond','presentedFrameStallNs','frameIntervalNs']}==acceptance.get('timingBounds'),'protected bounds differ from acceptance')
  require(ctx.get('scenario')==acceptance.get('scenario'),'protected scenario differs from acceptance')
  require(case.get('id')==self.case_ref.get('id') and ref(case)==self.case_ref.get('hash'),'case identity mismatch')
  require(ref(case.get('tuple'))==self.tuple_hash,'case tuple mismatch')
  for doc in (ctx,bounds):
   require(doc.get('case')==self.case_ref and doc.get('tupleHash')==self.tuple_hash,'protected context case/tuple mismatch')
  require(ctx.get('schema')=='timing-context-v1' and bounds.get('schema')=='timing-bounds-v1','unknown context schema')
  require(ctx.get('evidenceClass')=='synthetic/unit-evidence' or ctx.get('evidenceClass')=='observational','unknown evidence class')
  scenario=ctx.get('scenario');require(scenario in ('dynamic-interruption','static'),'undeclared scenario')
  sources=sorted(k for k in inputs if k.startswith('capture:'))
  require(sources and set(inputs)=={'case','context','bounds','acceptance',*sources},'unexpected input role')
  capture_refs=[{'id':docs[k].get('id'),'hash':digest(inputs[k])} for k in sources]
  require(all(isinstance(x['id'],str) and x['id'] for x in capture_refs),'missing capture identity')
  require(len({x['id'] for x in capture_refs})==len(sources),'duplicate capture identity')
  details=[]
  for k in sources:
   raw=docs[k];require(isinstance(raw,dict),'invalid capture object');require(raw.get('schema')=='timing-observations-v1','unknown capture schema')
   require(raw.get('case')==self.case_ref and raw.get('tupleHash')==self.tuple_hash,'capture case/tuple mismatch')
   require(raw.get('boundsHash')==self.pins['bounds'] and raw.get('contextHash')==self.pins['context'],'capture context/bounds mismatch')
   require(raw.get('scenario')==scenario,'capture scenario mismatch')
   base={'capture':{'id':raw['id'],'hash':digest(inputs[k])},'rawTiming':raw,'status':'held','reason':'missing qualified dynamic timestamp channels'}
   if scenario=='static':
    require(not raw.get('events') and not raw.get('animations'),'static scenario has dynamic records')
    base.update(status='not-applicable',reason='declared static scenario; no dynamic timing verdict');details.append(base);continue
   events,animations=raw.get('events'),raw.get('animations')
   if not events or not animations:details.append(base);continue
   clock=ctx.get('clock')
   # A shared capture clock alone does not prove timestamp/channel clock domains.
   if not isinstance(clock,dict) or clock.get('unit')!='ns' or not isinstance(clock.get('clockId'),str) or not clock.get('clockId') or clock.get('domain')!='monotonic':
    base['reason']='unknown declared clock domain/unit';details.append(base);continue
   require(isinstance(events,dict) and set(events)=={'stimulus','transaction','interruption','completion'},'event cardinality')
   require(isinstance(animations,list) and len(animations)>0,'animation cardinality')
   if any(not isinstance(e,dict) or 'clockId' not in e or 'unit' not in e for e in events.values()):
    base['reason']='event clock/unit declaration missing';details.append(base);continue
   cid=clock['clockId'];stim,txn,inter,end=[time(events[x],cid) for x in ['stimulus','transaction','interruption','completion']]
   require(stim<=txn<=inter<=end and stim<end,'event chronology')
   expected_ids=ctx.get('animationIds');require(isinstance(expected_ids,list) and expected_ids and all(isinstance(x,str) and x for x in expected_ids) and len(set(expected_ids))==len(expected_ids),'invalid expected animation identities')
   require([a.get('id') if isinstance(a,dict) else None for a in animations]==expected_ids,'animation identity/cardinality mismatch')
   duration_range=interval(bounds.get('durationNs'),'duration');velocity_range=interval(bounds.get('interruptionVelocityMilliPerSecond'),'velocity');stall_range=interval(bounds.get('presentedFrameStallNs'),'stall')
   frame_interval=integer(bounds.get('frameIntervalNs'),'frame interval');require(frame_interval>0,'zero frame interval')
   derived=[];held=False
   for a in animations:
    samples,frames=a.get('samples'),a.get('presentedFrames')
    require(isinstance(samples,list) and isinstance(frames,list),'missing sample/frame arrays')
    if not samples or not frames:held=True;break
    if any(not isinstance(x,dict) or 'clockId' not in x or 'unit' not in x for x in samples+frames):held=True;break
    ts=[time(x,cid) for x in samples];all_ft=[time(x,cid) for x in frames]
    require(all(type(x.get('dropped',False)) is bool for x in frames),'invalid dropped-frame marker')
    require(all(isinstance(x.get('imageHash'),str) and bool(re.fullmatch(r'sha256:[0-9a-f]{64}',x['imageHash'])) for x in frames),'missing presented frame image identity')
    ft=[t for t,x in zip(all_ft,frames) if not x.get('dropped',False)]
    require(all(x<y for x,y in zip(ts,ts[1:])) and all(x<y for x,y in zip(all_ft,all_ft[1:])),'nonmonotonic sample/frame timestamps')
    require(all(txn<=t<=end for t in ts) and all(stim<=t<=end for t in all_ft),'sample/frame outside event window')
    require(len(ft)>=2,'insufficient presentation samples')
    require(ts.count(inter)==1,'missing exact interruption sample')
    i=ts.index(inter);require(0<i<len(ts)-1,'missing incoming/outgoing interruption brackets')
    values=[numeric(x.get('value')) for x in samples]
    # Absolute adjacent slopes touching actual interruption, never unrelated global peak.
    velocities=[str(abs(values[b]-values[a0])*Decimal(10**12)/Decimal(ts[b]-ts[a0])) for a0,b in [(i-1,i),(i,i+1)]]
    largest=max([ft[0]-stim,end-ft[-1]]+[y-x for x,y in zip(ft,ft[1:])]);stall=max(0,largest-frame_interval)
    checks={'durationBounded':duration_range[0]<=end-stim<=duration_range[1],'interruptionVelocityBounded':all(Decimal(velocity_range[0])<=Decimal(v)<=Decimal(velocity_range[1]) for v in velocities),'presentedFrameStallBounded':stall_range[0]<=stall<=stall_range[1]}
    derived.append({'animationId':a['id'],'durationNs':end-stim,'incomingVelocityMilliPerSecond':velocities[0],'outgoingVelocityMilliPerSecond':velocities[1],'largestPresentationGapNs':largest,'presentedFrameStallNs':stall,'checks':checks})
   if held:base['reason']='sample/frame clock or dynamic observation missing';details.append(base);continue
   base.update(status='pass' if all(all(d['checks'].values()) for d in derived) else 'fail',reason='bounded observational timing only',derived=derived);details.append(base)
  status='fail' if any(x['status']=='fail' for x in details) else 'held' if any(x['status']=='held' for x in details) else 'not-applicable' if all(x['status']=='not-applicable' for x in details) else 'pass'
  payload={'schema':'timing-derived-details-v1','case':self.case_ref,'tupleHash':self.tuple_hash,'boundsHash':self.pins['bounds'],'contextHash':self.pins['context'],'evidenceClass':ctx['evidenceClass'],'nativeParity':False,'runs':details}
  return {'status':status,'nativeParity':False,'case':self.case_ref,'tupleHash':self.tuple_hash,'rawEvidence':capture_refs,'captureHashes':sorted(x['hash'] for x in capture_refs),'boundsHash':self.pins['bounds'],'contextHash':self.pins['context'],'resultHash':ref(payload),'evidence':[{'id':'timing-derived-details','hash':ref(payload)}],'details':payload}
