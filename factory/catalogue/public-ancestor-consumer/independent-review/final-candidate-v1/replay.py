import sys, json, hashlib, importlib.util, copy, time
from pathlib import Path
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[4]
sys.path.insert(0,str(ROOT));sys.dont_write_bytecode=True
spec=importlib.util.spec_from_file_location('independent_frozen_consumer',HERE/'snapshot/consumer.py')
c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
c.__file__=str(ROOT/'factory/catalogue/public-ancestor-consumer/consumer.py')
c.ROOT=ROOT;c.BASE_PATH=ROOT/'factory/catalogue/evidence/catalogue.json'
c.GUARD_PATH=ROOT/'factory/catalogue/public-ancestor-spike/exact_public_ancestor.py'
c.FINAL_PROOF_PATH=ROOT/'factory/catalogue/public-ancestor-spike/public-ancestor-evidence-v2.json.gz'
c.GRAPH_ARCHIVE_FOLDER=ROOT/'factory/catalogue/raw-symbolgraph-archive-v1'
digest=lambda b:hashlib.sha256(b).hexdigest()
assert digest((HERE/'snapshot/consumer.py').read_bytes())=='f36223d607908414c4c99a1133b070744bc1276274797a09b747106dbf606e47'
assert digest((HERE/'snapshot/test_consumer.py').read_bytes())=='3c9700e8ed89f6856232e4043a94f811e793e075ee17b5d2ca72fa8cf0d46e5d'
candidate_path=ROOT/'factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json'
candidate_raw=candidate_path.read_bytes();candidate=json.loads(candidate_raw)
assert digest(candidate_raw)=='fd453b6345f83b49931c7194c2e1127538e2de4ceb0de4c25f715ac6d85ac4f2'
side_raw=(HERE/'snapshot/derivation-manifest.json').read_bytes();side=json.loads(side_raw)
assert digest(side_raw)=='322543df1789a202301ac159089ec33b20487fe268db90d90d3a2948888fbbb4'
base=json.loads(c.BASE_PATH.read_bytes());assert c._digest(c.BASE_PATH.read_bytes())==c.BASE_CATALOGUE_SHA256
link_raw=(ROOT/'factory/catalogue/compiler-cursor-spike/link-evidence.json').read_bytes();link=json.loads(link_raw)
assert c._digest(link_raw)==c.IMMUTABLE_LINK_SHA256
guard=c._load_pinned_guard(c.GUARD_PATH,c.FINAL_GUARD_SHA256)
print('production force-archive loader start',flush=True)
v,proof=guard.load_artifact(c.FINAL_PROOF_PATH,c.FINAL_PROOF_SHA256,prefer_archive=True,expected_raw_sha256=c.FINAL_PROOF_RAW_SHA256,expected_raw_bytes=c.FINAL_PROOF_RAW_BYTES)
r=proof['resolution'];print('production force-archive accepted',flush=True)
graph=c.raw_graph_usr_closure(link,str(ROOT));assert len(graph)==108272
refs=c.proof_hash_refs(proof)
kwargs=dict(raw_graph_usrs=graph,proof_hash=c.FINAL_PROOF_SHA256,guard_hash=c.FINAL_GUARD_SHA256,link_hash=c.IMMUTABLE_LINK_SHA256,proof_input_refs=refs,created_at=candidate['provenance']['createdAt'])
actual=c.merge_catalogue(base,r,**kwargs)
assert c.dump_bytes(actual)==candidate_raw
rebuilt=c.build_derivation_manifest(actual,r,candidate_path=candidate_path,proof_hash=c.FINAL_PROOF_SHA256,guard_hash=c.FINAL_GUARD_SHA256,link_hash=c.IMMUTABLE_LINK_SHA256,proof_input_refs=refs)
assert c.dump_bytes(rebuilt)==side_raw
assert candidate['symbols'][:108272]==base['symbols']
assert candidate['symbolGraph']==base['symbolGraph']
assert len(candidate['symbols'])==111576
additions=candidate['symbols'][108272:];assert len(additions)==3304
assert additions==sorted(additions,key=lambda a:a['usr'])
assert len({a['usr'] for a in candidate['symbols']})==111576
assert all(a['usr'] not in graph for a in additions)
excluded=[a for a in r['compilerInventory'] if (a.get('childEvidence') or {}).get('status')=='excluded-nonpublic-parent-api']
assert len(excluded)==5
assert not ({a['usr'] for a in excluded}&{a['usr'] for a in additions})
children=r['publicCompilerChildren'];dupes=[a for a in children if a['rawCardinality']>1]
assert len(children)==2008 and sum(a['rawCardinality'] for a in children)==2013
assert len(dupes)==5 and all(a['rawCardinality']==2 for a in dupes)
faults=[]
def reject(label,resolution):
    try:c.merge_catalogue(base,resolution,**kwargs)
    except c.ConsumerError as e:faults.append({'fault':label,'reason':str(e)})
    else:raise AssertionError('accepted '+label)
for field,value in [('publicCompilerChildRecordCount',True),('publicCompilerChildRecordCount',2008),('publicCompilerChildUsrCount',True),('publicCompilerChildUsrCount',2013)]:
    bad=dict(r);bad[field]=value;reject(field+':'+str(value),bad)
for index,row in enumerate(dupes):
    bad=dict(r);badchildren=list(children);pos=children.index(row);badrow=dict(row);badrow['rawCardinality']=1;badchildren[pos]=badrow;bad['publicCompilerChildren']=badchildren
    reject('duplicate_cardinality:'+str(index),bad)
bad=dict(r);badchildren=list(children);badrow=dict(children[0]);badrow['rawCardinality']=True;badchildren[0]=badrow;bad['publicCompilerChildren']=badchildren;reject('bool_group_cardinality',bad)
pass_path=ROOT/'factory/catalogue/public-ancestor-spike/public-ancestor-faults-v2.json'
assert digest(pass_path.read_bytes())=='688358ac02748fc785e3997729d2978b44861b562b91a98a0e6f7e440256f944'
report={'accepted':True,'scope':'actual production forced-archive proof acceptance & exact additive catalogue derivation; observed SDK source/index inventory scope','consumerSha256':digest((HERE/'snapshot/consumer.py').read_bytes()),'testsSha256':digest((HERE/'snapshot/test_consumer.py').read_bytes()),'candidateSha256':digest(candidate_raw),'sidecarSha256':digest(side_raw),'proofStoredSha256':c.FINAL_PROOF_SHA256,'proofRawSha256':c.FINAL_PROOF_RAW_SHA256,'proofRawBytes':c.FINAL_PROOF_RAW_BYTES,'guardSha256':c.FINAL_GUARD_SHA256,'baseSymbols':108272,'additions':3304,'outputSymbols':111576,'basePrefixExact':True,'graphMetadataExact':True,'candidateReconstructedBytesEqual':True,'sidecarReconstructedBytesEqual':True,'groups':2008,'rawChildRecords':2013,'duplicatePairs':[{'usr':a['usr'],'rawCardinality':a['rawCardinality'],'rawOccurrences':a['rawOccurrences']} for a in dupes],'excludedGetters':[{'usr':a['usr'],'module':a['module'],'line':a['line']} for a in excluded],'countFaults':faults,'mainPassReceiptSha256':digest(pass_path.read_bytes())}
(HERE/'replay-result.json').write_text(json.dumps(report,indent=2)+'\n')
print('exactcandidate &sidecar replay accepted;10 count faults rejected',flush=True)
