"""Capture real tool streams & independently reconstruct bounded source proof."""
from pathlib import Path
import json
from exact_public_ancestor import Validator,HERE,LEXICAL_HASH,HELPER_HASH,STRICT_HASH,digest

def generate():
    validator=Validator();resolution=validator.validate()
    archive=HERE/'inputs-v1';archive.mkdir(exist_ok=True)
    descriptors={}
    for key,value in validator.inputs.items():
        if key in validator.paths:path=Path(validator.paths[key])
        else:
            path=archive/(key.replace(':','-')+'.txt');path.write_text(value)
        descriptors[key]={'path':str(path),'sha256':validator.pins[key]}
    evidence={'kind':'bounded-source-public-ancestor-proof','version':1,'status':resolution['status'],'dependencies':{'lexicalParser':{'path':str(HERE/'lexical_model_v2.py'),'sha256':LEXICAL_HASH},'rawParserSha256':HELPER_HASH,'strictRequestParserSha256':STRICT_HASH},'inputs':descriptors,'tools':validator.tool_pins,'resolution':resolution}
    path=HERE/'public-ancestor-evidence-v1.json';path.write_text(json.dumps(evidence,sort_keys=True,separators=(',',':'))+'\n')
    print(json.dumps({'path':str(path),'sha256':digest(path.read_bytes()),'starts':resolution['fullSourceDeclarationStarts'],'byStatus':resolution['byStatus'],'heldReasons':resolution['heldReasons'],'compilerRecordCategories':resolution['compilerRecordCategories']}))
if __name__=='__main__':generate()
