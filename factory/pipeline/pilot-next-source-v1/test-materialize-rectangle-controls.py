#!/usr/bin/env python3
"""Production materializer negative controls; no native or compiler actions."""
from __future__ import annotations
import argparse, copy, importlib.util, json
from pathlib import Path

MAX_JSON = 2 * 1024 * 1024

def load_json(path: Path) -> dict:
    st = path.stat()
    if not path.is_file() or path.is_symlink() or st.st_size > MAX_JSON:
        raise ValueError(f'bounded regular JSON required: {path}')
    return json.loads(path.read_bytes())

def load_materializer(path: Path):
    spec = importlib.util.spec_from_file_location('rectangle_materializer', path)
    if spec is None or spec.loader is None: raise RuntimeError('materializer import failed')
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--tuple', type=Path, required=True)
    ap.add_argument('--materializer', type=Path, default=Path(__file__).with_name('materialize-rectangle-case.py'))
    args = ap.parse_args()
    materializer = load_materializer(args.materializer)
    baseline = load_json(args.tuple)
    materializer.validate_tuple(baseline)
    faults = {
      'missing-macos-host': lambda x: x['hostHashes'].pop('macos'),
      'missing-windows-host': lambda x: x['hostHashes'].pop('windows'),
      'runtime-drift': lambda x: x.__setitem__('runtimeCommit', '0' * 40),
      'renderer-drift': lambda x: x.__setitem__('rendererHash', 'sha256:' + '0' * 64),
      'macos-host-drift': lambda x: x['hostHashes'].__setitem__('macos', 'sha256:' + '0' * 64),
      'windows-host-drift': lambda x: x['hostHashes'].__setitem__('windows', 'sha256:' + '0' * 64),
    }
    results = {}
    for name, mutate in faults.items():
        candidate = copy.deepcopy(baseline); mutate(candidate)
        try:
            materializer.validate_tuple(candidate)
        except ValueError as error:
            results[name] = {'accepted': False, 'reason': str(error)}
        else:
            results[name] = {'accepted': True, 'reason': 'unexpected acceptance'}
    passed = all(not result['accepted'] for result in results.values())
    print(json.dumps({'kind':'pilot-next-materializer-controls-v1','status':'PASS' if passed else 'HELD','controlOnly':True,'nativeWindowActions':0,'compilerActions':0,'baselineAccepted':True,'faults':results},sort_keys=True))
    return 0 if passed else 1

if __name__ == '__main__': raise SystemExit(main())
