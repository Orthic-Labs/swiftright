"""Nonvacuous synthetic raw controls; no native parity evidence."""
import copy,json,unittest,tempfile
from pathlib import Path
from retention import retain,retrieve
from consumer import TimingConsumer,Rejected,canonical,digest,ref
from report_join import join,gate_callback,inspect_legacy_capture

def fixture():
 acceptance={'schema':'timing-acceptance-v1','scenario':'dynamic-interruption','timingBounds':{'durationNs':{'min':95,'max':105},'interruptionVelocityMilliPerSecond':{'min':0,'max':60_000_000_000},'presentedFrameStallNs':{'min':0,'max':10},'frameIntervalNs':20}}
 case={'id':'synthetic.interruption.case','tuple':{'id':'synthetic.tuple','acceptanceConfigHash':ref(acceptance)}}
 cr={'id':case['id'],'hash':ref(case)};th=ref(case['tuple'])
 context={'schema':'timing-context-v1','acceptanceConfigHash':ref(acceptance),'case':cr,'tupleHash':th,'scenario':'dynamic-interruption','evidenceClass':'synthetic/unit-evidence','clock':{'clockId':'test.monotonic','unit':'ns','domain':'monotonic'},'animationIds':['motion']}
 bounds={'schema':'timing-bounds-v1','acceptanceConfigHash':ref(acceptance),'case':cr,'tupleHash':th,'durationNs':{'min':95,'max':105},'interruptionVelocityMilliPerSecond':{'min':0,'max':60_000_000_000},'presentedFrameStallNs':{'min':0,'max':10},'frameIntervalNs':20}
 def point(t,**kw):return {'timeNs':t,'clockId':'test.monotonic','unit':'ns',**kw}
 capture={'schema':'timing-observations-v1','id':'test.run1','case':cr,'tupleHash':th,'boundsHash':digest(canonical(bounds)),'contextHash':digest(canonical(context)),'scenario':'dynamic-interruption','events':{k:point(t) for k,t in [('stimulus',0),('transaction',0),('interruption',50),('completion',100)]},'animations':[{'id':'motion','samples':[point(t,value=v) for t,v in [(0,0),(25,0),(50,1),(75,2),(100,20)]],'presentedFrames':[point(t,imageHash='sha256:'+'b'*64) for t in [0,20,40,60,80,100]]}]}
 return json.loads(json.dumps({'acceptance':acceptance,'case':case,'context':context,'bounds':bounds,'capture:run1':capture}))
def prepare(docs):
 raw={k:canonical(v) for k,v in docs.items()};pins={k:digest(v) for k,v in raw.items()}
 case=docs['case'];return TimingConsumer(pins,{'id':case['id'],'hash':ref(case)},ref(case['tuple'])),raw
def validated(docs):c,raw=prepare(docs);return c.validate(raw)
def rebind(docs):
 for k,x in docs.items():
  if k.startswith('capture:'):x['boundsHash']=digest(canonical(docs['bounds']));x['contextHash']=digest(canonical(docs['context']))
 return docs

def controls():
 def mutate(name,fn,expected):return name,fn,expected
 cases=[
 mutate('duration',lambda d:d['capture:run1']['events']['completion'].update(timeNs=120),'fail'),
 mutate('terminal-truncation',lambda d:d['capture:run1']['animations'][0]['presentedFrames'].__delitem__(slice(3,None)),'fail'),
 mutate('leading-truncation',lambda d:d['capture:run1']['animations'][0]['presentedFrames'].__delitem__(slice(0,3)),'fail'),
 mutate('transaction-after-interruption',lambda d:d['capture:run1']['events']['transaction'].update(timeNs=60),'rejected'),
 mutate('sample-before-transaction',lambda d:d['capture:run1']['events']['transaction'].update(timeNs=10),'rejected'),
 mutate('frame-outside-window',lambda d:d['capture:run1']['animations'][0]['presentedFrames'][-1].update(timeNs=101),'rejected'),
 mutate('interruption-local-velocity',lambda d:d['capture:run1']['animations'][0]['samples'][2].update(value=10),'fail'),
 mutate('missing-interruption-sample',lambda d:d['capture:run1']['animations'][0]['samples'][2].update(timeNs=51),'rejected'),
 mutate('missing-incoming-bracket',lambda d:d['capture:run1']['animations'][0]['samples'].__delitem__(slice(0,2)),'rejected'),
 mutate('mixed-clock',lambda d:d['capture:run1']['animations'][0]['presentedFrames'][1].update(clockId='other.clock'),'rejected'),
 mutate('unknown-unit',lambda d:d['capture:run1']['events']['completion'].update(unit='us'),'rejected'),
 mutate('missing-channel-clock',lambda d:d['capture:run1']['animations'][0]['samples'][1].pop('clockId'),'held'),
 mutate('unknown-domain',lambda d:d['context']['clock'].update(domain='wall'),'held'),
 mutate('wrong-bound-case',lambda d:d['bounds']['case'].update(id='other.case'),'rejected'),
 mutate('wrong-capture-tuple',lambda d:d['capture:run1'].update(tupleHash='sha256:'+'f'*64),'rejected'),
 mutate('duplicate-animation',lambda d:d['capture:run1']['animations'].append(copy.deepcopy(d['capture:run1']['animations'][0])),'rejected'),
 mutate('missing-animation',lambda d:d['capture:run1'].update(animations=[]),'held'),
 mutate('nonmonotonic-frame',lambda d:d['capture:run1']['animations'][0]['presentedFrames'][1].update(timeNs=0),'rejected'),
 mutate('dropped-frame-gap',lambda d:[x.update(dropped=True) for x in d['capture:run1']['animations'][0]['presentedFrames'][1:5]],'fail'),
 mutate('protected-bound-values',lambda d:d['bounds']['durationNs'].update(max=1000),'rejected'),
 mutate('rawbyte-hash',lambda d:None,'rejected'),
 mutate('duplicate-event-field',lambda d:None,'raw-rejected'),
 ]
 rows=[]
 for name,fn,expected in cases:
  before=fixture();assert validated(before)['status']=='pass';docs=copy.deepcopy(before);fn(docs);rebind(docs)
  if name=='rawbyte-hash':
   c,raw=prepare(before);raw['capture:run1']+=b' '
  elif name=='duplicate-event-field':
   c,raw=prepare(before);raw['capture:run1']=raw['capture:run1'].replace(b'"timeNs":0',b'"timeNs":0,"timeNs":0',1);c.pins['capture:run1']=digest(raw['capture:run1']);expected='rejected'
  else:c,raw=prepare(docs)
  assert raw!=prepare(before)[1],name
  try:actual=c.validate(raw)['status'];reason=actual
  except Rejected as e:actual='rejected';reason=str(e)
  assert actual==expected,(name,actual,expected)
  rows.append({'name':name,'acceptedBaseline':True,'changedRawBytes':True,'status':actual,'reason':reason,'mutatedRawPins':{k:digest(v) for k,v in raw.items()},'actualMutatedRawInputsUTF8':{k:v.decode() for k,v in raw.items()}})
 return rows
