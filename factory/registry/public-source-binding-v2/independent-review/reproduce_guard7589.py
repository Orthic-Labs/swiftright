import contextlib,hashlib,io,json,sys
from pathlib import Path
ROOT=Path.cwd(); HERE=ROOT/'factory/registry/public-source-binding-v2/independent-review'; V1=ROOT/'factory/registry/public-source-binding-v1'
GUARD=ROOT/'factory/registry/public-source-binding-v2/versioned-snapshots/comparator-guard-v1/compare_final_candidate.py'
def sha(b):return hashlib.sha256(b).hexdigest()
source=GUARD.read_bytes(); assert sha(source)=='7589dc6ff0754b66a380a0e59565fc05535d04f9f258ef58dab86035ad125659'
(HERE/'preimages/compare_final_candidate.py.7589dc').write_bytes(source)
scope={'__name__':'independent_review','__file__':str(GUARD)};exec(compile(source,str(GUARD),'exec'),scope)
manifest_path=V1/'manifest-usr-v1.json'; expected_path=V1/'expected-registry-membership.json'
manifest=json.loads(manifest_path.read_text()); expected=json.loads(expected_path.read_text());
for block in manifest['blocks']:block['symbols']=block['symbols'][:1]
expected['blocks']=[r for r in expected['blocks'] if r['symbolIndex']==0]
virtual={manifest_path:json.dumps(manifest).encode(),expected_path:json.dumps(expected).encode()}
read_bytes=Path.read_bytes;read_text=Path.read_text
Path.read_bytes=lambda p:virtual.get(p.resolve(),read_bytes(p))
Path.read_text=lambda p,*args,**kwargs:virtual[p.resolve()].decode() if p.resolve() in virtual else read_text(p,*args,**kwargs)
output=HERE/'guard7589-coherent-input-receipt.json'; assert not output.exists()
sys.argv=['guard',str(V1/'archive/inputs/catalogue.json'),'--output',str(output)]
try:
 with contextlib.redirect_stdout(io.StringIO()): result=scope['main']()
finally:Path.read_bytes=read_bytes;Path.read_text=read_text
receipt=json.loads(output.read_text());assert result==0 and receipt['status']=='stable-membership' and receipt['actualMembershipCount']==10
report={'guardSha256':sha(source),'fault':'coherent unpinned manifest & expected mutation accepted','status':receipt['status'],'blockCount':receipt['actualBlockCount'],'selectorCount':receipt['actualMembershipCount'],'productionBytesChanged':False,'reproducerSha256':sha(Path(__file__).read_bytes())}
report_path=HERE/'guard7589-fault-reproduction.json';report_path.write_text(json.dumps(report,indent=2)+'\n');print(sha(report_path.read_bytes()))
