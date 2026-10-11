import sys,json,importlib.util,copy
from pathlib import Path
from unittest.mock import patch
HERE=Path(__file__).resolve().parent;ROOT=HERE.parents[4];sys.path.insert(0,str(ROOT));sys.dont_write_bytecode=True
s=importlib.util.spec_from_file_location('frozen_final',HERE/'snapshot/consumer.py');c=importlib.util.module_from_spec(s);s.loader.exec_module(c)
c.__file__=str(ROOT/'factory/catalogue/public-ancestor-consumer/consumer.py')
guard=c._load_pinned_guard(ROOT/'factory/catalogue/public-ancestor-spike/exact_public_ancestor.py',c.FINAL_GUARD_SHA256)
proof=ROOT/'factory/catalogue/public-ancestor-spike/public-ancestor-evidence-v2.json.gz';faults=[]
for label,changes in [('wrong_stored',{'expected_sha256':'sha256:'+'0'*64}),('wrong_raw_hash',{'expected_raw_sha256':'sha256:'+'0'*64}),('wrong_raw_size',{'expected_raw_bytes':c.FINAL_PROOF_RAW_BYTES+1}),('bool_raw_size',{'expected_raw_bytes':True})]:
    kw={'expected_sha256':c.FINAL_PROOF_SHA256,'expected_raw_sha256':c.FINAL_PROOF_RAW_SHA256,'expected_raw_bytes':c.FINAL_PROOF_RAW_BYTES};kw.update(changes)
    try:guard.load_artifact(proof,**kw)
    except ValueError as e:faults.append({'fault':label,'productionLoaderReason':str(e)})
    else:raise AssertionError(label)
candidate_path=ROOT/'factory/catalogue/public-ancestor-consumer/catalogue-public-source-v1.json';a=json.loads(candidate_path.read_bytes());m=json.loads((HERE/'snapshot/derivation-manifest.json').read_bytes())
out=HERE/'rollback';out.mkdir(exist_ok=True);cp=out/candidate_path.name;mp=out/'catalogue-public-source-v1.manifest.json';cp.write_bytes(b'preserved-candidate');mp.write_bytes(b'preserved-sidecar')
original=c.os.replace;calls=0
def fail_second(src,dst):
    global calls
    calls+=1
    if calls==2:raise OSError('independent sidecar replacement fault')
    return original(src,dst)
try:
    with patch.object(c.os,'replace',side_effect=fail_second):
        try:c.write_candidate_bundle_atomic(cp,mp,a,m)
        except OSError as e:assert 'independent sidecar' in str(e)
        else:raise AssertionError('rollback fault ignored')
    assert cp.read_bytes()==b'preserved-candidate' and mp.read_bytes()==b'preserved-sidecar'
    assert sorted(p.name for p in out.iterdir())==[cp.name,mp.name]
finally:
    cp.unlink();mp.unlink();out.rmdir()
(HERE/'gzip-rollback-result.json').write_text(json.dumps({'actualProductionGzipFaults':faults,'actualCandidatePairRollback':True,'noTemporaryResidue':True,'producerOutputsTouched':False},indent=2)+'\n')
print('4actualgzip faults rejected; actualcandidate pair rollback preserved')