class TimingTests(unittest.TestCase):
 def test_content_addressed_retention(self):
  c,raw=prepare(fixture())
  with tempfile.TemporaryDirectory() as d:
   m=retain(c,raw,Path(d));self.assertEqual(retain(c,raw,Path(d)),m)
   for k,x in m['rawInputs'].items():self.assertEqual(retrieve(Path(d),x),raw[k])
   desc=m['derivedDetails'];(Path(d)/desc['path']).write_bytes(b'forged')
   with self.assertRaisesRegex(Rejected,'immutable retained'):retain(c,raw,Path(d))
   with self.assertRaisesRegex(Rejected,'byte integrity'):retrieve(Path(d),desc)
 def test_controls(self):self.assertEqual(len(controls()),22)
 def test_local_velocity_ignores_unrelated_global_peak(self):
  r=validated(fixture());self.assertEqual(r['status'],'pass');self.assertEqual(r['details']['runs'][0]['derived'][0]['incomingVelocityMilliPerSecond'],'40000000000')
 def test_raw_hash_fault(self):
  c,raw=prepare(fixture());raw['capture:run1']+=b' '
  with self.assertRaisesRegex(Rejected,'raw hash mismatch'):c.validate(raw)
 def test_report_join_and_status_hash_faults(self):
  c,raw=prepare(fixture());r=c.validate(raw);claimed={k:v for k,v in r.items() if k!='details'};b=canonical(r['details']);self.assertEqual(join(c,raw,claimed,b)['observationalStatus'],'pass')
  for key,v in [('resultHash','sha256:'+'c'*64),('status','held'),('rawEvidence',[]),('boundsHash','sha256:'+'d'*64),('contextHash','sha256:'+'e'*64)]:
   forged=copy.deepcopy(claimed);forged[key]=v
   with self.assertRaises(Rejected):join(c,raw,forged,b)
  forged=copy.deepcopy(r['details']);forged['runs'][0]['derived'][0]['durationNs']=99
  with self.assertRaises(Rejected):join(c,raw,claimed,canonical(forged))
 def test_static_not_pass(self):
  d=fixture();d['acceptance']['scenario']='static';d['case']['tuple']['acceptanceConfigHash']=ref(d['acceptance']);cr={'id':d['case']['id'],'hash':ref(d['case'])};th=ref(d['case']['tuple']);
  for v in [d['context'],d['bounds'],d['capture:run1']]:v.update(case=cr,tupleHash=th)
  for v in [d['context'],d['bounds']]:v['acceptanceConfigHash']=ref(d['acceptance'])
  d['context']['scenario']='static';d['capture:run1'].update(scenario='static',events={},animations=[]);self.assertEqual(validated(rebind(d))['status'],'not-applicable')
 def test_legacy_shared_clock_held(self):self.assertEqual(inspect_legacy_capture(canonical({'kind':'capture','version':'0.1','id':'legacy','meta':{'clock':{'clockId':'monotonic'}}}))['status'],'held')
 def test_gate_never_promotes_observational_packet(self):
  d=fixture();c,raw=prepare(d);cb=gate_callback(c,raw);self.assertEqual(cb(captures=[raw['capture:run1']],tuple_value=d['case']['tuple'])['status'],'blocked')
  with self.assertRaises(Rejected):cb(captures=[raw['capture:run1']+b' '],tuple_value=d['case']['tuple'])
if __name__=='__main__':unittest.main()
