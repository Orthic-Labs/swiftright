"""Fresh diagnostic snapshots: runtime unchanged, one assertion message added."""
from pathlib import Path
import json, shutil, tarfile
from factory.core.artifacts import canonical_hash, file_hash, write_artifact

LANE=Path(__file__).resolve().parent
PROPOSAL=LANE.parents[2]/'factory/runtime-additions/task-id-investigation/trace-proposal/proposal.json'
PROPOSAL_HASH='sha256:25d12312a1b42d7a29b328b98a13aceff3b5b06e19cc7c4acf3dbe44d8c57030'

def prepare():
    output=LANE/'taskid-message-trace-20261011'
    if output.exists() or file_hash(PROPOSAL)!=PROPOSAL_HASH: raise ValueError('fresh output & exact proposal required')
    proposal=json.loads(PROPOSAL.read_text()); trace=Path(proposal['diagnosticSource']['path'])
    if file_hash(trace)!='sha256:'+proposal['diagnosticSource']['sha256']: raise ValueError('trace source drift')
    new=b'XCTAssertEqual(log.results, ["a"], "events: \\(log.events)")'; old=b'XCTAssertEqual(log.results, ["a"])'
    if trace.read_bytes().count(new)!=1: raise ValueError('one diagnostic message required')
    output.mkdir(); shutil.copyfile(PROPOSAL,output/'proposal.json'); rows=[]
    for variant in proposal['variants']:
        parent_receipt=Path(variant['originalSourceReceipt']); parent=json.loads(parent_receipt.read_text()); original=Path(variant['originalTaskIDSource'])
        if file_hash(parent_receipt)!='sha256:'+variant['originalSourceReceiptHash'] or trace.read_bytes().replace(new,old)!=original.read_bytes(): raise ValueError('original bytes not exactly recoverable')
        root=output/variant['label']; root.mkdir(); runtime=root/'runtime'; shutil.copytree(original.parents[2],runtime)
        for binding in parent['completeSnapshotBindings']:
            if file_hash(runtime/binding['path'])!=binding['sha256']: raise ValueError('parent snapshot drift')
        shutil.copyfile(parent_receipt,root/'parent-runtime-source-receipt.json'); shutil.copyfile(trace,runtime/'Tests/SwiftRightRuntimeTests/TaskIDTests.swift')
        bindings=[{'path':str(p.relative_to(runtime)),'sha256':file_hash(p)} for p in sorted(runtime.rglob('*')) if p.is_file()]
        changes=[x['path'] for x,y in zip(bindings,parent['completeSnapshotBindings']) if x!=y]
        if changes!=['Tests/SwiftRightRuntimeTests/TaskIDTests.swift']: raise ValueError('diagnostic delta exceeds one file')
        archive=root/'diagnostic-source.tar'
        with tarfile.open(archive,'w') as tar:
            for b in bindings: tar.add(runtime/b['path'],arcname=b['path'],recursive=False)
        receipt={**parent,'kind':'factory-diagnostic-runtime-source','runtimePackagePath':str(Path('D:/Claude/factory-swiftright-taskid-trace-20261011'))+'\\'+variant['label']+'\\runtime','completeSnapshotBindings':bindings,'completeSnapshotHash':canonical_hash(bindings),'snapshotArchiveHash':file_hash(archive),'snapshotMethod':'Exact parent git snapshot, copied factory-only assertion message delta; runtime source unchanged','parentSourceReceiptHash':file_hash(parent_receipt),'parentCompleteSnapshotHash':parent['completeSnapshotHash'],'diagnosticOnly':True,'diagnosticTaskSourceHash':file_hash(trace),'originalTaskSourceHash':file_hash(original),'proposalHash':PROPOSAL_HASH}
        receipt['runtimePackagePath']=receipt['runtimePackagePath'].replace('/','\\')
        write_artifact(root/'runtime-source-receipt.json',receipt); write_artifact(root/'runtime-source-tree.json',parent['sourceBindings'])
        rows.append({'label':variant['label'],'sourceCommit':parent['sourceCommit'],'runtimeSourceTreeHash':parent['sourceTreeHash'],'diagnosticSourceReceiptHash':file_hash(root/'runtime-source-receipt.json'),'parentSourceReceiptHash':file_hash(parent_receipt),'diagnosticCompleteSnapshotHash':receipt['completeSnapshotHash'],'onlyChangedPath':changes[0]})
    write_artifact(output/'source-plan.json',{'kind':'factory-taskid-message-trace-source-plan','proposalHash':PROPOSAL_HASH,'diagnosticOnly':True,'nativeCaseCaptureCount':0,'variants':rows})
    return output
if __name__=='__main__': print(prepare())
