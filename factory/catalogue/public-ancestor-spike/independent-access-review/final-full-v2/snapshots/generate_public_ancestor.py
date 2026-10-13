"""Capture real tool streams & independently reconstruct bounded source proof."""
from pathlib import Path
import json,gzip
from exact_public_ancestor import Validator,HERE,ROOT,LEXICAL_HASH,HELPER_HASH,STRICT_HASH,digest,frozen_dependency_descriptors

def generate():
    validator=Validator()
    resolution=validator.validate()
    archive=HERE/'inputs-final-v2';archive.mkdir(exist_ok=True)
    descriptors={}
    for key,value in validator.inputs.items():
        if key in validator.paths:path=Path(validator.paths[key])
        else:
            path=archive/(key.replace(':','-')+'.txt');path.write_text(value)
        fallback=archive/(key.replace(':','-')+'.txt');fallback.write_bytes(value.encode());repository_path=str(fallback.relative_to(ROOT))
        descriptors[key]={'path':str(path),'repositoryPath':repository_path,'sha256':validator.pins[key]}
    production_sources={name:{'path':str(HERE/file),'sha256':digest((HERE/file).read_bytes())} for name,file in {'guard':'exact_public_ancestor.py','compilerChildren':'compiler_children.py','externalScopes':'external_scopes.py','generator':'generate_public_ancestor.py'}.items()}
    evidence={'kind':'bounded-source-public-ancestor-proof','version':2,'status':resolution['status'],'dependencies':{'lexicalParser':{'path':str(HERE/'lexical_model_v2.py'),'sha256':LEXICAL_HASH},'rawParserSha256':HELPER_HASH,'strictRequestParserSha256':STRICT_HASH,'productionSources':production_sources,'pinnedDependencies':frozen_dependency_descriptors()},'inputs':descriptors,'tools':validator.tool_pins,'resolution':resolution}
    decoded=(json.dumps(evidence,sort_keys=True,separators=(',',':'))+'\n').encode()
    path=HERE/'public-ancestor-evidence-v2.json.gz';path.write_bytes(gzip.compress(decoded,compresslevel=9,mtime=0))
    artifact_descriptor={'kind':'lossless-public-ancestor-proof-artifact','path':str(path.relative_to(ROOT)),'encoding':'gzip-level-9-mtime-0','sha256':digest(path.read_bytes()),'bytes':path.stat().st_size,'rawJsonSha256':digest(decoded),'rawJsonBytes':len(decoded)}
    (HERE/'public-ancestor-artifact-v2.json').write_text(json.dumps(artifact_descriptor,sort_keys=True,separators=(',',':'))+'\n')
    print(json.dumps({'path':str(path),'sha256':digest(path.read_bytes()),'rawJsonSha256':digest(decoded),'rawJsonBytes':len(decoded),'starts':resolution['fullSourceDeclarationStarts'],'byStatus':resolution['byStatus'],'heldReasons':resolution['heldReasons'],'compilerRecordCategories':resolution['compilerRecordCategories']}))
if __name__=='__main__':generate()
