import sys,json,gzip,copy,hashlib,importlib.util
from pathlib import Path
from unittest.mock import patch
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[4];sys.path.insert(0,str(ROOT));sys.dont_write_bytecode=True
source=HERE/'final-snapshot/consumer.py';spec=importlib.util.spec_from_file_location('fixed_frozen',source);c=importlib.util.module_from_spec(spec);spec.loader.exec_module(c)
c.__file__=str(ROOT/'factory/catalogue/public-ancestor-consumer/consumer.py')
digest=lambda b:hashlib.sha256(b).hexdigest()
proof_path=ROOT/'factory/catalogue/public-ancestor-spike/public-ancestor-evidence-v2.json.gz';stored=proof_path.read_bytes();assert 'sha256:'+digest(stored)==c.FINAL_PROOF_SHA256
raw=gzip.decompress(stored);assert len(raw)==c.FINAL_PROOF_RAW_BYTES and 'sha256:'+digest(raw)==c.FINAL_PROOF_RAW_SHA256
r=json.loads(raw)['resolution'];del raw,stored
candidate_path=ROOT/'factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json';a_raw=candidate_path.read_bytes();a=json.loads(a_raw);m=json.loads((HERE/'snapshot/derivation-manifest.json').read_bytes())
c._validate_derivation_manifest(m,a,a_raw,candidate_path.name,r)
faults=[]
def reject(label,bad,resolution=r):
    try:c._validate_derivation_manifest(bad,a,a_raw,candidate_path.name,resolution)
    except c.ConsumerError as e:faults.append({'fault':label,'reason':str(e)})
    else:raise AssertionError('accepted '+label)
for k,v in m['coverage'].items():
    if isinstance(v,int):
        for label,value in [('increment',v+1),('float',float(v)),('bool',True)]:
            bad=copy.deepcopy(m);bad['coverage'][k]=value;reject(k+':'+label,bad)
    elif isinstance(v,dict):
        for inner,value in v.items():
            for label,new in [('float',float(value)),('bool',True),('increment',value+1)]:
                bad=copy.deepcopy(m);bad['coverage'][k][inner]=new;reject(k+'/'+inner+':'+label,bad)
for label,value in [('float',108272.0),('bool',True),('increment',108273)]:
    bad=copy.deepcopy(m);bad['base']['symbolCount']=value;reject('baseCount:'+label,bad)
bad=copy.deepcopy(m);bad['coverage']['extraField']=0;reject('extra_coverage_field',bad)
bad=copy.deepcopy(m);del bad['coverage']['publicCompilerChildGroups'];reject('missing_group_field',bad)
bad_r=dict(r);bad_r['publicCompilerChildRecordCount']=2014;reject('changed_resolution_hash',m,bad_r)
out=HERE/'fixed-rollback';out.mkdir(exist_ok=True);cp=out/candidate_path.name;mp=out/'catalogue-public-source-v1.manifest.json';cp.write_bytes(b'originalcandidate');mp.write_bytes(b'originalmanifest')
original=c.os.replace;calls=0
def fail_second(src,dst):
    global calls
    calls+=1
    if calls==2:raise OSError('independent repaired pair fault')
    return original(src,dst)
try:
    with patch.object(c.os,'replace',side_effect=fail_second):
        try:c.write_candidate_bundle_atomic(cp,mp,a,m,resolution=r)
        except OSError as e:assert 'independent repaired' in str(e)
        else:raise AssertionError('pair failure ignored')
    assert cp.read_bytes()==b'originalcandidate' and mp.read_bytes()==b'originalmanifest'
    assert len(list(out.iterdir()))==2
finally:
    cp.unlink();mp.unlink();out.rmdir()
report={'sourceSha256':digest(source.read_bytes()),'testsSha256':digest((HERE/'final-snapshot/test_consumer.py').read_bytes()),'candidateSha256':digest(a_raw),'baselineActualSidecarAccepted':True,'faultCount':len(faults),'faults':faults,'actualCandidatePairRollback':True,'producerOutputsTouched':False,'proofStoredAndRawPinsUnchanged':True}
(HERE/'repaired-coverage-result.json').write_text(json.dumps(report,indent=2)+'\n');print(len(faults),'actualsidecar faults rejected &pair rollback preserved')
