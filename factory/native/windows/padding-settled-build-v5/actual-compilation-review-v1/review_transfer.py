"""Read-only transfer/process/raw joins, alongside actual compilation verifier."""
from pathlib import Path
from review import review,load,digest,ticks
import json
ROOT=Path(__file__).resolve().parent.parent/'root-build-r1'
def final_review():
 result=review(ROOT/'actual');refs=result['rawRefs'];issues=result['issues']
 def raw(path):
  data=(ROOT/path).read_bytes();refs['root-build-r1/'+path]='sha256:'+digest(data);return data
 def require(test,message):
  if not test:raise ValueError(message)
 try:
  for name in ('build','inspect'):
   record=load(raw(name+'-process.json'))
   require(type(record['exitCode']) is int and record['exitCode']==0,name+' process exit0')
   require(ticks(record['startedAt'])<=ticks(record['finishedAt']),name+' process time order')
   for stream in ('stdout','stderr'):require(record[stream+'Sha256']==digest(raw(name+'.'+stream+'.bin')),name+' process raw join')
  fetch=load(raw('fetch.json'));require(type(fetch['exitCode']) is int and fetch['exitCode']==0 and fetch['stderr']=='','fetch completion')
  expected={'compile.stderr.bin','compile.stdout.bin','FactoryProbe.exe','observation.json','runtime-module-archive/x86_64-unknown-windows-msvc.swiftdoc','runtime-module-archive/x86_64-unknown-windows-msvc.swiftmodule'}
  require(set(fetch['files'])==expected,'six exact transfer files')
  inventory=load(raw('inspect.stdout.bin'));rows=inventory['rows'];require(len(rows)==6 and {r['path'].replace('\\','/') for r in rows}==expected,'six exact remote inventory files')
  require(inventory['root']==r'D:\Claude\swiftright\.factory-work\hosts\padding-settled\package\build-settled-r2','remote build root')
  for path in expected:
   data=(ROOT/'actual'/path).read_bytes();claim=fetch['files'][path];row=next(r for r in rows if r['path'].replace('\\','/')==path)
   require(type(claim['bytes']) is int and type(row['bytes']) is int and claim['bytes']==row['bytes']==len(data),'transferred/remote byte size '+path)
   require(claim['sha256']==row['sha256']==digest(data),'transferred/remote byte hash '+path)
  require(inventory['receiptSha256']==digest((ROOT/'actual/observation.json').read_bytes()) and inventory['exeSha256']==digest((ROOT/'actual/FactoryProbe.exe').read_bytes()),'remote measured actual pins')
 except (ValueError,KeyError,TypeError,OSError,UnicodeError) as error:issues.append(str(error))
 result.update({'decision':'CLEAR-OBSERVATIONAL-COMPILATION' if not issues else 'BLOCKED','acceptedObservationalCompile':not issues,'transferJoins':not issues,'sourceInputScope':'frozen producer/canonical raw input authority +reviewed before/after operational guards; driver-reported argv, not independent backend attestation','nativeLaunchAdmission':'root separately binds actual serializer control +immediate production preflight +reviewed Count1/noactivation/lock/owned-kernel capture driver'})
 return result
if __name__=='__main__':print(json.dumps(final_review(),indent=2))
