#!/usr/bin/env python3
"""Pure byte-archive controls; mock bytes never compiled or executed."""
from pathlib import Path
import importlib.util,json,gzip,hashlib,tarfile,io,copy
OUT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('restore',OUT/'restore.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
def sha(b):return 'sha256:'+hashlib.sha256(b).hexdigest()
def fixture(name,*,part_bad=False,member_bad=False,chunk_bad=False):
 root=OUT/'offline-controls'/name;root.mkdir(parents=True,exist_ok=False);data=b'UNEXECUTED MOCK ARCHIVE BYTES';h=sha(data);member='../escape' if member_bad else f'objects/{h[7:]}/00000'
 chunk=root/'chunk.tar.gz'
 with chunk.open('wb') as stream:
  with gzip.GzipFile(filename='',mode='wb',fileobj=stream,mtime=0) as z:
   with tarfile.open(fileobj=z,mode='w|') as t:
    x=tarfile.TarInfo(member);x.size=len(data);t.addfile(x,io.BytesIO(data))
 ref={'path':'chunk.tar.gz','sha256':sha(chunk.read_bytes()),'bytes':chunk.stat().st_size,'payloadBytes':len(data),'members':1}
 part={'chunk':'chunk.tar.gz','member':member,'sha256':sha(b'wrong') if part_bad else h,'bytes':len(data)}
 m={'kind':'owned-scratch-byte-preservation','version':2,'roots':[str(mod.CACHE/'mock-never-executed')],'files':[{'path':str(mod.CACHE/'mock-never-executed/payload'),'sha256':h,'bytes':len(data),'mode':0o644}],'objects':{h:{'sha256':h,'bytes':len(data),'parts':[part]}},'chunks':[ref],'symlinks':[]}
 raw=json.dumps(m,sort_keys=True).encode();mp=root/'manifest.json.gz';mp.write_bytes(gzip.compress(raw,mtime=0));d={'manifest':{'path':mp.name,'sha256':sha(mp.read_bytes()),'bytes':mp.stat().st_size,'rawBytes':len(raw),'rawSha256':sha(raw)},'chunks':[ref],'roots':m['roots']};dp=root/'descriptor.json';dp.write_text(json.dumps(d))
 if chunk_bad:chunk.write_bytes(b'CORRUPT')
 return dp,sha(dp.read_bytes())
def rejection(name,fn,expected):
 try:fn()
 except ValueError as e:assert expected in str(e),(name,e);return {'status':'PASS','rejection':str(e)}
 raise AssertionError(name+' accepted')
def main():
 result={};p,h=fixture('positive');r=mod.verify(p,h);assert r['status']=='PASS' and r['uniqueObjects']==1;result['actual-verifier-positive']='PASS'
 result['descriptor-pin']=rejection('descriptor-pin',lambda:mod.verify(p,'sha256:'+'0'*64),'descriptor hash differs')
 for name,key,message in [('raw-part','part_bad','raw part hash differs'),('chunk-pin','chunk_bad','chunk hash/size differs'),('member-traversal','member_bad','unsafe archive path')]:
  f,hf=fixture(name,**{key:True});result[name]=rejection(name,lambda:mod.verify(f,hf),message)
 result['internal-output-policy']=rejection('output-policy',lambda:mod.verify(p,h,output=OUT/'forbidden-output'),'rehydration requires fresh internal output');assert not (OUT/'forbidden-output').exists()
 return {'scope':'offline byte fixtures, no native/compiler execution','controls':result}
if __name__=='__main__':
 r=main();(OUT/'controls-results.json').write_text(json.dumps(r,indent=2,sort_keys=True)+'\n');print(json.dumps(r))
