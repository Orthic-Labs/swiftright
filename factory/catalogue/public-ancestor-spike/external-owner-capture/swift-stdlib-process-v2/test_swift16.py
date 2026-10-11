#!/usr/bin/env python3
"""Accepted-baseline changed-byte production faults; no compiler rerun."""
import copy, json, re
from exact_swift16 import *
def record_span(raw,line,column):
    lines=raw.splitlines(keepends=True);stack=[];matches=[]
    for i,text in enumerate(lines):
        text=text.rstrip('\n')
        if m:=re.fullmatch(r'(\s*)\{',text):stack.append({'start':i,'indent':len(m[1]),'fields':{}});continue
        if m:=re.fullmatch(r'(\s*)\},?',text):
            frame=stack.pop()
            if frame['fields'].get('line')==line and frame['fields'].get('column')==column:matches.append((frame['start'],i+1,frame['indent']))
            continue
        m=re.fullmatch(r'(\s*)key\.(line|column): (\d+),?',text)
        if m and stack and len(m[1])==stack[-1]['indent']+2:stack[-1]['fields'][m[2]]=int(m[3])
    require(len(matches)==1,'fixture record cardinality');return lines,matches[0]
def change_record(raw,line,column,field,value,duplicate=False):
    lines,(begin,end,indent)=record_span(raw,line,column);block=lines[begin:end]
    prefix=' '*(indent+2)+'key.'+field+': '
    positions=[i for i,t in enumerate(block) if t.startswith(prefix)];require(len(positions)<=1,'fixture field duplicate')
    replacement=prefix+(json.dumps(value) if isinstance(value,str) else str(value))+',\n'
    if positions:block[positions[0]]=replacement
    else:block.insert(1,replacement)
    return ''.join(lines[:begin]+(lines[begin:end]+block if duplicate else block)+lines[end:])
def change_tree(raw,usr,old,new):
    pattern=r'(Demangling for '+re.escape('$s'+usr[2:])+r'\n)(.*?)(?=Demangling for \$s|\Z)';match=re.search(pattern,raw,re.S);require(match is not None,'fixture tree exists');require(old in match[2],'fixture tree node exists');section=match[2].replace(old,new,1);return raw[:match.start(2)]+section+raw[match.end(2):]
def bind_mutated_stream(candidate,key):
    if key not in {'indexStdout','trees'}:return
    p=json.loads(candidate['processes']);name='index' if key=='indexStdout' else 'demangle';p[name]['stdout']['sha256']=digest(candidate[key]);p[name]['stdout']['bytes']=len(candidate[key]);candidate['processes']=json.dumps(p).encode()
