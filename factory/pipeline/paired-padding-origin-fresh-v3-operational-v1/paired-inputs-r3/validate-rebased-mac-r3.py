#!/usr/bin/env python3
"""Validate F10 r3's explicit Mac archive map; no discovery or fallback."""
from __future__ import annotations
import argparse, hashlib, json, os
from pathlib import Path

HERE = Path(__file__).resolve().parent

def sha(path: Path) -> str:
    return 'sha256:' + hashlib.sha256(path.read_bytes()).hexdigest()

def fail(message: str) -> None:
    raise SystemExit('blocked: ' + message)

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--mac-only', action='store_true')
    args = parser.parse_args()
    manifest_path = HERE / 'input-manifest-r3.pending.json'
    refs_path = HERE / 'mac-rebased-refs-r3.json'
    map_path = HERE / 'mac-path-map-r3.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    refs = json.loads(refs_path.read_text(encoding='utf-8'))
    path_map = json.loads(map_path.read_text(encoding='utf-8'))
    if manifest.keys() != {'version','expectedWindows','macReport','windowsCaptures','macRoots','macPathMap','windowsArchives'}:
        fail('manifest shape changed')
    if manifest['macPathMap'] != path_map or refs['macPathMapCount'] != len(path_map):
        fail('map join changed')
    if refs['sourceConfig']['sha256'] != sha(Path('/Volumes/D/claude/swiftright/factory/oracle/mac/padding-origin-fresh-v1/actual/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258/origin-reader-config.json')):
        fail('source config changed')
    roots = [ (HERE / value).resolve(strict=True) for value in manifest['macRoots'] ]
    if len(roots) != 3 or len(set(roots)) != 3 or any(not p.is_dir() for p in roots):
        fail('explicit Mac roots unavailable')
    rows = {row['logicalPath']: row for row in refs['macPathMap']}
    if set(rows) != set(path_map):
        fail('rebased row keys changed')
    for logical, relative in sorted(path_map.items()):
        if not logical.startswith('/') or '..' in Path(logical).parts:
            fail(f'unsafe logical path: {logical}')
        if not isinstance(relative, str) or relative.startswith('/') or ':' in relative or '\\' in relative or '\x00' in relative:
            fail(f'unsafe physical path: {logical}')
        physical = (HERE / relative).resolve(strict=True)
        if not physical.is_file() or not any(os.path.commonpath([physical, root]) == str(root) for root in roots):
            fail(f'physical target outside admitted roots: {logical}')
        row = rows[logical]
        if row['physicalPath'] != relative or row['sha256'] != sha(physical) or row['bytes'] != physical.stat().st_size:
            fail(f'archive byte binding changed: {logical}')
    captures = refs.get('macCaptures')
    if not isinstance(captures, list) or [row.get('run') for row in captures] != list(range(1,21)):
        fail('Mac capture rows must be fixed 1..20')
    for row in captures:
        path = (HERE / row['path']).resolve(strict=True)
        if not path.is_file() or row['sha256'] != sha(path) or row['bytes'] != path.stat().st_size:
            fail(f'Mac capture binding changed: run {row.get("run")}')
    report = (HERE / manifest['macReport']).resolve(strict=True)
    report_value = json.loads(report.read_text(encoding='utf-8'))
    mac = report_value.get('macOS', {})
    if mac.get('count') != 20 or mac.get('originProof', {}).get('verified') != 180 or mac.get('originProof', {}).get('failures') != []:
        fail('Mac report origin proof incomplete')
    pending = not manifest['windowsArchives']
    print(json.dumps({'status':'PASS','macPathMapCount':len(path_map),'macCaptureCount':20,'macReportSha256':sha(report),'windowsJoins':'pending' if pending else 'bound'} ,sort_keys=True))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
