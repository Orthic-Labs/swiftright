"""Export exact committed runtime bytes, excluding concurrent working-tree edits."""
import argparse, io, json, re, subprocess, tarfile
from pathlib import Path, PurePosixPath
from factory.core.artifacts import canonical_hash, file_hash, write_artifact

REL='probes/sr0-s/fresh-runtime'
def export(repo: Path, commit: str, output: Path, remote: str) -> dict:
    full=subprocess.check_output(['git','-C',str(repo),'rev-parse',commit+'^{commit}'],text=True).strip()
    if not re.fullmatch('[a-f0-9]{40}',full):raise ValueError('exact commit required')
    lane=Path(__file__).resolve().parent;output=output.resolve()
    if not output.is_relative_to(lane) or output==lane or output.exists():raise ValueError('fresh owned output required')
    payload=subprocess.check_output(['git','-C',str(repo),'archive','--format=tar',full,REL])
    output.mkdir(parents=True);archive=output/'runtime-source.tar';archive.write_bytes(payload)
    runtime=output/'runtime';runtime.mkdir()
    with tarfile.open(fileobj=io.BytesIO(payload),mode='r:') as tar:
        for entry in tar.getmembers():
            name=PurePosixPath(entry.name)
            if name.is_relative_to(REL) and entry.isfile():
                rel=name.relative_to(REL)
                if '..' in rel.parts:raise ValueError('archive source escape')
                target=runtime/str(rel);target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(tar.extractfile(entry).read())
    source_files=sorted([runtime/'Package.swift',*(runtime/'Sources').rglob('*')])
    bindings=[{'path':str(p.relative_to(runtime)),'sha256':file_hash(p)} for p in source_files if p.is_file()]
    all_bindings=[{'path':str(p.relative_to(runtime)),'sha256':file_hash(p)} for p in sorted(runtime.rglob('*')) if p.is_file()]
    receipt={'kind':'factory-additive-runtime-source','sourceCommit':full,'runtimePackagePath':remote,'sourceTreeHash':canonical_hash(bindings),'sourceBindings':bindings,'synthetic':False,'snapshotArchiveHash':file_hash(archive),'snapshotMethod':'git archive exact commit; no working-tree bytes','completeSnapshotBindings':all_bindings,'completeSnapshotHash':canonical_hash(all_bindings)}
    write_artifact(output/'runtime-source-receipt.json',receipt);write_artifact(output/'runtime-source-tree.json',bindings)
    return receipt
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--repo',type=Path,required=True);p.add_argument('--commit',required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--remote-runtime',required=True);a=p.parse_args();print(json.dumps(export(a.repo,a.commit,a.output,a.remote_runtime),sort_keys=True))
