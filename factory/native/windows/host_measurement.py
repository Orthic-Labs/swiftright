"""Postclosure fixed qualification-host receipt, independent final tuple/case hashes."""
from datetime import datetime, timezone
from pathlib import Path
import argparse, json
from factory.core.artifacts import file_hash, write_artifact
from .closure_guard import validate

def measure(package: Path, binary: Path, closure_path: Path, output: Path) -> dict:
    root=Path(__file__).resolve().parent;package=package.resolve();output=output.resolve();binary=binary.resolve()
    if not package.is_relative_to(root) or not output.is_relative_to(root) or output.exists():raise ValueError('fresh owned measurement output required')
    plan=json.loads((package/'plan.json').read_text());observation=json.loads((package/'observation.json').read_text(encoding='utf-8-sig'));closure=validate(package/'sr0-status-closed.md',closure_path)
    if plan.get('synthetic') or observation.get('synthetic') or closure.get('synthetic'):raise ValueError('synthetic measurement cannot qualify host')
    if closure.get('decision')!='CLOSED' or closure.get('tuple')!='10':raise ValueError('tuple10 closure receipt required')
    if not plan.get('closureBinding') or plan['closureBinding']['statusHash']!=closure['statusHash'] or plan['closureBinding'].get('receiptHash')!=file_hash(closure_path) or plan['closureBinding'].get('closedAt')!=closure['closedAt']:raise ValueError('host lacks exact closure status binding')
    if observation.get('exitCode')!=0 or file_hash(binary)!='sha256:'+observation['exeSha256']:raise ValueError('actual compiled binary binding required')
    closed=datetime.fromisoformat(closure['closedAt'].replace('Z','+00:00'))
    compiled=datetime.fromisoformat(observation['observedAt'].replace('Z','+00:00'))
    if compiled<=closed:raise ValueError('qualification host must compile after closure')
    source=package/'Sources/FactoryProbe/main.swift'
    for binding in plan['sourceBindings']:
        path=package/binding['path']
        if not path.resolve().is_relative_to(package) or file_hash(path)!=binding['sha256']:raise ValueError('actual compiled source drift')
    def ref(path):return {'path':str(path.resolve()),'hash':file_hash(path)}
    result={'kind':'windows-factory-host-measurement','platform':'windows','tupleIndependent':True,
      'measuredAt':datetime.now(timezone.utc).isoformat().replace('+00:00','Z'),'runtimeCommit':plan['runtimeSourceCommit'],
      'closure':{**closure,'receiptHash':file_hash(closure_path)},'source':ref(source),'binary':ref(binary),
      'adapterSource':ref(root/'RendererHostAdditive.swift.in'),'plan':ref(package/'plan.json'),
      'compileObservation':ref(package/'observation.json'),'runtimeSourceReceipt':ref(package/'runtime-source-receipt.json'),
      'nativeReplayCount':0,'nativeWindowOpened':False,'nativeParity':'hold'}
    write_artifact(output,result);return result
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('package',type=Path);p.add_argument('--binary',type=Path,required=True);p.add_argument('--closure',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();measure(a.package,a.binary,a.closure,a.output)
