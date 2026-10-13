#!/usr/bin/env python3
"""Run F10 reader admission plus production semantic comparison.

This packet accepts no discovery, fallback, parity, golden, or promotion claim.
Windows joins are supplied only by root after Count20 capture & archive transport.
"""
from __future__ import annotations
import argparse, hashlib, importlib.util, json
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
READER = HERE.parent / 'f10-trusted-reader-v1' / 'trusted-reader-report.py'
CASE = ROOT / 'factory/oracle/mac/seed-origin-v5/inputs/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.json'

def digest(raw: bytes) -> str:
    return 'sha256:' + hashlib.sha256(raw).hexdigest()

def sha(path: Path) -> str:
    return digest(path.read_bytes())

def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValueError(f'source unavailable: {path}')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def parse(path: Path):
    return json.loads(path.read_bytes().decode('utf-8-sig'))

def static_inputs():
    manifest_path = HERE / 'input-manifest-r3.pending.json'
    refs_path = HERE / 'mac-rebased-refs-r3.json'
    manifest = parse(manifest_path)
    refs = parse(refs_path)
    if manifest.get('macPathMap') != parse(HERE / 'mac-path-map-r3.json'):
        raise ValueError('explicit Mac path map changed')
    if len(refs.get('macCaptures', [])) != 20:
        raise ValueError('explicit Mac capture refs missing')
    for row in refs['macCaptures']:
        path = (HERE / row['path']).resolve(strict=True)
        if sha(path) != row['sha256'] or path.stat().st_size != row['bytes']:
            raise ValueError(f'Mac capture byte join changed: run {row.get("run")}')
    return manifest_path, refs, manifest

def missing_windows(manifest: dict) -> list[str]:
    missing = []
    if not manifest.get('windowsArchives'):
        missing.append('windowsArchives:20 exact capture-hash->archive-directory rows from root Count20 adapter')
    capture_path = (HERE / manifest.get('windowsCaptures', '')).resolve()
    if not capture_path.is_file():
        missing.append(f'windowsCaptures:typed normalized-observational JSON at {manifest.get("windowsCaptures")}')
    else:
        value = parse(capture_path)
        captures = value.get('captures') if isinstance(value, dict) else value
        if not isinstance(captures, list) or len(captures) != 20:
            missing.append('windowsCaptures:exact 20 typed captures with prefixed IDs')
        elif any(not isinstance(c, dict) or not isinstance(c.get('meta', {}).get('conditions', {}).get('windowsExitProof'), dict) for c in captures):
            missing.append('windowsExitProof:20 production proof objects with all 19 raw role bindings')
    return missing

def mac_captures(refs):
    captures = []
    for row in refs['macCaptures']:
        path = (HERE / row['path']).resolve(strict=True)
        value = parse(path)
        if digest(path.read_bytes()) != row['sha256'] or path.stat().st_size != row['bytes']:
            raise ValueError(f'Mac capture changed: run {row["run"]}')
        captures.append(value)
    if [c.get('meta', {}).get('run') for c in captures] != list(range(1, 21)):
        raise ValueError('Mac captures must be fixed runs 1..20')
    return captures

def build(input_path: Path, output: Path) -> dict:
    manifest_path, refs, manifest = static_inputs()
    missing = missing_windows(manifest)
    if missing:
        return {'schema':'paired-padding-f10-comparison-diagnostic-v1','status':'blocked','candidateOnly':True,
                'comparison':{'status':'blocked','semantic':'blocked','nativeParity':'held','pixelParity':'held','goldens':0,'promotion':'held'},
                'inputs':{'manifest':{'path':str(manifest_path),'sha256':sha(manifest_path)},'macReport':str((HERE/manifest['macReport']).resolve())},
                'missingWindowsJoins':missing,
                'effects':{'nativeWindowActions':0,'compilerActions':0,'remoteActions':0,'lockActions':0,'sourceMutations':0}}
    reader_mod = load_module(READER, 'f10_trusted_reader_r3')
    from factory.comparison.comparator import compare_case
    value, mac_report_path, windows_path, reader = reader_mod.load_inputs(input_path)
    mac_report = reader_mod.parse_json(mac_report_path, 'Mac report')
    mac = reader_mod.mac_proof(mac_report, mac_report_path)
    rows = reader_mod.windows_rows(reader_mod.parse_json(windows_path, 'typed Windows captures'), value, reader)
    case = parse(CASE)
    mac_runs = mac_captures(refs)
    windows_value = reader_mod.parse_json(windows_path, 'typed Windows captures')
    windows_runs = windows_value.get('captures') if isinstance(windows_value, dict) else windows_value
    comparison = compare_case(case, mac_runs + windows_runs, acceptance_config={}, holds=['F10 parity/golden/freeze held'])
    report = {'schema':'paired-padding-f10-comparison-diagnostic-v1','status':'paired-comparison-diagnostic-complete','candidateOnly':True,
              'inputs':{'manifest':{'path':str(input_path.resolve()),'sha256':sha(input_path)},'macReport':mac,
              'windowsCaptures':{'path':str(windows_path),'sha256':sha(windows_path)},'case':{'path':str(CASE),'sha256':sha(CASE)}},
              'reader':{'macRuns':20,'windowsReaderVerified':len(rows),'windowsRows':rows},'comparison':comparison,
              'parity':{'status':'held','goldens':0,'promotion':'held'},
              'effects':{'nativeWindowActions':0,'compilerActions':0,'remoteActions':0,'lockActions':0,'sourceMutations':0}}
    if output.exists():
        raise ValueError('output must be fresh')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report,indent=2,sort_keys=True)+'\n',encoding='utf-8')
    return report

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, default=HERE/'input-manifest-r3.pending.json')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        report = build(args.input.resolve(), args.output.resolve())
    except Exception as exc:
        print(json.dumps({'status':'blocked','error':str(exc)},sort_keys=True))
        return 2
    print(json.dumps({'status':report['status'],'semantic':report['comparison']['semantic'],'nativeParity':report['comparison'].get('nativeParity','held'),'missingWindowsJoins':report.get('missingWindowsJoins',[])},sort_keys=True))
    return 0 if report['status']=='paired-comparison-diagnostic-complete' else 2

if __name__ == '__main__':
    raise SystemExit(main())
