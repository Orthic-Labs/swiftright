#!/usr/bin/env python3
"""Offline Count20 repeat producer source admission."""
import hashlib
from pathlib import Path

HERE=Path(__file__).resolve().parent
SOURCE=HERE/'produce-repeat-inputs-r2.py'
GUARD='d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904'
ISSUER='ee30fdd3f83459a62a2024fe95b22bf228b1471cf7498642181e49c2d473d66e'
HASHES={
 'resume-issued-coordinator-repeat-r2.ps1':'d4359512dd4f6efe2f13dad301b12d14b5099130185fbfcf9b4572f0ecbef043',
 'interactive-task-repeat-r2.ps1':'e9d2d2055f8c5e89439046e843cd11e5820aab742da88eda1c6f90ec7305a929',
 'dispatch-repeat-r2.ps1':'3b61a3d60ef5509ce6852a38e8441cdec44b7e05b989b02c018634f43ee507d1',
 'capture-repeat-r2.ps1':'45f795f3a41551a2931c50fbfd9763405f0ea6bac249edc93f8f42a12499a5d7',
 'integration-prefixed-ids-r1.ps1':GUARD,
}
def main():
 s=SOURCE.read_text()
 assert 'expectedCount") != 20' in s and 'len(run_maps) != 20' in s
 assert 'overlay_root.endswith("/repeat-r2")' in s
 assert 'issuerSource' in s and ISSUER in s
 assert 'prefixed issuer' in s
 for name,h in HASHES.items(): assert h in s,name
 for name,h in HASHES.items():
  p=HERE.parents[4]/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r2'/name
  assert p.is_file(),str(p)
  assert hashlib.sha256(p.read_bytes()).hexdigest()==h,name
 assert hashlib.sha256((HERE.parents[4]/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/issuer-overlay-r1/issue-before-launch-prefixed-r1.ps1').read_bytes()).hexdigest()==ISSUER
 print('PASS Count20 repeat producer source admission; native/lock/compiler/remote actions=0')
if __name__=='__main__': main()
