#!/usr/bin/env python3
"""Preserve exact owned scratch bytes; no deletion or native execution."""
from pathlib import Path
import os,json,gzip,tarfile,hashlib,io,subprocess,datetime,collections
ROOT=Path('/Volumes/D/claude/swiftright');CACHE=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory');OUT=Path(__file__).resolve().parent
LIMIT=24_000_000
EXCLUDE={CACHE/'sr1/git-root',CACHE/'catalogue',CACHE/'sr1/f1-residuals',CACHE/'padding-origin-fresh-v1',CACHE/'sr1/padding-origin-fresh-v1',CACHE/'compiler-tool-reader-review-v1',CACHE/'compiler-tool-reader-review-v2',CACHE/'compiler-tool-reader-review-v3'}
def digest(raw):return 'sha256:'+hashlib.sha256(raw).hexdigest()
def hashfile(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  while b:=f.read(1024*1024):h.update(b)
 return 'sha256:'+h.hexdigest()
def inside(path,root):
 try:Path(path).relative_to(root);return True
 except ValueError:return False
def role(p):
 if '.git' in p.parts:return 'copied-repository-state'
 if p.suffix in ('.o','.pcm','.swiftdeps','.d','.dia','.mdb','.db') or 'index' in p.parts:return 'generated-intermediate-preserved'
 if 'Products' in p.parts or p.suffix in ('.swiftmodule','.dylib','.a','.exe') or p.stat().st_mode&0o111:return 'compiled-product-preserved'
 if p.suffix in ('.swift','.patch','.rs','.h','.c','.cpp') or p.name.startswith('Package.'):return 'source-preserved'
 return 'logs-receipts-data-preserved'
def snapshot(roots):
 ps=subprocess.check_output(['ps','-axo','pid=,ppid=,command='],text=True)
 active=[s.strip() for s in ps.splitlines() if any(str(r) in s for r in roots) and 'archive.py' not in s]
 result=subprocess.run(['/usr/sbin/lsof','-nP','-Fpn'],capture_output=True,text=True,timeout=45)
 assert result.returncode in (0,1),result.returncode
 paths=[s[1:] for s in result.stdout.splitlines() if s.startswith('n') and any(inside(s[1:],r) for r in roots)]
 assert not active and not paths,(active,paths)
 return {'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'processMatches':active,'openPaths':paths,'lsofExitCode':result.returncode}
def roots():
 old=json.loads((ROOT/'factory/pipeline/workspace-cleanup-audit-v1/report.json').read_text())
 result=[CACHE/'sr1/runtime-additions']+[Path(x['path']) for x in old['nativeControlDirectoryInventory'] if x['status'].startswith('HOLD')]
 return sorted({p for p in result if p not in EXCLUDE and p.is_dir()},key=str)
class Chunks:
 def __init__(self):self.number=0;self.bytes=0;self.members=0;self.entries=[];self.tar=None
 def open(self):
  self.number+=1;self.path=OUT/'chunks'/f'chunk-{self.number:05d}.tar.gz';self.path.parent.mkdir(exist_ok=True)
  self.raw=self.path.open('xb');self.gz=gzip.GzipFile(filename='',mode='wb',fileobj=self.raw,mtime=0,compresslevel=6);self.tar=tarfile.open(mode='w|',fileobj=self.gz);self.bytes=0;self.members=0
 def close(self):
  if self.tar is None:return
  self.tar.close();self.gz.close();self.raw.close();assert self.path.stat().st_size<=50_000_000
  self.entries.append({'path':str(self.path.relative_to(OUT)),'sha256':hashfile(self.path),'bytes':self.path.stat().st_size,'payloadBytes':self.bytes,'members':self.members});self.tar=None
 def add(self,h,part,data):
  if self.tar is None:self.open()
  if self.bytes+len(data)>LIMIT or self.members>=10000:self.close();self.open()
  name=f'objects/{h.removeprefix("sha256:")}/{part:05d}';info=tarfile.TarInfo(name);info.size=len(data);info.mode=0o600;info.mtime=0
  self.tar.addfile(info,io.BytesIO(data));self.bytes+=len(data);self.members+=1
  return {'chunk':str(self.path.relative_to(OUT)),'member':name,'bytes':len(data),'sha256':digest(data)}
def main():
 selected=roots();before=snapshot(selected);writer=Chunks();objects={};rows=[];links=[];dirs=[];counts=collections.Counter();logical=0
 for root in selected:
  for base,subdirs,files in os.walk(root,followlinks=False):
   subdirs.sort();files.sort();base=Path(base);dirs.append({'path':str(base),'mode':base.stat().st_mode&0o7777})
   for n in subdirs+files:
    p=base/n
    if p.is_symlink():links.append({'path':str(p),'target':os.readlink(p)})
   subdirs[:]=[x for x in subdirs if not (base/x).is_symlink()]
   for n in files:
    p=base/n
    if p.is_symlink():continue
    assert p.is_file(),p
    stat=p.stat();h=hashfile(p)
    if h not in objects:
     parts=[];actual=hashlib.sha256()
     with p.open('rb') as f:
      i=0
      while data:=f.read(LIMIT):actual.update(data);parts.append(writer.add(h,i,data));i+=1
     assert 'sha256:'+actual.hexdigest()==h,p
     objects[h]={'sha256':h,'bytes':stat.st_size,'parts':parts}
    assert objects[h]['bytes']==stat.st_size
    after=p.stat();assert (stat.st_size,stat.st_mtime_ns,stat.st_ino)==(after.st_size,after.st_mtime_ns,after.st_ino),p
    tag=role(p);counts[tag]+=stat.st_size;logical+=stat.st_size;rows.append({'path':str(p),'sha256':h,'bytes':stat.st_size,'mode':stat.st_mode&0o7777,'mtimeNs':stat.st_mtime_ns,'role':tag})
    if len(rows)%10000==0:print(json.dumps({'files':len(rows),'uniqueObjects':len(objects),'logicalBytes':logical,'chunks':writer.number}),flush=True)
 writer.close();after=snapshot(selected)
 # Source/evidence refs remain metadata only; no schema admission or changed reader aliases.
 manifest={'version':2,'candidateOnly':True,'kind':'owned-scratch-byte-preservation','roots':[str(r) for r in selected],'excludedRoots':[str(r) for r in sorted(EXCLUDE,key=str)],'before':before,'after':after,'files':rows,'symlinks':links,'directories':dirs,'objects':objects,'chunks':writer.entries,'logicalBytes':logical,'uniqueRawBytes':sum(x['bytes'] for x in objects.values()),'compressedBytes':sum(x['bytes'] for x in writer.entries),'rolesBytes':dict(counts),'classification':'All compiled Products & intermediates preserved byte-exact. No object/product disposal inferred from suffix; no legacy missing process receipt manufactured. Quiescence is current process/open-file observation, distinct from historical job closure.'}
 raw=json.dumps(manifest,sort_keys=True,separators=(',',':')).encode()+b'\n';path=OUT/'archive-manifest.json.gz'
 with path.open('xb') as f:
  with gzip.GzipFile(filename='',mode='wb',fileobj=f,mtime=0) as z:z.write(raw)
 descriptor={'kind':manifest['kind'],'version':2,'candidateOnly':True,'manifest':{'path':path.name,'sha256':hashfile(path),'bytes':path.stat().st_size,'rawSha256':digest(raw),'rawBytes':len(raw)},'fileCount':len(rows),'uniqueObjects':len(objects),'roots':manifest['roots'],'excludedRoots':manifest['excludedRoots'],'logicalBytes':logical,'uniqueRawBytes':manifest['uniqueRawBytes'],'compressedBytes':manifest['compressedBytes'],'chunks':writer.entries,'rolesBytes':dict(counts),'before':before,'after':after,'deletionPerformed':False}
 (OUT/'archive-descriptor.json').write_text(json.dumps(descriptor,indent=2,sort_keys=True)+'\n');print(json.dumps({k:descriptor[k] for k in ('fileCount','uniqueObjects','logicalBytes','uniqueRawBytes','compressedBytes')}),flush=True)
if __name__=='__main__':main()
