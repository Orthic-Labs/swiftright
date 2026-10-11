#!/usr/bin/env python3
"""Build Mac capture host on internal disk only; launch nothing."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json, os, shutil
from pathlib import Path
from factory.core.artifacts import canonical_hash

def load_module(path: Path):
 spec=importlib.util.spec_from_file_location('seed_origin_v5_prepare',path); mod=importlib.util.module_from_spec(spec); assert spec.loader; spec.loader.exec_module(mod); return mod

def digest(p: Path): return 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()
def internal(p: Path):
 p=p.expanduser().resolve(); root=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory').resolve()
 if not p.is_relative_to(root) or p == root: raise SystemExit('output must be fresh child of internal SwiftRightFactory cache')
 return p

def main():
 ap=argparse.ArgumentParser(); ap.add_argument('--manifest',type=Path,required=True); ap.add_argument('--case',type=Path,required=True); ap.add_argument('--output',type=Path,required=True); a=ap.parse_args()
 manifest=json.loads(a.manifest.read_text()); case=json.loads(a.case.read_text())
 if manifest.get('case') != {'id':case['id'],'hash':canonical_hash(case)}: raise SystemExit('manifest/case binding mismatch')
 if case['tuple']['id'] != 'sr1-source-bound-r11-20261011': raise SystemExit('unexpected base tuple')
 out=internal(a.output); work=out/'work'; evidence=out/'evidence'
 if out.exists() and any(out.iterdir()): raise SystemExit('output must be fresh')
 work.mkdir(parents=True); evidence.mkdir()
 # Resolve from repository packet layout, then enforce exact manifest source bytes.
 repo=Path(os.environ.get('SWIFTRIGHT_REPO_ROOT','/Volumes/D/claude/swiftright')).resolve()
 source_path=repo/'factory/oracle/mac/seed-origin-v5/inputs'/manifest['sourceFile']
 if digest(source_path) != manifest['sourceHash']: raise SystemExit('source hash mismatch')
 shutil.copy2(source_path,work/'Witness.swift')
 harness=repo/'factory/oracle/mac/padding-origin-r11-source-v1/CaptureHost.swift'; shutil.copy2(harness,work/'CaptureHost.swift')
 adapted=(work/'CaptureHost.swift').read_text().replace('__WITNESS_TYPE__',manifest['witnessType']); (work/'CaptureHost.swift').write_text(adapted)
 collector=load_module(repo/'factory/oracle/mac/seed-origin-v5/capture_origin.py')
 binary=work/'capture-host'; result, receipt=collector.compiler_build(work,evidence,binary)
 if result.returncode != 0 or not binary.is_file(): raise SystemExit(f'host compile failed: {result.returncode}')
 if receipt.get('status') != 'SUCCESS': raise SystemExit(f'host receipt status {receipt.get("status")}')
 payload={'schema':'factory-macos-r11-host-build-receipt-v1','status':'internal-host-built-no-native-launch','candidateOnly':True,'case':{'id':case['id'],'hash':canonical_hash(case)},'tupleTemplate':case['tuple'],'source':{'path':str(source_path),'sha256':digest(source_path),'bytes':source_path.stat().st_size},'adapter':{'path':str(work/'CaptureHost.swift'),'sha256':digest(work/'CaptureHost.swift'),'bytes':(work/'CaptureHost.swift').stat().st_size},'binary':{'path':str(binary),'sha256':digest(binary),'bytes':binary.stat().st_size},'compilerReceipt':receipt,'effects':{'nativeWindowActions':0,'compilerActions':1,'remoteActions':0,'lockActions':0}}
 (out/'host-build-r1.json').write_text(json.dumps(payload,sort_keys=True,indent=2)+'\n'); print(json.dumps({'status':payload['status'],'hostHash':payload['binary']['sha256'],'hostBytes':payload['binary']['bytes'],'effects':payload['effects']}))
if __name__=='__main__': main()
