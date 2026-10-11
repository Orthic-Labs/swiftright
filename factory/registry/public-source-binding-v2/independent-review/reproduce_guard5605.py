import contextlib,hashlib,io,json,sys
from pathlib import Path
ROOT=Path.cwd(); HERE=ROOT/'factory/registry/public-source-binding-v2/independent-review'; V1=ROOT/'factory/registry/public-source-binding-v1'
GUARD=ROOT/'factory/registry/public-source-binding-v2/versioned-snapshots/comparator-guard-v2/compare_final_candidate.py'
def sha(b):return hashlib.sha256(b).hexdigest()
source=GUARD.read_bytes(); assert sha(source)=='5605a749d29dcf20af266765e710665cec428e9a6089fbef45dd7f0ba2f1907c'
(HERE/'preimages/compare_final_candidate.py.5605a7').write_bytes(source)
scope={'__name__':'independent_review','__file__':str(GUARD)};exec(compile(source,str(GUARD),'exec'),scope)
manifest_path=V1/'manifest-usr-v1.json'; expected_path=V1/'expected-registry-membership.json'
manifest=json.loads(manifest_path.read_text()); expected=json.loads(expected_path.read_text());
manifest['blocks'][0]['symbols'][0],manifest['blocks'][0]['symbols'][1]=manifest['blocks'][0]['symbols'][1],manifest['blocks'][0]['symbols'][0]
expected['blocks']=[{'blockId':b['id'],'symbolIndex':i,'usr':u.removeprefix('usr:')} for b in manifest['blocks'] for i,u in enumerate(b['symbols'])]
virtual={manifest_path:json.dumps(manifest).encode(),expected_path:json.dumps(expected).encode()}
read_bytes=Path.read_bytes;read_text=Path.read_text
counts={}
def race(p):
 if p.resolve() in virtual:
  counts[p.resolve()]=counts.get(p.resolve(),0)+1
  if counts[p.resolve()]>1:return virtual[p.resolve()]
 return read_bytes(p)
Path.read_bytes=race
Path.read_text=lambda p,*args,**kwargs:virtual[p.resolve()].decode() if p.resolve() in virtual else read_text(p,*args,**kwargs)
output=HERE/'guard5605-coherent-input-receipt.json'; assert not output.exists()
sys.argv=['guard',str(V1/'archive/inputs/catalogue.json'),'--output',str(output)]
try:
 with contextlib.redirect_stdout(io.StringIO()): result=scope['main']()
finally:Path.read_bytes=read_bytes;Path.read_text=read_text
receipt=json.loads(output.read_text());assert result==0 and receipt['status']=='stable-membership' and receipt['actualMembershipCount']==65
report={'guardSha256':sha(source),'fault':'coherent post-verification manifest & expected mutation accepted','status':receipt['status'],'blockCount':receipt['actualBlockCount'],'selectorCount':receipt['actualMembershipCount'],'productionBytesChanged':False,'reproducerSha256':sha(Path(__file__).read_bytes())}
report_path=HERE/'guard5605-fault-reproduction.json';report_path.write_text(json.dumps(report,indent=2)+'\n');print(sha(report_path.read_bytes()))
