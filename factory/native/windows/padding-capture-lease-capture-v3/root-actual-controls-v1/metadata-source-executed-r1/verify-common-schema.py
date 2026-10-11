"""Offline local common.schema tuple validation; never invokes host actions."""
from __future__ import annotations
import argparse, json, warnings
warnings.filterwarnings("ignore", category=DeprecationWarning)
from pathlib import Path
from jsonschema import Draft202012Validator, RefResolver
ap=argparse.ArgumentParser(); ap.add_argument('--tuple', required=True); ap.add_argument('--schema', required=True); args=ap.parse_args()
schema=json.loads(Path(args.schema).read_text()); doc=json.loads(Path(args.tuple).read_text())
wrapper={'$schema':schema.get('$schema'),'type':'object','required':['tuple'],'properties':{'tuple':{'$ref':schema['$id']+'#/$defs/tuple'}}}
resolver=RefResolver(schema['$id'],schema)
Draft202012Validator(wrapper,resolver=resolver).validate(doc)
t=doc['tuple']; assert t.get('id')=='sr1-source-bound-r11-20261011'; assert t.get('frozenTupleBound') is False or doc.get('frozenTupleBound') is False
for key in ('sdk','macosBuild','runtimeCommit','rendererHash','factoryVersion','acceptanceConfigHash'): assert isinstance(t.get(key),str) and t[key]
assert isinstance(t.get('toolchains'),dict) and t['toolchains']; assert isinstance(t.get('hostHashes'),dict) and t['hostHashes']
print(json.dumps({'status':'PASS_LOCAL_COMMON_SCHEMA','tupleID':t['id'],'frozenTupleBound':doc.get('frozenTupleBound'),'nativeWindowActions':0},sort_keys=True))
