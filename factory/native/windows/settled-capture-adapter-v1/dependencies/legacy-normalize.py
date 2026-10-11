"""Normalize raw native Windows observations; preserve unavailable-channel holds."""
from __future__ import annotations
import argparse
from decimal import Decimal
import json
from pathlib import Path
import re
import shutil
import struct
from factory.core.artifacts import file_hash, provenance, validate_artifact, write_artifact

def number(value):
    decimal = Decimal(str(value))
    if not decimal.is_finite(): raise ValueError('nonfinite native coordinate')
    if decimal == decimal.to_integral_value(): return int(decimal)
    return {'$decimal': format(decimal.normalize(), 'f')}

def rect(bounds):
    if len(bounds) != 4: raise ValueError('UIA rect must have four coordinates')
    return dict(zip(('x', 'y', 'width', 'height'), map(number, bounds)))

def normalize(package: Path, tuple_path: Path, output: Path) -> list[Path]:
    package = package.resolve()
    output = output.resolve()
    if not output.is_relative_to(Path(__file__).resolve().parent):
        raise ValueError('normalized output must live under Windows factory lane')
    if not package.is_relative_to(Path(__file__).resolve().parent):
        raise ValueError('native package must live under Windows factory lane')
    observation_path = package / 'native-observation.json'
    plan = json.loads((package / 'plan.json').read_text())
    witness = package / 'Sources/FactoryProbe/Witness.swift'
    if file_hash(witness) != plan['sourceHash']: raise ValueError('archived witness source drift')
    observations = json.loads(observation_path.read_text(encoding='utf-8-sig'))
    tuple_value = json.loads(tuple_path.read_text())
    if not isinstance(observations, list) or len(observations) != 20:
        raise ValueError('expected 20 complete independent native observations')
    if sorted(row.get('index', 0) for row in observations) != list(range(1, 21)):
        raise ValueError('native replay indices must be unique 1 through 20')
    additive_copies = {}
    if plan.get('closureBinding'):
        from .additive_archive import validate as validate_additive
        additive_copies = validate_additive(package,plan,observations,tuple_path)
    prepared = []
    for row in observations:
        if row['case'] != plan['case'] or row['sourceHash'] != plan['sourceHash']:
            raise ValueError('native receipt differs from source-bound case plan')
        archived_exe = package / 'evidence/FactoryProbe.exe'
        if archived_exe.exists() and file_hash(archived_exe) != 'sha256:' + row['exeSha256']:
            raise ValueError('archived native executable drift')
        run = row['index']
        run_dir = package / f'native-{run:02d}'
        copies = {}
        for binding in row['files']:
            relative = Path(binding['path'].replace('\\', '/'))
            if relative.is_absolute() or '..' in relative.parts or ':' in relative.as_posix():
                raise ValueError('raw file escapes replay archive')
            if relative in additive_copies or relative.as_posix() in ('capture.json', 'Witness.swift', 'plan.json', 'native-observation.json', 'tuple.json', 'FactoryProbe.exe'):
                raise ValueError('raw file collides with archive metadata')
            path = (run_dir / relative).resolve()
            if not path.is_relative_to(run_dir.resolve()): raise ValueError('raw file escapes replay')
            if file_hash(path) != 'sha256:' + binding['sha256']:
                raise ValueError('raw native file hash mismatch')
            if relative in copies: raise ValueError('duplicate raw native file binding')
            copies[relative] = path
        if not {Path('native.uia.json'), Path('native.screen.png'), Path('host.stdout.txt')}.issubset(copies):
            raise ValueError('missing required raw native file binding')
        if tuple_value['rendererHash'] != 'sha256:' + row['rendererSha256']:
            raise ValueError('native renderer differs from declared observational tuple')
        uia_path = run_dir / 'native.uia.json'
        uia = json.loads(uia_path.read_text(encoding='utf-8-sig'))
        if additive_copies:
            from .additive_archive import synthetic
            if synthetic(uia): raise ValueError('nested synthetic additive UIA receipt rejected')
        ax = []
        def walk(node, location='root'):
            identity = node.get('automationId') or location
            children = node.get('children', [])
            if isinstance(children, dict): children = [children]
            child_ids = [child.get('automationId') or f'{location}/{i}' for i, child in enumerate(children)]
            actions = []
            patterns = node.get('patterns', []) or []
            if isinstance(patterns, str): patterns = [patterns]
            for pattern, action in [('InvokePatternIdentifiers.Pattern', 'invoke'), ('TogglePatternIdentifiers.Pattern', 'toggle')]:
                if pattern in patterns: actions.append(action)
            ax.append({'identity': identity, 'role': node['controlType'].removeprefix('ControlType.'),
                       'label': node.get('name', ''), 'value': {'isEnabled': node['enabled'], 'isOffscreen': node['offscreen']},
                       'actions': actions, 'bounds': rect(node['bounds']), 'source': 'external', 'children': child_ids})
            for i, child in enumerate(children): walk(child, f'{location}/{i}')
        walk(uia)
        image_path = run_dir / 'native.screen.png'
        payload = image_path.read_bytes()
        if payload[:8] != b'\x89PNG\r\n\x1a\n': raise ValueError('native image is not PNG')
        width, height = struct.unpack('>II', payload[16:24])
        host_output = (run_dir / 'host.stdout.txt').read_text(encoding='utf-8-sig')
        scale_match = re.search(r'FACTORY_RENDERER_READY scale=([0-9.]+)', host_output)
        if scale_match is None: raise ValueError('missing measured native host scale')
        conditions = {'evidenceClass': 'observational-native', 'environmentInputs': plan.get('environmentInputs', {}), 'hostValid': row['hostValid'],
                      'nativeParity': row['nativeParity'], 'occlusionQualified': row['occlusionQualified'],
                      'providerPaintAvailable': False, 'layoutAvailable': False, 'animationClockCorrelated': False,
                      'actualHostExecutableHash': 'sha256:' + row['exeSha256'],
                      'actualSourceHash': row['sourceHash'], 'actualRendererHash': 'sha256:' + row['rendererSha256'],
                      'tupleWindowsHostHash': tuple_value['hostHashes']['windows'],
                      'rawReceiptHash': file_hash(observation_path), 'rawUIAHash': file_hash(uia_path),
                      'rawPlanHash': file_hash(package / 'plan.json'), 'rawWitnessHash': file_hash(witness)}
        if additive_copies:
            conditions.update(runtimeSourceCommit=plan['runtimeSourceCommit'], runtimeSourceTreeHash=plan['runtimeSourceTreeHash'], closureReceiptHash=plan['closureBinding']['receiptHash'], closedAt=plan['closureBinding']['closedAt'])
        if plan.get('synthetic') or row.get('synthetic') or uia.get('synthetic'):
            conditions['synthetic'] = True
        capture = {'kind': 'capture', 'version': '0.1', 'id': row['case']['id'] + f'.windows.r{run:02d}',
                   'provenance': provenance(row['sourceHash'], producer='factory.native.windows/observational'),
                   'case': row['case'], 'platform': 'windows', 'tuple': tuple_value,
                   'meta': {'run': run, 'host': {'id': 'windows.generated-renderer-host', 'hash': 'sha256:' + row['exeSha256']},
                            'conditions': conditions, 'clock': {'clockId': 'windows.native.receipt-clock', 'correlationHash': file_hash(observation_path)}},
                   'layout': [], 'ax': ax, 'events': [], 'anim': [],
                   'images': [{'id': f'windows.native-screen.r{run:02d}', 'hash': file_hash(image_path), 'widthPx': width,
                               'heightPx': height, 'captureScale': number(scale_match.group(1))}], 'text': []}
        validate_artifact(capture)
        archive = output / f'run-{run:03d}'
        if archive.exists(): raise ValueError('normalized replay archive exists')
        copies.update({Path('Witness.swift'): witness, Path('plan.json'): package / 'plan.json',
                       Path('native-observation.json'): observation_path, Path('tuple.json'): tuple_path})
        copies.update(additive_copies)
        if archived_exe.exists(): copies[Path('FactoryProbe.exe')] = archived_exe
        prepared.append((archive, capture, copies))
    outputs = []
    for archive, capture, copies in prepared:
        archive.mkdir(parents=True, exist_ok=False)
        for relative, source in copies.items():
            destination = archive / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, destination)
        target = archive / 'capture.json'
        write_artifact(target, capture)
        outputs.append(target)
    return outputs

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('--tuple', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(argv)
    for path in normalize(args.package, args.tuple, args.output): print(path)
    return 0
if __name__ == '__main__': raise SystemExit(main())
