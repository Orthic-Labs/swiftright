"""Freeze or replay lossless synthetic raw timing & fault-control evidence."""
import json,hashlib,sys
from pathlib import Path
from consumer import canonical,digest,Rejected
from report_join import join
from retention import retain
from test_consumer import fixture,prepare,controls
HERE=Path(__file__).resolve().parent

def build():
 docs=fixture();c,raw=prepare(docs);actual=c.validate(raw);claim={k:v for k,v in actual.items() if k!='details'};derived=canonical(actual['details'])
 baseline=join(c,raw,claim,derived);faults=[]
 for key,value in [('resultHash','sha256:'+'a'*64),('status','held'),('rawEvidence',[]),('boundsHash','sha256:'+'b'*64),('contextHash','sha256:'+'c'*64)]:
  forged=dict(claim);forged[key]=value
  try:join(c,raw,forged,derived);raise AssertionError('accepted forged '+key)
  except Rejected as e:faults.append({'name':key,'acceptedBaseline':True,'actualClaim':forged,'reason':str(e),'status':'rejected'})
 mutated=derived+b' '
 try:join(c,raw,claim,mutated);raise AssertionError('accepted derived bytes')
 except Rejected as e:faults.append({'name':'derived-bytes','acceptedBaseline':True,'actualDerivedBytesUTF8':mutated.decode(),'reason':str(e),'status':'rejected'})
 sources={p.name:{'sha256':digest(p.read_bytes()),'bytes':p.stat().st_size} for p in [HERE/'consumer.py',HERE/'report_join.py',HERE/'test_consumer.py',HERE/'build_packet.py',HERE/'retention.py']}
 return {'schema':'timing-consumer-synthetic-proof-v1','evidenceClass':'synthetic/unit-evidence','nativeParity':False,'sourcePins':sources,'protectedExpectedPins':c.pins,'baselineRawInputsUTF8':{k:v.decode() for k,v in raw.items()},'baselineVerdict':claim,'derivedArtifactUTF8':derived.decode(),'verifiedReportJoin':baseline,'rawFaults':controls(),'reportJoinFaults':faults}
if __name__=='__main__':
 proof=build();c,raw=prepare(fixture());retained=retain(c,raw,HERE/'artifacts');proof['retainedArtifacts']=retained;encoded=json.dumps(proof,indent=2,allow_nan=False)+'\n';p=HERE/'proof.json'
 if '--check' in sys.argv:assert p.read_text()==encoded;print('Exact raw packet replay passed:22 raw +6 report-join faults')
 else:p.write_text(encoded);print('Frozen22 raw +6 report-join controls')
