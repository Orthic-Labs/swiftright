"""Archive-only hydration must preserve frozen semantic joins & tool bytes."""
from pathlib import Path
from archived_swift16 import ArchivedExactSwift16,m

def run():
 live=ArchivedExactSwift16();store={str(path):live.inputs[k] for k,path in live.paths.items()};reads=[]
 def reader(path,force_archive=False):
  if force_archive is not True or path not in store:raise ValueError('unexpected archive lookup')
  reads.append(path);return store[path]
 original=Path.read_bytes
 def no_live(path):
  if str(path).startswith('/Applications/') or str(path).startswith('/usr/bin/') or str(path).startswith('/Users/adrdsouza/Library/Caches/'):
   raise AssertionError('live SDK/tool/cache read '+str(path))
  return original(path)
 Path.read_bytes=no_live
 try:
  archived=ArchivedExactSwift16(read_bytes=reader,force_archive=True)
  rows=archived.validate();m.require(len(rows)==16,'archive-only sixteen baseline')
  try:archived.validate({'tool:compiler':archived.inputs['tool:compiler']+b'fault'})
  except ValueError as e:m.require(str(e)=='archive Swift16 exact bytes tool:compiler','archive actual tool byte fault')
  else:raise AssertionError('archive compiler byte fault accepted')
  try:ArchivedExactSwift16(force_archive=True)
  except ValueError as e:m.require(str(e)=='forced archive resolver required','forced resolver guard')
  else:raise AssertionError('forced archive fell back to live files')
 finally:Path.read_bytes=original
 return {'rows':16,'archiveReads':len(reads),'toolByteFaultRejected':True,'forcedResolverRequired':True,'liveSDKToolCacheReads':0}
if __name__=='__main__':print(run())
