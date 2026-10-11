#!/usr/bin/env python3
from __future__ import annotations
import gzip, hashlib, json, shutil
from pathlib import Path
ROOT=Path(__file__).resolve().parents[4]; OWN=Path(__file__).resolve().parent
V1=ROOT/'factory/catalogue/public-ancestor-spike/archive-inputs-v1/archive-input-mapping.json'
MAIN=ROOT/'factory/catalogue/public-ancestor-spike/public-ancestor-evidence-v2.json'
GUARD=ROOT/'factory/catalogue/public-ancestor-spike/external-owner-capture/clang-owner-guard-v1/capture-inputs.json'
SWIFT=ROOT/'factory/catalogue/public-ancestor-spike/external-owner-capture/swift-stdlib-process-v2/swift16-evidence.json'

def dig(p):
 h=hashlib.sha256();n=0
 with p.open('rb') as f:
  while b:=f.read(1<<20):h.update(b);n+=len(b)
 return n,h.hexdigest()
def sh(x):return str(x).removeprefix('sha256:')
def add(es,path,bytes_,sha,archive,role,prov,aliases=None):
 sha=sh(sha); bytes_=int(bytes_) if bytes_ is not None else None
 if path in es:
  old=es[path]
  if old['sha256']!=sha or (old['bytes'] is not None and bytes_ is not None and old['bytes']!=bytes_): raise SystemExit(f'conflicting original descriptor: {path}')
  if old['bytes'] is None: old['bytes']=bytes_
  old['roles'].append(role);old['provenance'].append(prov)
  if aliases: old['aliases']=sorted(set(old.get('aliases',[])+aliases))
 else: es[path]={'semanticPath':path,'bytes':bytes_,'sha256':sha,'archive':archive,'roles':[role],'provenance':[prov],**({'aliases':sorted(set(aliases))} if aliases else {})}
