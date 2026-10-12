#!/usr/bin/env python3
"""Create one canonical Rectangle source case from measured tuple bytes."""
from __future__ import annotations
import argparse, hashlib, json, re
from datetime import datetime, timezone
from pathlib import Path
from factory.tools.canonical_json import dump_bytes
from factory.core.artifacts import canonical_hash, write_artifact

ROOT = Path(__file__).resolve().parents[3]
PACKET = Path(__file__).resolve().parent
HASH = re.compile(r"sha256:[0-9a-f]{64}\Z")
MAX_JSON = 2 * 1024 * 1024
EXPECTED_RUNTIME = '37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'
EXPECTED_RENDERER = 'sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'

def bounded_json(path: Path):
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise ValueError(f"bounded regular JSON required: {path}")
    return json.loads(path.read_bytes())

def sha(path: Path) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise ValueError(f"bounded regular file required: {path}")
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024): h.update(chunk)
    return 'sha256:' + h.hexdigest()

def validate_tuple(tuple_value: dict) -> None:
    required = {'id','sdk','macosBuild','toolchains','runtimeCommit','rendererHash','hostHashes','factoryVersion','acceptanceConfigHash'}
    if set(tuple_value) != required: raise ValueError('tuple keys must match common schema')
    if not re.fullmatch(r'[0-9a-f]{7,64}', str(tuple_value['runtimeCommit'])) or tuple_value['runtimeCommit'] != EXPECTED_RUNTIME:
        raise ValueError('runtimeCommit is not measured current runtime')
    if tuple_value['rendererHash'] != EXPECTED_RENDERER: raise ValueError('rendererHash does not match pinned renderer')
    if not isinstance(tuple_value['hostHashes'], dict) or set(tuple_value['hostHashes']) != {'macos','windows'}:
        raise ValueError('both measured macos/windows host hashes are required')
    for value in tuple_value['hostHashes'].values():
        if not HASH.fullmatch(str(value)): raise ValueError('host hash is not measured sha256')
    for key in ('rendererHash','acceptanceConfigHash'):
        if not HASH.fullmatch(str(tuple_value[key])): raise ValueError(f'{key} is not measured sha256')
    for key in ('id','sdk','macosBuild','factoryVersion'):
        if not isinstance(tuple_value[key], str) or not tuple_value[key].strip(): raise ValueError(f'{key} is empty')
    if not isinstance(tuple_value['toolchains'], dict) or not tuple_value['toolchains']:
        raise ValueError('toolchains are required')

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--tuple', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    tuple_value = bounded_json(args.tuple)
    validate_tuple(tuple_value)
    recipe = bounded_json(PACKET / 'recipe.json')
    inputs = {'shape':'Rectangle()','style':'fill(Color.red)','color-scheme':'light'}
    witness_hash = sha(PACKET / 'witness.swift')
    recipe_hash = canonical_hash(recipe)
    if recipe_hash != 'sha256:52e97ee42c856ce0fb112d6ac616c66afcadac4177115870622e17673046cb57': raise ValueError('packet recipe changed')
    tuple_suffix = canonical_hash(tuple_value).split(':',1)[1][:16]
    case_id = f'swiftui.shapes.fill-stroke.recipe.pilot-next.rectangle-fill-light.{tuple_suffix}'
    descriptor = {'id':case_id,'inputs':inputs,'coverage':'declared'}
    case = {
      'kind':'case','version':'0.1','id':case_id,'block':'swiftui.shapes.fill-stroke',
      'inputs':inputs,'coverage':'declared','expectedCaseSetHash':canonical_hash([descriptor]),
      'provenance':{'sourceHash':recipe_hash,'createdAt':datetime.now(timezone.utc).isoformat().replace('+00:00','Z'),'producer':'factory/pipeline/pilot-next-source-v1'},
      'recipe':{'id':recipe['id'],'hash':recipe_hash},'tuple':tuple_value,
      'witness':{'path':'factory/pipeline/pilot-next-source-v1/witness.swift','sourceHash':witness_hash}
    }
    case_hash = canonical_hash(case)
    manifest = {
      'kind':'generated-probe','version':'0.1','block':'swiftui.shapes.fill-stroke',
      'compileExpectation':'success','executionEligible':True,'scenario':'baseline',
      'recipeFile':'factory/pipeline/pilot-next-source-v1/recipe.json',
      'recipe':{'id':recipe['id'],'hash':recipe_hash},'case':{'id':case_id,'hash':case_hash},
      'caseInputs':inputs,'environmentInputs':{'colorScheme':'light'},
      'sourceFile':'witness.swift','sourceRepositoryPath':'factory/pipeline/pilot-next-source-v1/witness.swift','sourceHash':witness_hash,
      'witness':{'id':'swiftui.shapes.rectangle-fill.pilot-next','sourceHash':witness_hash},
      'witnessType':'Witness_shapes_rectangle_fill','tupleId':tuple_value['id'],
      'channels':{
        'adapters':{'customLayout':'not-declared','native':'native host capture required','provider':'host-specific adapter required; no renderer ABI assumed','text':'not-declared'},
        'assertionChannels':['layout'],
        'geometry':[{'channel':'layout','hostHookRequired':True,'probeTag':'swiftui.shapes.rectangle-fill.pilot-next:swiftui.shapes.rectangle-fill.pilot-next.witness','viewInstrumentationInserted':False}],
        'native':[],'provider':[],
        'transparency':{'channels':['layout','paint'],'enabled':False,'viewIsolatedFromInstrumentation':True},
        'witnesses':[{'id':'swiftui.shapes.rectangle-fill.pilot-next','sourceHash':witness_hash}]
      },
      'candidate':'swiftui.shapes.rectangle-fill.pilot-next'
    }
    out = args.output.expanduser().resolve()
    if out.exists() and any(out.iterdir()): raise ValueError('output must be fresh and non-empty-free')
    write_artifact(out / 'manifest.json', manifest)
    (out / 'witness.swift').write_bytes((PACKET / 'witness.swift').read_bytes())
    write_artifact(out / 'cases' / (case_id.replace('/','--') + '.json'), case)
    write_artifact(out / 'tuple.json', tuple_value)
    print(json.dumps({'caseId':case_id,'caseHash':case_hash,'recipeHash':recipe_hash,'witnessHash':witness_hash},sort_keys=True))
    return 0
if __name__ == '__main__': raise SystemExit(main())
