"""Source-only Count1 r2 gate against archived actual metadata fixtures."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

def read(path: Path):
    return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def req(cond: bool, msg: str):
    if not cond: raise SystemExit(msg)

ap=argparse.ArgumentParser()
ap.add_argument('--source-root', required=True, help='capture-v3 source root')
ap.add_argument('--actual-root', required=True, help='archived root-actual-controls-v1 fixture root')
a=ap.parse_args(); source=Path(a.source_root).resolve(); actual=Path(a.actual_root).resolve()
r2=source/'root-metadata-controls-v1/root-metadata-controls-r2/resume-issued-coordinator-r2.ps1'
manifest=read(source/'root-stage-manifest.json')
binding=source/'integration-bindings.json'
rows=[x for x in manifest.get('files',[]) if x.get('path')=='factory/native/windows/padding-capture-lease-capture-v3/integration-bindings.json']
req(len(rows)==1, 'integration binding manifest row missing/duplicate')
req(rows[0].get('sha256')=='sha256:'+sha(binding), 'integration binding sha256 mismatch')
req(rows[0].get('bytes')==binding.stat().st_size, 'integration binding byte mismatch')
source_text=r2.read_text(encoding='utf-8')
req('$bindingEntry[0].sha256' in source_text, 'r2 missing sha256 field gate')
req('$bindingEntry[0].bytes' in source_text, 'r2 missing byte gate')
req('$bindingEntry[0].hash' not in source_text, 'r2 retained stale hash field')
lock_index=source_text.index("$lock='D:\\Claude\\desktop.lock'")
binding_index=source_text.index('$bindingEntry[0].sha256')
req(binding_index < lock_index, 'manifest gate occurs after lock declaration')
issued=actual/'observed-metadata-r1/coordinator-single-r1/issued-metadata.json'
tuple_file=actual/'observed-metadata-r1/coordinator-single-r1/candidate-tuple.json'
guard=actual/'observed-metadata-r1/actual/metadata-controls-r1.json'
review=actual/'root-metadata-review-r1.json'
schema=actual/'mac-schema-receipt-r1.json'
for p in (issued,tuple_file,guard,review,schema): req(p.is_file(), 'fixture missing: '+str(p))
idoc=read(issued); tdoc=read(tuple_file); g=read(guard); rv=read(review); sr=read(schema)
issued_hash=sha(issued); guard_hash=sha(guard)
req(issued_hash==g.get('issuedMetadataSha256'), 'fixture issued hash does not join guard')
req(issued_hash==rv.get('issuedMetadataSha256'), 'fixture issued hash does not join review')
req(guard_hash==rv.get('guardControlsSha256'), 'fixture guard hash does not join review')
req(idoc.get('expectedCount')==1 and g.get('count')==1, 'fixture is not Count1')
req(g.get('status')=='passed-source-only' and g.get('baseline',{}).get('accepted') is True, 'guard baseline not admitted')
req(len(g.get('faultControls',[]))==12, 'guard fault control cardinality mismatch')
req(rv.get('nativeLaunches')==0 and g.get('nativeWindowActions')==0, 'fixture records native action')
req(sr.get('rootNonce')==idoc.get('runID') and sr.get('exitCode')==0, 'schema receipt nonce/exit mismatch')
req(sr.get('candidateTupleRef',{}).get('sha256')=='sha256:'+sha(tuple_file), 'schema tuple hash mismatch')
req(sr.get('candidateTupleRef',{}).get('bytes')==tuple_file.stat().st_size, 'schema tuple bytes mismatch')
print(json.dumps({'kind':'factory-count1-r2-source-admission','status':'passed-source-only','issuedMetadataSha256':issued_hash,'guardControlsSha256':guard_hash,'schemaReceiptSha256':sha(schema),'nativeWindowActions':0,'lockActions':0}, sort_keys=True))