def controls(guard):
    baseline=guard.validate();require(len(baseline)==16,'accepted control baseline');out=[]
    def fault(label,key,value,reason=None):
        require(guard.validate()==baseline,'pre-fault accepted baseline');candidate=dict(guard.inputs);value=value.encode() if isinstance(value,str) else value;require(candidate[key]!=value,'fault changes actual bytes');candidate[key]=value;bind_mutated_stream(candidate,key)
        try:guard.validate(candidate)
        except ValueError as exc:
            message=str(exc);require(not message.startswith('final '),'semantic fault failed only final pin');require(reason is None or reason in message,'unexpected fault reason '+label+': '+message);out.append({'control':label,'acceptedBaseline':True,'changedInput':key,'changedBytes':True,'rejected':True,'reason':message});return
        raise AssertionError('fault accepted '+label)
    for row in baseline:
        name=row['name'];line=row['line'];col=row['column'];header=guard.inputs['headerIndex'].decode();ref=guard.inputs['indexStdout'].decode()
        for field,value in [('name','Wrong'+name),('kind','source.lang.swift.decl.class'),('usr','s:5Other'+str(len(name))+name+'V'),('effective_access','source.decl.effective_access.internal'),('line',line+1),('column',col+1),('is_implicit',1)]:fault(name+':physical-'+field,'headerIndex',change_record(header,line,col,field,value),'physical raw')
        for field,value in [('name','Wrong'+name),('kind','source.lang.swift.decl.class'),('is_implicit',1)]:fault(name+':physical-duplicate-'+field,'headerIndex',change_record(header,line,col,field,value,True),'physical raw cardinality')
        rl=row['referenceLine'];rc=row['referenceColumn']
        for field,value in [('name','Wrong'+name),('kind','source.lang.swift.ref.class'),('usr','s:5Other'+str(len(name))+name+'V'),('line',rl+1),('column',rc+1),('is_implicit',1)]:fault(name+':import-'+field,'indexStdout',change_record(ref,rl,rc,field,value),'import ')
        fault(name+':import-duplicate-wrong-name','indexStdout',change_record(ref,rl,rc,'name','Wrong'+name,True),'import reference cardinality')
        source=guard.inputs['source'].decode();lines=source.splitlines(keepends=True);original=lines[line-1]
        for label,text in [('access',original.replace('public ','internal ',1)),('attributes','@available(*, unavailable) '+original),('name',original.replace(name,'Wrong'+name,1))]:
            mutated=list(lines);mutated[line-1]=text;fault(name+':source-'+label,'source',''.join(mutated),'source ')
        mutated=list(lines);mutated[line-1]='#if false\n'+original+'#endif\n';fault(name+':source-branch','source',''.join(mutated),'source ')
        trees=guard.inputs['trees'].decode();usr=row['canonicalUsr']
        fault(name+':canonical-wrong-module','trees',change_tree(trees,usr,'text="Swift"','text="Other"').replace('\nSwift.'+name+'\n','\nOther.'+name+'\n',1),'tree exact namespace/name')
        fault(name+':canonical-wrong-kind','trees',change_tree(trees,usr,'kind='+{'enum':'Enum','struct':'Structure','protocol':'Protocol'}[row['kind']],'kind=Class'),'tree nominal kind')
        fault(name+':canonical-duplicate-module','trees',change_tree(trees,usr,'    kind=Module, text="Swift"','    kind=Module, text="Swift"\n    kind=Module, text="Swift"'),'nominal expanded tree/report shape')
        fault(name+':canonical-wrong-outer','trees',change_tree(trees,usr,'    kind=Module, text="Swift"','    kind=Structure\n      kind=Module, text="Swift"\n      kind=Identifier, text="Outer"'),'expanded node/result binding')
        fault(name+':source-wrong-module-tree','trees',change_tree(trees,row['sourceUsr'],'text="main"','text="Other"').replace('\nmain.'+name+'\n','\nOther.'+name+'\n',1),'tree exact namespace/name')
    req=guard.inputs['request'].decode();fault('import-extra-target','request',req.replace(' ]',' , "-target", "x86_64-apple-macosx27.0" ]'),'import request options');fault('import-wrong-request-kind','request',req.replace('source.request.indexsource','source.request.cursorinfo'),'request kind')
    req=guard.inputs['headerRequest'].decode();fault('header-wrong-module','headerRequest',req.replace('"Swift"','"Other"'),'header request options');fault('header-extra-target','headerRequest',req.replace(' ]',' , "-target", "x86_64-apple-macosx27.0" ]'),'header request options')
    for key in ['request','headerRequest']:
        req=guard.inputs[key].decode();fault(key+':duplicate-compilerargs',''+key,req.replace(' key.compilerargs:', ' key.compilerargs: [],\n key.compilerargs:',1),'request field closure/cardinality')
    fault('import-unknown-request-field','request',guard.inputs['request'].decode().replace(' key.compilerargs:', ' key.unknown: 1,\n key.compilerargs:',1),'request field closure/cardinality')
    for name in ['typecheck','index','demangle']:
        for field,value in [('argv',['wrong-tool']),('cwd','/tmp/wrong'),('returncode',1),('startedUnixNs',10**30)]:
            p=json.loads(guard.inputs['processes']);p[name][field]=value;fault(name+':process-'+field,'processes',json.dumps(p),'actual '+name)
        for stream in ['stdout','stderr']:
            p=json.loads(guard.inputs['processes']);p[name][stream]['path']='wrong/stream';fault(name+':process-'+stream+'-path','processes',json.dumps(p),'actual '+name+' '+stream+' binding')
        p=json.loads(guard.inputs['processes']);p[name]['returncode']=False;fault(name+':process-bool-exit','processes',json.dumps(p),'actual '+name+' execution')
    ref=guard.inputs['indexStdout'].decode();fault('import-extra-target-record','indexStdout',change_record(ref,4,29,'line',999,True),'exact import reference closure')
    lines,(begin,end,indent)=record_span(ref,3,41);fault('import-missing-auxiliary-generic-reference','indexStdout',''.join(lines[:begin]+lines[end:]),'exact import reference closure')
    lines,(begin,end,indent)=record_span(ref,1,8);fault('import-missing-module-reference','indexStdout',''.join(lines[:begin]+lines[end:]),'exact import reference closure')
    fault('import-extra-probe-target','probe',guard.inputs['probe']+b'let _extra: Any.Type = String.self\n','exact 16 ordinary import probe')
    trees=guard.inputs['trees'].decode();section=trees.split('Demangling for ',2)[1];fault('tree-duplicate-section','trees',trees+'Demangling for '+section,'duplicate tree section')
    return out
def main():
    guard=ExactSwift16();results=controls(guard);(HERE/'fault-controls.json').write_text(json.dumps(results,indent=2,sort_keys=True)+'\n');print('PASS 16 accepted witnesses & '+str(len(results))+' changed-byte semantic faults.')
if __name__=='__main__':main()
