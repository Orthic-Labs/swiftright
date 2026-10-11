#!/usr/bin/env python3
"""Reproduce original comparator faults without changing protected evidence."""
import contextlib,hashlib,io,json,sys
from pathlib import Path
ROOT=Path.cwd();HERE=ROOT/'factory/registry/public-source-binding-v2/independent-review';V1=ROOT/'factory/registry/public-source-binding-v1'
PIN='b2e9eb066a9dd7ba92133fc4c427a552484adcaff7fbd5eb60f117fdc34635bc'
def digest(raw):return hashlib.sha256(raw).hexdigest()
def main():
 source=(HERE/'preimages'/('compare_final_candidate.py.'+PIN)).read_bytes();assert digest(source)==PIN
 scope={'__name__':'original_comparator_review','__file__':str(ROOT/'factory/registry/public-source-binding-v2/compare_final_candidate.py')};exec(compile(source,scope['__file__'],'exec'),scope)
 cat=json.loads((V1/'archive/inputs/catalogue.json').read_text());want=json.loads((V1/'expected-registry-membership.json').read_text())['blocks'];usrs={r['usr'] for r in want};cat['symbols']=[s for s in cat['symbols'] if s['usr'] in usrs];assert len(cat['symbols'])==len(usrs)
 candidate=HERE/'initial-control-candidate.json';candidate.write_text(json.dumps(cat)+'\n');raw=candidate.read_bytes();faults=[]
 def invoke(output):
  sys.argv=['original-comparator',str(candidate),'--output',str(output)]
  try:
   with contextlib.redirect_stdout(io.StringIO()):scope['main']()
  except SystemExit as ex:return ex.code
 output=HERE/'initial-status-receipt.json';cat['symbols'][0]['status']='INVALID_SCHEMA_STATUS';candidate.write_text(json.dumps(cat)+'\n');assert invoke(output)==0;receipt=json.loads(output.read_text());assert receipt['status']=='stable-membership';faults.append({'name':'invalid-selected-status','acceptedStatus':receipt['status'],'injectedStatus':'INVALID_SCHEMA_STATUS'})
 candidate.write_bytes(raw);read=Path.read_bytes;readcount=0
 def race(path):
  nonlocal readcount
  if path.resolve()==candidate.resolve():
   readcount+=1
   if readcount>1:return b'not parsed catalogue bytes'
  return read(path)
 Path.read_bytes=race
 try:
  output=HERE/'initial-race-receipt.json';assert invoke(output)==0;receipt=json.loads(output.read_text());assert receipt['candidate']['sha256']=='sha256:'+digest(b'not parsed catalogue bytes');faults.append({'name':'candidate-reread','acceptedStatus':receipt['status'],'parsedBytesSha256':digest(raw),'reportedCandidateSha256':receipt['candidate']['sha256']})
 finally:Path.read_bytes=read
 protected=V1/'final-candidate-resolution.json';before=protected.read_bytes();write=Path.write_text;attempt=[]
 class InterceptedWrite(Exception):pass
 def intercept(path,*args,**kwargs):
  if path.resolve()==protected.resolve():attempt.append(True);raise InterceptedWrite()
  return write(path,*args,**kwargs)
 Path.write_text=intercept
 try:
  try:invoke(protected)
  except InterceptedWrite:pass
  assert attempt
 finally:Path.write_text=write
 assert protected.read_bytes()==before;faults.append({'name':'reserved-pending-output','protectedWriteAttempted':True,'protectedBytesUnchanged':True})
 report={'comparatorSha256':PIN,'reproducerSha256':digest(Path(__file__).read_bytes()),'faults':faults,'allProtectedV1BytesPreserved':True};out=HERE/'initial-fault-reproduction.json';out.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(digest(out.read_bytes()));candidate.unlink()
if __name__=='__main__':main()
