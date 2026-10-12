#!/usr/bin/env python3
"""Build source-bound Text Mac host on internal disk; launch nothing."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, shutil
from pathlib import Path
from factory.core.artifacts import canonical_hash

MAX_FILE = 64 * 1024 * 1024
MAX_JSON = 2 * 1024 * 1024

def load_json(path: Path):
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise SystemExit(f'bounded regular JSON required: {path}')
    return json.loads(path.read_bytes())

def digest(path: Path) -> str:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_FILE:
        raise SystemExit(f'bounded regular source required: {path}')
    h = hashlib.sha256()
    with path.open('rb') as stream:
        while chunk := stream.read(1024 * 1024): h.update(chunk)
    return 'sha256:' + h.hexdigest()

def load_module(path: Path):
    spec = importlib.util.spec_from_file_location('pilot_next_mac_compiler', path)
    if spec is None or spec.loader is None: raise SystemExit('compiler helper unavailable')
    mod = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod); return mod

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifest', type=Path, required=True)
    ap.add_argument('--case', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--expected-binary-hash')
    args = ap.parse_args()
    manifest = load_json(args.manifest)
    case = load_json(args.case)
    if manifest.get('case') != {'id': case['id'], 'hash': canonical_hash(case)}:
        raise SystemExit('manifest/case binding mismatch')
    if case.get('candidate') != 'swiftui.text.layout.baseline.pilot-next' and manifest.get('candidate') != 'swiftui.text.layout.baseline.pilot-next':
        raise SystemExit('unexpected pilot candidate')
    repo = Path(os.environ.get('SWIFTRIGHT_REPO_ROOT', '/Volumes/D/claude/swiftright')).resolve()
    source = (repo / manifest['sourceRepositoryPath']).resolve()
    if not source.is_relative_to(repo / 'factory') or digest(source) != manifest['sourceHash']:
        raise SystemExit('source path/hash binding failed')
    builder = load_module(Path(__file__).with_name('build_text_host.py'))
    payload = builder.build_host(args.output, expected_hash=args.expected_binary_hash, case=case, manifest=manifest)
    print(json.dumps({'status':payload['status'],'hostHash':payload['binary']['sha256'] if payload.get('binary') else None,'hostBytes':payload['binary']['bytes'] if payload.get('binary') else None,'effects':payload['effects']}))
    return 0
if __name__ == '__main__': raise SystemExit(main())
