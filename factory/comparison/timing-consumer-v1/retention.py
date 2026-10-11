"""Retain validated raw inputs & derived payloads by exact byte hash, immutably."""
from pathlib import Path
import re
from consumer import canonical,digest,require

def retain(consumer,inputs:dict[str,bytes],directory:Path)->dict:
 result=consumer.validate(inputs);directory=Path(directory);directory.mkdir(parents=True,exist_ok=True)
 def put(raw):
  pin=digest(raw);name=pin.removeprefix('sha256:')+'.json';path=directory/name
  if path.exists():require(path.read_bytes()==raw,'immutable retained artifact mismatch')
  else:
   with path.open('xb') as f:f.write(raw)
  return {'hash':pin,'path':name,'bytes':len(raw)}
 raw={k:put(v) for k,v in inputs.items()};derived=put(canonical(result['details']));require(derived['hash']==result['resultHash'],'derived retention join')
 return {'schema':'timing-retention-manifest-v1','nativeParity':False,'rawInputs':raw,'derivedDetails':derived}

def retrieve(directory:Path,descriptor:dict)->bytes:
 pin=descriptor.get('hash');require(isinstance(pin,str) and bool(re.fullmatch(r'sha256:[0-9a-f]{64}',pin)),'invalid retention hash')
 require(descriptor.get('path')==pin[7:]+'.json','retention path/hash mismatch')
 raw=(Path(directory)/descriptor['path']).read_bytes();require(digest(raw)==pin and len(raw)==descriptor.get('bytes'),'retained byte integrity mismatch');return raw
