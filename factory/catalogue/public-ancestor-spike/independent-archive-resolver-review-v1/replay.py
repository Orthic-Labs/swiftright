import hashlib,importlib.util,json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
HERE=Path(__file__).resolve().parent
BASE=HERE.parent/'archive-resolver-v1'
def load(path,name):
 s=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
r=load(BASE/'archive_resolver.py','reviewed_resolver')
assert hashlib.sha256((BASE/'archive_resolver.py').read_bytes()).hexdigest()=='28c7ddd5974534efc13cb93d6030ce64fadb752e6c98212205f02c4b9787a8d4'
assert hashlib.sha256((BASE/'test_archive_resolver.py').read_bytes()).hexdigest()=='aa43ec14f5772e0dd8909c83925a7c7126eb48cdaf00375cb48081c65c3fe321'
models=[json.loads(p.read_text()) for p in (r.MANIFEST_PATH,r.V2_MANIFEST_PATH)]
blocked={x['semanticPath'] for m in models for x in m['entries']};blocked_reads=[];rows=[]
original_open=Path.open;original_stat=Path.stat
# Force both bytes & filesystem inspection to reject exact semantic originals.
def guarded_open(p,*a,**kw):
 if str(p) in blocked:blocked_reads.append(str(p));raise AssertionError('original semantic read '+str(p))
 return original_open(p,*a,**kw)
def guarded_stat(p,*a,**kw):
 if str(p) in blocked:blocked_reads.append(str(p));raise AssertionError('original semantic stat '+str(p))
 return original_stat(p,*a,**kw)
with patch.object(Path,'open',guarded_open),patch.object(Path,'stat',guarded_stat):
 for mp,pin,m in zip((r.MANIFEST_PATH,r.V2_MANIFEST_PATH),(r.PINNED_MANIFEST_SHA256,r.V2_MANIFEST_SHA256),models):
  reader=r.ArchiveResolver(manifest_path=mp,expected_manifest_sha256=pin)
  for e in m['entries']:
   b=reader.read_bytes(e['semanticPath'],expected_sha256='sha256:'+e['sha256'],expected_size=e['bytes'],force_archive=True)
   assert len(b)==e['bytes'] and hashlib.sha256(b).hexdigest()==e['sha256']
   if e['archive']['compression']=='none':assert reader.resolve_path(e['semanticPath'],force_archive=True).read_bytes()==b
   rows.append({'semanticPath':e['semanticPath'],'archive':e['archive'],'size':len(b),'sha256':hashlib.sha256(b).hexdigest()})
assert not blocked_reads
# Producer controls execute on actual source, temporary payloads confined here.
t=load(BASE/'test_archive_resolver.py','reviewed_controls')
real_mkdtemp=tempfile.mkdtemp
def owned_tmp(*a,**kw):kw['dir']=HERE;return real_mkdtemp(*a,**kw)
with patch.object(tempfile,'mkdtemp',owned_tmp):
 result=unittest.TextTestRunner(verbosity=1).run(unittest.defaultTestLoader.loadTestsFromModule(t))
assert result.wasSuccessful()
report={'scope':'archive source/tool resolver bytes only; no compiler execution or whole public proof qualification','sourceSha256':'28c7ddd5974534efc13cb93d6030ce64fadb752e6c98212205f02c4b9787a8d4','testsSha256':'aa43ec14f5772e0dd8909c83925a7c7126eb48cdaf00375cb48081c65c3fe321','manifestPins':[r.PINNED_MANIFEST_SHA256,r.V2_MANIFEST_SHA256],'manifestEntryCounts':[len(m['entries']) for m in models],'forcedArchiveRows':rows,'originalSemanticReads':blocked_reads,'testsRun':result.testsRun}
(HERE/'replay-result.json').write_text(json.dumps(report,indent=2)+'\n');print('replayed',len(rows),'rows; controls',result.testsRun)
