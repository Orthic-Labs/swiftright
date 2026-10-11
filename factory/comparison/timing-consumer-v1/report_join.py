"""Recompute observational timing joins before exposing any supplied status."""
from consumer import TimingConsumer,Rejected,require,canonical,digest

def join(consumer:TimingConsumer,inputs:dict[str,bytes],claimed:dict,derived_bytes:bytes)->dict:
 actual=consumer.validate(inputs)
 require(digest(derived_bytes)==actual['resultHash'],'derived artifact hash mismatch')
 require(derived_bytes==canonical(actual['details']),'derived artifact contents mismatch')
 require(canonical(claimed)==canonical({k:v for k,v in actual.items() if k!='details'}),'claimed timing verdict mismatch')
 return {'schema':'verified-timing-report-join-v1','observationalStatus':actual['status'],'nativeParity':False,'qualificationStatus':'held','qualificationReason':'This consumer establishes timestamp reconstruction only; qualified native gate evidence is separate.','timing':claimed,'derivedArtifact':{'hash':actual['resultHash'],'bytes':len(derived_bytes)}}

def gate_callback(consumer:TimingConsumer,inputs:dict[str,bytes]):
 """Return bound diagnostics without promoting synthetic/observational timing to gate pass."""
 def callback(*,captures,tuple_value):
  from consumer import ref
  result=consumer.validate(inputs)
  require(ref(tuple_value)==consumer.tuple_hash,'gate tuple mismatch')
  require(isinstance(captures,list) and all(type(raw) is bytes for raw in captures),'gate requires original raw capture bytes; dict-only adapter is unqualified')
  require(sorted(digest(raw) for raw in captures)==result['captureHashes'],'gate raw captures mismatch')
  return {'status':'blocked','observationalStatus':result['status'],'evidence':result['evidence'],'captureHashes':result['captureHashes'],'tupleHash':result['tupleHash'],'nativeParity':False}
 return callback

def inspect_legacy_capture(raw:bytes)->dict:
 """Existing v0.1 shared-clock capture cannot supply absent channel qualification."""
 from consumer import parse
 capture=parse(raw)
 require(capture.get('kind')=='capture' and capture.get('version')=='0.1','not legacy capture')
 return {'status':'held','nativeParity':False,'rawEvidence':{'id':capture.get('id'),'hash':digest(raw)},'reason':'Legacy animation timestamps lack per-channel clock/unit declarations; no clock domain is inferred from meta.clock.'}
