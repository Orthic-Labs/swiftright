#!/usr/bin/env python3
"""Fresh genuine compiler, SourceKit & demangle executions; no existing receipts."""
import json, subprocess, sys, time
from pathlib import Path
from exact_swift16 import *
def descriptor(path):
    p=Path(path);b=p.read_bytes();return {'path':str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p),'sha256':digest(b),'bytes':len(b)}
def write(path,value):
    path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(value if isinstance(value,bytes) else value.encode())
def execute(name,argv,stdout_path,stderr_path,stdin=None):
    started=time.time_ns();result=subprocess.run(argv,cwd=SCRATCH,input=stdin,capture_output=True,check=False,timeout=600);ended=time.time_ns()
    write(stdout_path,result.stdout);write(stderr_path,result.stderr)
    receipt={'argv':argv,'cwd':str(SCRATCH),'startedUnixNs':started,'endedUnixNs':ended,'returncode':result.returncode,'stdinSha256':digest(stdin) if stdin is not None else None,'stdout':descriptor(stdout_path),'stderr':descriptor(stderr_path)}
    print(name+' actual returncode '+str(result.returncode),flush=True)
    return receipt
def main():
    if '--finalize' in sys.argv:
        finalize();return
    require(str(SCRATCH.resolve()).startswith('/Users/adrdsouza/Library/Caches/'),'internal scratch required');SCRATCH.mkdir(parents=True,exist_ok=True)
    for name,(p,h) in TOOLS.items():require(digest(p.read_bytes())==h,'actual pinned '+name+' bytes')
    source=expected_probe();probe=SCRATCH/'owners.swift';request=SCRATCH/'owners.yaml';write(probe,source)
    args=[str(probe),'-sdk',SDK,'-target',TARGET]
    request_text='{\n key.request: source.request.indexsource,\n key.sourcefile: '+json.dumps(str(probe))+',\n key.compilerargs: [ '+', '.join(json.dumps(a) for a in args)+' ]\n}\n';write(request,request_text)
    write(HERE/'probes/owners.swift',probe.read_bytes());write(HERE/'requests/owners.yaml',request.read_bytes());write(HERE/'requests/demangle.input.txt',expanded_input())
    processes={}
    processes['typecheck']=execute('typecheck',[str(TOOLS['compiler'][0]),'-typecheck','-sdk',SDK,'-target',TARGET,str(probe)],HERE/'receipts/typecheck.stdout',HERE/'receipts/typecheck.stderr')
    processes['index']=execute('index',[str(TOOLS['sourcekitLsp'][0]),'debug','run-sourcekitd-request','--request-file',str(request)],HERE/'raw/owners.index.txt',HERE/'receipts/index.stderr')
    processes['demangle']=execute('demangle',[str(TOOLS['demangler'][0]),'--expand'],HERE/'raw/trees.txt',HERE/'receipts/demangle.stderr',expanded_input().encode())
    write(HERE/'processes.json',json.dumps(processes,indent=2,sort_keys=True)+'\n')
    paths={'source':SOURCE,'headerIndex':HEADER/'raw/Swift.index.txt','headerRequest':HEADER/'requests/Swift.yaml','probe':HERE/'probes/owners.swift','request':HERE/'requests/owners.yaml','typecheckStdout':HERE/'receipts/typecheck.stdout','typecheckStderr':HERE/'receipts/typecheck.stderr','indexStdout':HERE/'raw/owners.index.txt','indexStderr':HERE/'receipts/index.stderr','demangleInput':HERE/'requests/demangle.input.txt','trees':HERE/'raw/trees.txt','demangleStderr':HERE/'receipts/demangle.stderr','processes':HERE/'processes.json'}
    write(HERE/'capture-inputs.json',json.dumps({k:descriptor(p) for k,p in paths.items()},indent=2,sort_keys=True)+'\n')
    if '--capture-only' in sys.argv:return
    finalize()
def finalize():
    processes=json.loads((HERE/'processes.json').read_text())
    guard=ExactSwift16();rows=guard.validate()
    evidence={'kind':'swift16-genuine-process-capture-v2','status':'exact-bounded-correspondences-only','sdk':SDK,'target':TARGET,'physicalSourceNamespace':'main','compiledImportNamespace':'Swift','namespaceMismatchPreserved':True,'witnesses':rows,'processes':processes,'rawInputs':{k:descriptor(p) for k,p in guard.paths.items()},'captureInputManifest':descriptor(HERE/'capture-inputs.json'),'tools':{k:descriptor(p) for k,(p,h) in TOOLS.items()},'sourceFiles':{'capture':descriptor(Path(__file__)),'guard':descriptor(HERE/'exact_swift16.py'),'test':descriptor(HERE/'test_swift16.py')},'immutable836':descriptor(ROOT/'factory/catalogue/compiler-cursor-spike/link-evidence.json'),'headerIndexLineage':descriptor(HEADER/'swift-foundation-index-evidence.json'),'frozenHelpers':{'lexical':descriptor(BASE/'lexical_model_v2.py'),'trees':descriptor(ROOT/'factory/catalogue/module-provenance-spike/exact_validator.py')},'scope':'Only sixteen exact physical public top-level Swift declarations joined to actual ordinary compiled-import references & full nominal trees. No generic main→Swift alias.'}
    controls=json.loads((HERE/'fault-controls.json').read_text());require(all(c['acceptedBaseline'] and c['changedBytes'] and c['rejected'] and not c['reason'].startswith('final ') for c in controls),'all raw controls semantic');evidence['faultControls']={'artifact':descriptor(HERE/'fault-controls.json'),'count':len(controls),'acceptedBaselines':len(controls),'changedByteControls':len(controls),'semanticRejections':len(controls)}
    write(HERE/'swift16-evidence.json',json.dumps(evidence,indent=2,sort_keys=True)+'\n');print('Accepted exact witnesses '+str(len(rows)),flush=True)
if __name__=='__main__':main()
