"""Bind actual additive runtime source bytes before copying into new Dell root."""
from pathlib import Path
import argparse, re, subprocess
from factory.core.artifacts import canonical_hash, file_hash, write_artifact

def receipt(source: Path, remote: str, commit: str, *, synthetic: bool = False) -> dict:
    if not re.fullmatch('[a-f0-9]{40}',commit):raise ValueError('full frozen source commit required')
    if not synthetic:
        head=subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()
        if head!=commit:raise ValueError('runtime checkout HEAD differs from source commit')
        if subprocess.run(['git','-C',str(source),'diff','--quiet',commit,'--','.'],check=False).returncode:
            raise ValueError('runtime has uncommitted source edits')
        if subprocess.check_output(['git','-C',str(source),'ls-files','--others','--exclude-standard','--','Package.swift','Sources'],text=True).strip():
            raise ValueError('runtime contains uncommitted source files')
    files=sorted([source/'Package.swift',*(source/'Sources').rglob('*')])
    bindings=[{'path':str(p.relative_to(source)),'sha256':file_hash(p)} for p in files if p.is_file()]
    return {'kind':'factory-additive-runtime-source','sourceCommit':commit,'runtimePackagePath':remote,'sourceTreeHash':canonical_hash(bindings),'sourceBindings':bindings,'synthetic':synthetic}
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('source',type=Path);p.add_argument('--remote-runtime',required=True);p.add_argument('--commit',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();write_artifact(a.output,receipt(a.source,a.remote_runtime,a.commit))
