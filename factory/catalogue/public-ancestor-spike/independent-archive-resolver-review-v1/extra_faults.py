import copy,hashlib,importlib.util,json,tempfile,shutil
from pathlib import Path
HERE=Path(__file__).resolve().parent;BASE=HERE.parent/'archive-resolver-v1'
def load(p,n):
 s=importlib.util.spec_from_file_location(n,p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
r=load(BASE/'archive_resolver.py','strict_resolver');t=load(BASE/'test_archive_resolver.py','fixtures');faults=[]
mutations={'observed_hash':lambda e:e['observedLive'].update(sha256='0'*64),'archive_bool_size':lambda e:e['archive'].update(bytes=True),'negative_size':lambda e:e.update(bytes=-1),'path_traversal':lambda e:e['archive'].update(path='../payload.bin'),'path_empty_part':lambda e:e['archive'].update(path='dir//payload.bin'),'semantic_alias':lambda e:e.update(semanticPath=e['semanticPath']+'/../Header.h'),'alias_other':lambda e:e.update(aliases=['/other/Header.h']),'gzip_bool_size':lambda e:e['archive'].update(decompressedBytes=True)}
for name,mut in mutations.items():
 with tempfile.TemporaryDirectory(dir=HERE) as tmp:
  archive,manifest,pin,original,raw=t.fixture(Path(tmp),mode='gzip' if name=='gzip_bool_size' else 'none');m=json.loads(manifest.read_text());mut(m['entries'][0]);manifest.write_text(json.dumps(m));pin=hashlib.sha256(manifest.read_bytes()).hexdigest()
  try:r.ArchiveResolver(manifest_path=manifest,expected_manifest_sha256=pin,archive_root=archive,allow_fixture=True)
  except r.ArchiveResolverError as e:faults.append({'fault':name,'reason':str(e)})
  else:raise AssertionError(name)
with tempfile.TemporaryDirectory(dir=HERE) as tmp:
 archive,manifest,pin,original,raw=t.fixture(Path(tmp));reader=r.ArchiveResolver(manifest_path=manifest,expected_manifest_sha256=pin,archive_root=archive,allow_fixture=True)
 for name,action in [('wrong_expected_hash',lambda:reader.read_bytes(original,expected_sha256='sha256:'+'0'*64,force_archive=True)),('resolve_truthy_flag',lambda:reader.resolve_path(original,force_archive='yes')),('fixture_truthy_flag',lambda:r.ArchiveResolver(allow_fixture='yes')),('unapproved_pin',lambda:r.ArchiveResolver(expected_manifest_sha256='0'*64))]:
  try:action()
  except r.ArchiveResolverError as e:faults.append({'fault':name,'reason':str(e)})
  else:raise AssertionError(name)
(HERE/'extra-fault-result.json').write_text(json.dumps({'faultCount':len(faults),'faults':faults},indent=2)+'\n');print(len(faults))
