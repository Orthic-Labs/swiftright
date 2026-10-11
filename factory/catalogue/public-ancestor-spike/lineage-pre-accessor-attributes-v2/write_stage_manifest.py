"""List exact repository bytes needed for frozen production replay."""
import hashlib,json,gzip
from pathlib import Path
from exact_public_ancestor import HERE,ROOT,CLANG_FOLDER,SWIFT16_FOLDER,DESTRUCTOR_FOLDER,GRAPH_ARCHIVE_FOLDER,frozen_dependency_descriptors,digest,require

def generate():
    files={}
    def add(path,role):
        path=Path(path);path=path if path.is_absolute() else ROOT/path
        require(path.is_relative_to(ROOT) and path.is_file() and not path.is_symlink(),'stage dependency path absent/escaped: '+str(path))
        key=str(path.relative_to(ROOT));raw=path.read_bytes()
        row=files.setdefault(key,{'path':key,'sha256':digest(raw),'bytes':len(raw),'roles':[]})
        require(row['sha256']==digest(raw),'stage dependency changed during inventory')
        if role not in row['roles']:row['roles'].append(role)
    artifact=HERE/'public-ancestor-evidence-v2.json.gz';decoded=gzip.decompress(artifact.read_bytes());e=json.loads(decoded)
    for name in ['exact_public_ancestor.py','compiler_children.py','external_scopes.py','lexical_model_v2.py','generate_public_ancestor.py','test_public_ancestor.py','replay_archive_v2.py','write_stage_manifest.py','public-ancestor-evidence-v2.json.gz','public-ancestor-artifact-v2.json','public-ancestor-faults-v2.json','public-ancestor-archive-replay-v2.json']:
        add(HERE/name,'owned final proof')
    for key,d in e['inputs'].items():add(d['repositoryPath'],'actual captured input:'+key)
    for key,d in frozen_dependency_descriptors().items():add(d['path'],'frozen production dependency:'+key)
    for d in e['dependencies']['productionSources'].values():add(d['path'],'production source')
    # These immutable mappings retain original semantic paths & lossless bytes.
    semantic={}
    for version in ['archive-inputs-v1','archive-inputs-v2']:
        mapping=HERE/version/'archive-input-mapping.json';add(mapping,'source/tool archive mapping')
        for entry in json.loads(mapping.read_text())['entries']:
            if entry.get('kind')=='directory':continue
            a=entry['archive'];add(a['path'],'lossless source/tool archive')
            semantic[entry['semanticPath']]=a['path']
            for alias in entry.get('aliases',[]):semantic[alias]=a['path']
    for folder in [CLANG_FOLDER,SWIFT16_FOLDER]:
        manifest=folder/'capture-inputs.json';add(manifest,'helper actual input closure')
        for d in json.loads(manifest.read_text()).values():
            original=Path(d['path']);original=original if original.is_absolute() else ROOT/original
            if original.is_relative_to(ROOT):add(original,'helper captured repository input')
            else:require(str(original) in semantic,'external helper input lacks archive mapping: '+str(original))
    manifest=DESTRUCTOR_FOLDER/'archive-manifest-v2.json';add(manifest,'destructor thirteen-member raw archive')
    for d in json.loads(manifest.read_text())['rows']:add(DESTRUCTOR_FOLDER/d['archivePath'],'destructor raw archive member')
    add(DESTRUCTOR_FOLDER/'archive-wrapper-v2/evaluate_reader.py','frozen destructor evaluator')
    manifest=GRAPH_ARCHIVE_FOLDER/'archive-manifest.json'
    for graph in json.loads(manifest.read_text())['files']:
        for chunk in graph['chunks']:add(GRAPH_ARCHIVE_FOLDER/chunk['archivePath'],'lossless actual symbolgraph chunk')
    add(ROOT/'factory/catalogue/compiler-cursor-spike/link-evidence.json','immutable836 lineage authority')
    add(ROOT/'factory/catalogue/evidence/interface-audit-v12-candidate.json','immutable v12 lineage')
    add(ROOT/'factory/catalogue/duplicate-identity-spike/exact-identity-candidate.json','bounded five projected pairs')
    rows=[files[k] for k in sorted(files)]
    for row in rows:row['roles'].sort()
    payload={'kind':'public-ancestor-final-input-stage-manifest','version':2,'artifactSha256':digest(artifact.read_bytes()),'rawJsonSha256':digest(decoded),'rawJsonBytes':len(decoded),'scope':e['resolution']['scope'],'status':e['resolution']['status'],'fileCount':len(rows),'totalBytes':sum(r['bytes'] for r in rows),'files':rows}
    output=HERE/'final-input-stage-manifest-v2.json';output.write_text(json.dumps(payload,sort_keys=True,separators=(',',':'))+'\n')
    print(json.dumps({'path':str(output),'sha256':digest(output.read_bytes()),'files':len(rows),'bytes':payload['totalBytes']}))
if __name__=='__main__':generate()
