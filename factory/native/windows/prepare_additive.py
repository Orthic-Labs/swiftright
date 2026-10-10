"""Fresh factory host linked to owned additive runtime; immutable tuple10 DLL separate."""
from __future__ import annotations
import argparse, json, re
from pathlib import Path, PureWindowsPath
from factory.core.artifacts import file_hash, write_artifact, canonical_hash
from .adapter import prepare, DLL_HASH

STAGE10 = r'D:\Claude\sr0-r10'
STAGE10_COMMIT = '8e47b89b3e9ae488e77ea8b5a2e4663053601c0d'

def prepare_additive(manifest: Path, output: Path, receipt_path: Path) -> dict:
    receipt = json.loads(receipt_path.read_text())
    runtime = receipt['runtimePackagePath']
    if not re.fullmatch(r'D:\\Claude\\factory-swiftright-[A-Za-z0-9_-]+\\.+', runtime, re.I):
        raise ValueError('runtime must live within NEW owned factory-swiftright root')
    if '..' in PureWindowsPath(runtime).parts:
        raise ValueError('runtime path escapes owned root')
    commit = receipt['sourceCommit']
    if not re.fullmatch('[a-f0-9]{40}', commit) or commit == STAGE10_COMMIT:
        raise ValueError('additive runtime needs distinct full source commit')
    if not re.fullmatch('sha256:[a-f0-9]{64}', receipt['sourceTreeHash']):
        raise ValueError('runtime source tree binding required')
    bindings = receipt['sourceBindings']
    if not bindings or canonical_hash(bindings) != receipt['sourceTreeHash']:
        raise ValueError('runtime source bindings hash mismatch')
    for binding in bindings:
        path = PureWindowsPath(binding['path'])
        if path.is_absolute() or '..' in path.parts or ':' in binding['path']:
            raise ValueError('runtime source binding escapes owned package')
        if not re.fullmatch('sha256:[a-f0-9]{64}', binding['sha256']):
            raise ValueError('invalid runtime source binding hash')
    plan = prepare(manifest, output, renderer=True)
    output = output.resolve()
    package = output / 'Package.swift'
    text = package.read_text().replace(r'D:\\Claude\\sr0-r09\\src\\probes\\sr0-s\\fresh-runtime', json.dumps(runtime)[1:-1]).replace(r'D:\\Claude\\sr0-r09\\src\\packages\\SwiftRightBridge', r'D:\\Claude\\sr0-r10\\src\\packages\\SwiftRightBridge')
    text=text.replace('.package(path: '+json.dumps(runtime)+')', '.package(name: "fresh-runtime", path: '+json.dumps(runtime)+')')
    package.write_text(text)
    host = output / 'Sources/FactoryProbe/main.swift'
    template=Path(__file__).with_name('RendererHostAdditive.swift.in').read_text()
    witness=json.loads(manifest.read_text())
    host.write_text(template.replace('__WITNESS__',witness['witnessType']).replace('__COLORSCHEME__',witness.get('environmentInputs',{}).get('colorScheme','light')))
    (output / 'runtime-source-receipt.json').write_bytes(receipt_path.read_bytes())
    write_artifact(output / 'runtime-source-tree.json', bindings)
    plan.update(stage=STAGE10, stageSourceCommit=STAGE10_COMMIT, rendererSha256=DLL_HASH,
                runtimeSourceCommit=commit, runtimeSourceTreeHash=receipt['sourceTreeHash'],
                runtimeSourceReceiptHash=file_hash(receipt_path), runtimePackagePath=runtime,
                closureRequired=True, closureBinding=None, synthetic=bool(receipt.get('synthetic',False)),
                nativeHold='Explicit SR0 CLOSED status + current tuple inputs + owned lock required; UIA/pixels cannot establish provider export parity')
    plan['sourceBindings'] = [{'path':str(p.relative_to(output)), 'sha256':file_hash(p)} for p in sorted(output.rglob('*.swift'))]
    write_artifact(output / 'plan.json', plan)
    return plan

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('manifest',type=Path);p.add_argument('--output',type=Path,required=True);p.add_argument('--runtime-receipt',type=Path,required=True)
    a=p.parse_args();print(json.dumps(prepare_additive(a.manifest,a.output,a.runtime_receipt),sort_keys=True))
if __name__=='__main__':main()
