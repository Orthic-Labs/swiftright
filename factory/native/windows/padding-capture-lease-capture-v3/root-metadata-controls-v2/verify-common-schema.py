"""Offline local common.schema tuple validation; never invokes host actions."""
from __future__ import annotations
import argparse, json, warnings, hashlib, re
warnings.filterwarnings("ignore", category=DeprecationWarning)
from pathlib import Path
from jsonschema import Draft202012Validator, RefResolver
ap=argparse.ArgumentParser(); ap.add_argument('--tuple', required=True); ap.add_argument('--schema', required=True); ap.add_argument('--root-nonce', required=True); ap.add_argument('--source-hash', required=True); ap.add_argument('--source-binding-file', required=True); ap.add_argument('--source-archive-file', required=True); args=ap.parse_args()
if not re.fullmatch(r'[0-9a-fA-F]+', args.root_nonce or ''): raise SystemExit('root nonce must be non-empty hex')
if not re.fullmatch(r'sha256:[0-9a-f]{64}', args.source_hash or ''): raise SystemExit('source hash must be sha256 ref')
schema=json.loads(Path(args.schema).read_text()); doc=json.loads(Path(args.tuple).read_text())
wrapper={'$schema':schema.get('$schema'),'type':'object','required':['tuple'],'properties':{'tuple':{'$ref':schema['$id']+'#/$defs/tuple'}}}
resolver=RefResolver(schema['$id'],schema)
Draft202012Validator(wrapper,resolver=resolver).validate(doc)
t=doc['tuple']; assert t.get('id')=='sr1-source-bound-r11-20261011'; assert t.get('frozenTupleBound') is False or doc.get('frozenTupleBound') is False
for key in ('sdk','macosBuild','runtimeCommit','rendererHash','factoryVersion','acceptanceConfigHash'): assert isinstance(t.get(key),str) and t[key]
assert isinstance(t.get('toolchains'),dict) and t['toolchains']; assert isinstance(t.get('hostHashes'),dict) and t['hostHashes']
def ref(path):
 p=Path(path); raw=p.read_bytes(); return {'path':str(path),'sha256':'sha256:'+hashlib.sha256(raw).hexdigest(),'bytes':len(raw)}
source_ref=doc.get('sourceInputs',{}).get('sourceBinding'); assert isinstance(source_ref,dict) and source_ref.get('path') and source_ref.get('sha256') and isinstance(source_ref.get('bytes'),int)
source_actual=ref(args.source_binding_file); assert source_actual['sha256']==source_ref['sha256'] and source_actual['bytes']==source_ref['bytes']
print(json.dumps({'kind':'factory-mac-common-schema-validation-receipt-v1','version':'0.1','status':'PASS_LOCAL_COMMON_SCHEMA','exitCode':0,'rootNonce':args.root_nonce,'sourceHash':args.source_hash,'tupleID':t['id'],'frozenTupleBound':doc.get('frozenTupleBound'),'candidateTupleRef':ref(args.tuple),'schemaRef':ref(args.schema),'toolRef':ref(__file__),'sourceRef':source_ref,'sourceArchiveRef':ref(args.source_archive_file),'nativeWindowActions':0,'compilerActions':0,'guiActions':0,'remoteActions':0,'lockActions':0},sort_keys=True))