def main():
 v1=json.loads(V1.read_text()); base={x['semanticPath']:x for x in v1['entries']}
 # Materialize distinct swift-frontend archive before recorded-tool scan.
 frontend_archive=OWN/'archive/tools/swift-frontend.archive.gz'
 if not frontend_archive.exists(): shutil.copyfile(ROOT/'factory/catalogue/public-ancestor-spike/external-owner-header-index-v1/developer-spatial-symbols/staging/swiftc.archive.gz',frontend_archive)
 es={}
 # Main evidence records all internal probe/request/header/index/receipt/tool read sites.
 main=json.loads(MAIN.read_text())
 def repo_for(original, repository=None):
  if repository:
   p=ROOT/repository
   if p.is_file(): return str(p.relative_to(ROOT))
  if original.startswith('/Volumes/D/claude/swiftright/'):
   p=Path(original.removeprefix('/Volumes/D/claude/swiftright/'))
   if (ROOT/p).is_file(): return str(p)
  if original in base: return base[original]['archive']['path']
  return None
 def record(k,x,role,source):
  if not isinstance(x,dict) or 'path' not in x or 'sha256' not in x:return
  original=x['path']; rp=repo_for(original,x.get('repositoryPath'))
  if rp is None and original.endswith('/swift-frontend'):
   rp='factory/catalogue/public-ancestor-spike/archive-inputs-v2/archive/tools/swift-frontend.archive.gz'
  if rp is None: raise SystemExit(f'no archive for recorded path: {original}')
  af=ROOT/rp
  if not af.is_file(): raise SystemExit(f'missing archive path: {rp}')
  n,h=dig(af)
  # gzip copy has semantic bytes/hash separate from archive bytes/hash.
  if rp.endswith('.gz') and (original.endswith('/swiftc') or original.endswith('/swift-frontend') or base.get(original,{}).get('archive',{}).get('compression')=='gzip'):
   with gzip.open(af,'rb') as f:
    hh=hashlib.sha256(); nn=0
    while b:=f.read(1<<20):hh.update(b);nn+=len(b)
   expected_n=x.get('bytes') or nn
   if (nn,hh.hexdigest())!=(expected_n,sh(x['sha256'])):raise SystemExit(f'gzip archive mismatch: {original}')
   a={'path':rp,'compression':'gzip','bytes':n,'sha256':h,'decompressedBytes':nn,'decompressedSha256':hh.hexdigest()}
  else:
   expected_n=x.get('bytes')
   if expected_n is None:expected_n=n
   if n!=expected_n or h!=sh(x['sha256']):raise SystemExit(f'archive mismatch {original}: {n}/{h} != {expected_n}/{sh(x["sha256"])}')
   a={'path':rp,'compression':'none','bytes':n,'sha256':h}
  add(es,original,expected_n,sh(x['sha256']),a,role,{'source':source,'key':k,'repositoryPath':x.get('repositoryPath')},x.get('physicalAliases'))
 for k,x in main.get('inputs',{}).items():record(k,x,'main recorded input',str(MAIN.relative_to(ROOT)))
 for k,x in main.get('tools',{}).items():record('tool:'+k,x,'main recorded tool',str(MAIN.relative_to(ROOT)))
 def recurse(x,key,source,role):
  if isinstance(x,dict):
   if 'path' in x and 'sha256' in x: record(key,x,role,source)
   for k,v in x.items():
    if isinstance(v,(dict,list)):recurse(v,key+'/'+k,source,role)
  elif isinstance(x,list):
   for i,v in enumerate(x):recurse(v,f'{key}[{i}]',source,role)
 # Swift16 capture manifest, tools, lineage, internal probes/requests.
 recurse(SWIFT,'swift16',str(SWIFT.relative_to(ROOT)),'Swift16 recorded capture input')
 # Clang owner guard includes original v3/v2 probes, requests, raw process outputs & physical aliases.
 guard=json.loads(GUARD.read_text())
 for k,x in guard.items():
  if isinstance(x,dict) and 'path' in x and 'sha256' in x:
   record(k,x,'Clang recorded input/tool/output',str(GUARD.relative_to(ROOT)))
 # Production source dependencies from main evidence are internal helper read sites.
 # compiler_children has an exact reviewed snapshot because live path changed after evidence freeze.
 dep_overrides={'/Volumes/D/claude/swiftright/factory/catalogue/public-ancestor-spike/compiler_children.py':'factory/catalogue/public-ancestor-spike/lineage-physical10-cleared/compiler_children.py'}
 for k,x in main.get('dependencies',{}).items():
  if isinstance(x,dict) and x.get('path') in dep_overrides:
   y=dict(x); y['repositoryPath']=dep_overrides[x['path']]; record(k,y,'main production dependency exact preimage',str(MAIN.relative_to(ROOT)))
  else: record(k,x,'main production dependency',str(MAIN.relative_to(ROOT)))
 # Add swift-frontend as distinct original path; same bytes as swiftc but separate archived copy.
 frontend='/Applications/Xcode-27-RC.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-frontend'
 fp=Path(frontend); n,h=dig(fp); gz=OWN/'archive/tools/swift-frontend.archive.gz'
 if not gz.exists(): shutil.copyfile(ROOT/'factory/catalogue/public-ancestor-spike/external-owner-header-index-v1/developer-spatial-symbols/staging/swiftc.archive.gz',gz)
 an,ah=dig(gz)
 with gzip.open(gz,'rb') as f:
  hh=hashlib.sha256();nn=0
  while b:=f.read(1<<20):hh.update(b);nn+=len(b)
 if (n,h)!=(nn,hh.hexdigest()): raise SystemExit('swift-frontend live/archive mismatch')
 add(es,frontend,n,h,{'path':str(gz.relative_to(ROOT)),'compression':'gzip','bytes':an,'sha256':ah,'decompressedBytes':nn,'decompressedSha256':hh.hexdigest()},'main compiler driver (separate swift-frontend path)',{'source':str(MAIN.relative_to(ROOT)),'key':'tools.compiler','repositoryPath':None})
 # Remove entries already fully represented in v1; v2 contains only additive mappings.
 extras=[]
 for p,x in es.items():
  if p in base:
   if x['sha256']!=base[p]['sha256'] or x['bytes']!=base[p]['bytes']: raise SystemExit(f'base conflict {p}')
   continue
  extras.append(x)
 out={'schema':'factory.public-ancestor.archive-input-mapping.v1','kind':'additive-force-archive-inputs-v2','status':'frozen-additive-inputs-only','baseMapping':{'path':str(V1.relative_to(ROOT)),'sha256':dig(V1)[1]},'policy':{'archivePathsRepositoryRelative':True,'maxArchiveBytes':100000000,'noArchiveAliasInvented':True},'sourceScope':{'mainEvidence':str(MAIN.relative_to(ROOT)),'mainEvidenceSha256':dig(MAIN)[1],'clangGuard':str(GUARD.relative_to(ROOT)),'clangGuardSha256':dig(GUARD)[1],'swift16Evidence':str(SWIFT.relative_to(ROOT)),'swift16EvidenceSha256':dig(SWIFT)[1]},'entries':sorted(extras,key=lambda x:x['semanticPath'])}
 (OWN/'archive-input-mapping.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n');print({'base':len(base),'extras':len(extras)})
if __name__=='__main__':main()
