#!/usr/bin/env python3
"""Source-only controls for strict semantic-equivalence admission."""
from __future__ import annotations
import json, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
BASE = ROOT / 'factory/oracle/mac/padding-origin-r11-source-v1'
GEN = BASE / 'generated/13bfe5b8fbd9'
WIN = ROOT / 'factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1'
ACT = WIN / 'observed-native20-r7/actual-repeat-r1'
ARC = WIN / 'adapter-v6-r7/trusted-reader-archive-r7/capture-bd1cba8c7017fc5cfc343288191ebd130f6f38730f69266301194ebcac81e7de'
FRESH = BASE / 'windows-replay-admission-r1/fresh-windows-source-r11-h13bfe5b8fbd9'
ADMIT = Path(__file__).with_name('admit-windows-replay-v3-equivalence.py')

def run(td: Path, mutate=None, expect_success=False):
    td.mkdir(parents=True, exist_ok=True)
    src = {
      'case': GEN/'cases/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.json',
      'manifest': GEN/'manifests/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9.manifest.json',
      'tuple': GEN/'candidate-tuple.json', 'donor-tuple': ACT/'candidate-tuple.json',
      'windows-executable': ARC/'FactoryProbe.exe', 'witness-manifest': FRESH/'witness.manifest.json',
      'witness-source': FRESH/'swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.swift',
      'donor-witness-manifest': ARC/'host/witness.manifest.json', 'actual-receipt': ACT/'observation.json',
      'actual-plan': ACT/'plan.json', 'actual-binding': ACT/'candidate-binding.json',
      'actual-proof-bundle': WIN/'adapter-v6-r7/proof-bundle-r7-v2c.actual.json',
      'actual-reader': WIN/'adapter-v6-r7/trusted-reader-count20-r7.actual.json',
      'actual-compiler': ARC/'tool/compiler.bin', 'actual-runtime-receipt': ACT/'runtime-source-receipt.json',
      'actual-runtime-tree': ACT/'runtime-source-tree.json',
    }
    local={}
    for key,path in src.items():
        dest=(td/'donor-witness.manifest.json') if key == 'donor-witness-manifest' else (td/path.name if key in ('witness-source','witness-manifest') else td/(key.replace('-', '_')+path.suffix)); shutil.copyfile(path,dest); local[key]=dest
    if mutate: mutate(local)
    out=td/'result.json'; cmd=[sys.executable,str(ADMIT)]
    for key,path in local.items(): cmd += ['--'+key,str(path)]
    cmd += ['--output',str(out)]
    p=subprocess.run(cmd,text=True,capture_output=True)
    result=json.loads(out.read_text())
    wanted=0 if expect_success else 2
    if p.returncode != wanted: raise AssertionError((p.returncode,wanted,p.stdout,p.stderr,result))
    return result

def main():
  with tempfile.TemporaryDirectory(prefix='r11-equivalence-controls-') as name:
    root=Path(name)
    good=run(root/'good',expect_success=True)
    if good['status']!='reuse-admitted-source-equivalent-v3' or not good['equivalence']['semanticInputsEqual']: raise AssertionError(good)
    def semantic_fault(f):
      x=json.loads(f['witness-manifest'].read_text()); x['caseInputs']['width']=97; f['witness-manifest'].write_text(json.dumps(x))
    bad_sem=run(root/'semantic',semantic_fault)
    if not any('semantic inputs differ' in r for r in bad_sem['reasons']): raise AssertionError(bad_sem)
    def binary_fault(f): f['windows-executable'].write_bytes(f['windows-executable'].read_bytes()+b'swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258')
    bad_bin=run(root/'binary',binary_fault)
    if not any('case metadata token' in r for r in bad_bin['reasons']): raise AssertionError(bad_bin)
    def proof_fault(f): f['actual-proof-bundle'].write_text(json.dumps({'archiveBindings':{}}))
    bad_roles=run(root/'roles',proof_fault)
    if not any('proof archive missing roles' in r for r in bad_roles['reasons']): raise AssertionError(bad_roles)
  print(json.dumps({'status':'PASS','baseline':'reuse-admitted-source-equivalent-v3','faults':['semantic-input-drift','binary-case-token','missing-proof-roles']}))

if __name__=='__main__': main()
