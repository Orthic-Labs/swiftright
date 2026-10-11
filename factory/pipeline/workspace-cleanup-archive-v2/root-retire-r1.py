#!/usr/bin/env python3
"""Root-only retirement of exactly hash-preserved internal Mac scratch roots."""
from pathlib import Path
import datetime, importlib.util, json, os, shutil

PACKET = Path(__file__).resolve().parent
PIN = 'sha256:d752681c7526631e55c7f73415f026a4f1a0704359d2cd5900d35c6de290ef1f'
CACHE = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory')

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

def main():
    receipt = PACKET / 'root-retirement-r1.json'
    assert not receipt.exists(), 'immutable retirement receipt already exists'
    restore = module('scratch_restore', PACKET / 'restore.py')
    archive = module('scratch_archive', PACKET / 'archive.py')
    descriptor, manifest = restore.load_archive(PACKET / 'archive-descriptor.json', PIN)
    verification = json.loads((PACKET / 'root-verification-r1.json').read_text())
    assert verification['status'] == 'PASS' and verification['descriptorSha256'] == PIN, 'full archive verification must pass'
    roots = [Path(x) for x in descriptor['roots']]
    assert len(roots) == 64 and len(set(roots)) == 64
    exclusions = [Path(x) for x in descriptor['excludedRoots']]
    for root in roots:
        assert root.is_absolute() and root.is_relative_to(CACHE) and root != CACHE
        assert root.resolve() == root and root.is_dir() and not root.is_symlink()
        assert all(not excluded.is_relative_to(root) for excluded in exclusions)
    before = archive.snapshot(roots)
    expected = {row['path']: row for row in manifest['files']}
    links = {row['path']: row['target'] for row in manifest['symlinks']}
    seen, seen_links, allocated = set(), set(), 0
    for root in roots:
        for base, directories, files in os.walk(root, followlinks=False):
            base = Path(base)
            for name in directories + files:
                path = base / name
                if path.is_symlink():
                    assert str(path) in links and os.readlink(path) == links[str(path)]
                    seen_links.add(str(path))
            directories[:] = [x for x in directories if not (base / x).is_symlink()]
            for name in files:
                path = base / name
                if path.is_symlink():
                    continue
                assert path.is_file() and str(path) in expected, str(path)
                row = expected[str(path)]
                first = path.stat()
                assert first.st_size == row['bytes'] and archive.hashfile(path) == row['sha256'], str(path)
                last = path.stat()
                assert (first.st_size, first.st_mtime_ns, first.st_ino) == (last.st_size, last.st_mtime_ns, last.st_ino)
                seen.add(str(path))
                allocated += first.st_blocks * 512
            if len(seen) % 10000 == 0:
                print(json.dumps({'verifiedFiles': len(seen)}), flush=True)
    assert seen == set(expected) and seen_links == set(links), 'live membership changed since preservation'
    ready = archive.snapshot(roots)
    plan = {'scope': 'exact owned internal Mac scratch; no Dell deletion',
            'archiveDescriptorSha256': PIN,
            'verificationSha256': archive.hashfile(PACKET / 'root-verification-r1.json'),
            'rootCount': len(roots), 'regularFileCount': len(seen),
            'symlinkCount': len(seen_links), 'allocatedBytesBefore': allocated,
            'before': before, 'preRetirement': ready, 'actions': []}
    plan_path = PACKET / 'root-retirement-intent-r1.json'
    with plan_path.open('x') as stream:
        json.dump(plan, stream, indent=2)
        stream.write('\n')
    for root in roots:
        shutil.rmtree(root)
        assert not root.exists()
        plan['actions'].append({'path': str(root), 'action': 'byte-preserved-owned-scratch-removed'})
    plan['after'] = archive.snapshot(roots)
    plan['completedAt'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    plan['verdict'] = 'PASS'
    with receipt.open('x') as stream:
        json.dump(plan, stream, indent=2)
        stream.write('\n')
    print(json.dumps({'verdict': 'PASS', 'retiredRoots': len(roots), 'allocatedBytesBefore': allocated}), flush=True)

if __name__ == '__main__':
    main()
