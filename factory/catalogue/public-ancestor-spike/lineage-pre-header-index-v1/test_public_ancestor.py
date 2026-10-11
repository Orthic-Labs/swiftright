"""Replay complete artifact & changed actual raw/source acceptance faults."""
import json,re
from pathlib import Path
from types import MappingProxyType
from exact_public_ancestor import Validator,HERE,LINK_HASH,V12_HASH,DEMANGLE_HASH,helper,digest,require,load_artifact

def line_edit(raw,line,old,new):
    rows=raw.splitlines(keepends=True);require(old in rows[line-1],'fault source anchor missing');rows[line-1]=rows[line-1].replace(old,new,1);return ''.join(rows)

def duplicate_record(raw,line):
    at=raw.index('key.line: '+str(line)+',');start=raw.rfind('{',0,at);depth=0;quoted=False;escaped=False
    for end in range(start,len(raw)):
        c=raw[end]
        if quoted:
            if escaped:escaped=False
            elif c=='\\':escaped=True
            elif c=='"':quoted=False
        elif c=='"':quoted=True
        elif c=='{':depth+=1
        elif c=='}':
            depth-=1
            if depth==0:
                block=raw[start:end+1];return raw[:start]+block+',\n'+raw[start:]
    raise ValueError('fault raw record unterminated')

def test():
    path=HERE/'public-ancestor-evidence-v1.json';v,evidence=load_artifact(path,digest(path.read_bytes()));baseline=evidence['resolution']
    require(baseline['fullSourceDeclarationStarts']==17846 and baseline['unreconstructedV12Starts']==0,'actual universe denominator changed')
    faults=[]
    def add(name,key,changed):
        require(changed!=v.inputs[key] and digest(changed)!=v.pins[key],'fault unchanged '+name);faults.append((name,key,changed))
    core=v.inputs['SwiftUICore:source'];ui=v.inputs['SwiftUI:source']
    add('compound-binding-name','SwiftUICore:source',line_edit(core,13604,'m12','wrongName'))
    add('compound-binding-removal','SwiftUICore:source',line_edit(core,13604,', m12: CoreFoundation::CGFloat = 0.0',''))
    add('nominal-ancestor-access','SwiftUI:source',line_edit(ui,4067,'public struct','internal struct'))
    add('nominal-owner-name','SwiftUI:source',line_edit(ui,4067,'ToggleStyleConfiguration','WrongOwner'))
    add('declaration-read-access','SwiftUI:source',line_edit(ui,4080,'public var','internal var'))
    add('declaration-family','SwiftUICore:source',line_edit(core,13604,'var','let'))
    add('source-appended-bytes','SwiftUI:source',ui+'\n// changed actual source bytes\n')
    add('conditional-expression','SwiftUI:source',ui.replace('compiler(>=5.3)','compiler(>=99.0)',1))
    add('annotation-macOS-unavailable','SwiftUI:source',line_edit(ui,236,'unavailable','deprecated'))
    add('extension-owner-ambiguity','SwiftUICore:source',core+'\npublic struct ProjectionTransform {}\n')
    index=v.inputs['SwiftUICore:index'];entity=next(e for e in helper.entities(index) if e['line']==13604 and e['name']=='m11')
    for field,old,new in [('usr',entity['usr'],'s:WrongIdentity'),('name','m11','wrongName'),('kind',entity['kind'],'source.lang.swift.decl.enum'),('effective_access',entity['effective_access'],'source.decl.effective_access.internal')]:
        needle='key.'+field+': '+('"'+old+'"' if field in {'usr','name'} else old)
        require(needle in index,'raw field anchor missing');add('raw-'+field,'SwiftUICore:index',index.replace(needle,needle.replace(old,new),1))
    add('raw-cardinality','SwiftUICore:index',duplicate_record(index,13604))
    add('request-target','SwiftUI:request',v.inputs['SwiftUI:request'].replace('arm64-apple-macosx27.0','arm64-apple-macosx26.0'))
    add('request-extra-flag','SwiftUI:request',v.inputs['SwiftUI:request'].replace('"-module-name"','"-wrong-module-name"'))
    processes=json.loads(v.inputs['processResults']);processes['SwiftUI']['compile']['argv'][0]='/wrong/compiler';add('captured-process-argv','processResults',json.dumps(processes,sort_keys=True,separators=(',',':'))+'\n')
    tree=v.inputs['trees'];first=re.split(r'(?=Demangling for \$s)',tree)[1];add('duplicate-tree','trees',tree+first)
    add('tree-full-namespace','trees',tree.replace('text="SwiftUICore"','text="WrongModule"',1))
    receipts=[]
    for name,key,changed in faults:
        raw=dict(v.inputs);raw[key]=changed
        try:v.accept(baseline,raw)
        except (ValueError,KeyError) as error:receipts.append({'name':name,'rawInput':key,'baselineAccepted':True,'beforeSha256':v.pins[key],'afterSha256':digest(changed),'rejected':True,'reason':str(error)})
        else:raise AssertionError('accepted actual input fault '+name)
    result={'kind':'production-public-ancestor-raw-fault-replay','artifactSha256':digest(path.read_bytes()),'baselineWholeArtifactEqual':True,'faultCount':len(receipts),'faults':receipts}
    (HERE/'public-ancestor-faults-v1.json').write_text(json.dumps(result,sort_keys=True,separators=(',',':'))+'\n');print(json.dumps({'wholeArtifactEqual':True,'rejectedRawFaults':len(receipts)}))
if __name__=='__main__':test()
