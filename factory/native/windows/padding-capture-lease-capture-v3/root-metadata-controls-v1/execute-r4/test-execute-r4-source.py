#!/usr/bin/env python3
"""Offline source admission for prefixed-ID Count1 execution overlay."""
import hashlib, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
BASE=HERE.parents[1]
FILES=['coordinator-r4.ps1','interactive-task-r4.ps1','dispatch-r4.ps1','capture-repeat-r4.ps1','integration-prefixed-ids-r1.ps1','test-metadata-guard-controls-r4.ps1']
GUARD='d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904'
ISSUER='ee30fdd3f83459a62a2024fe95b22bf228b1471cf7498642181e49c2d473d66e'
def main():
 assert (BASE/'capture-plan.json').is_file()
 for n in FILES: assert (HERE/n).is_file(),n
 issuer=BASE/'root-metadata-controls-v1/issuer-overlay-r1/issue-before-launch-prefixed-r1.ps1'
 assert issuer.is_file()
 assert hashlib.sha256(issuer.read_bytes()).hexdigest()==ISSUER
 for n in ('coordinator-r4.ps1','dispatch-r4.ps1','capture-repeat-r4.ps1'):
  s=(HERE/n).read_text(); assert 'integration-prefixed-ids-r1.ps1' in s; assert GUARD in s; assert "support\\integration.ps1" not in s
 assert 'interactive-task-r4.ps1' in (HERE/'coordinator-r4.ps1').read_text()
 assert 'dispatch-r4.ps1' in (HERE/'interactive-task-r4.ps1').read_text()
 assert 'capture-repeat-r4.ps1' in (HERE/'dispatch-r4.ps1').read_text()
 assert '[ValidateSet(1)]' in (HERE/'coordinator-r4.ps1').read_text()
 control=(HERE/'test-metadata-guard-controls-r4.ps1').read_text()
 assert "Join-Path $PSScriptRoot '..\\..\\support\\integration.ps1'" in control
 assert "Join-Path $PSScriptRoot 'integration-prefixed-ids-r1.ps1'" in control and '. $guardPath' in control and GUARD in control
 for name in ('admitted-baseline-actual','admitted-baseline-relocated-resealed','metadata-expected-count','metadata-host-argument','metadata-source-hash','metadata-serializer-prefix','metadata-runtime-modules','tuple-case','tuple-runtime','tuple-renderer','binding-frozen','binding-canonical-input-hash','mac-context-path'):
  assert name in control,name
 assert control.count("@{name='")>=11
 assert (HERE/'integration-prefixed-ids-r1.ps1').read_text().count("^capture/[0-9a-f]{32}$")==1
 assert (HERE/'integration-prefixed-ids-r1.ps1').read_text().count("^image/[0-9a-f]{32}$")==1
 assert hashlib.sha256((HERE/'integration-prefixed-ids-r1.ps1').read_bytes()).hexdigest()==GUARD
 manifest=json.loads((HERE/'root-stage-manifest.json').read_text())
 for row in manifest['files']:
  raw=(HERE/row['path']).read_bytes(); assert len(raw)==row['bytes'] and 'sha256:'+hashlib.sha256(raw).hexdigest()==row['sha256'],row['path']
 frozen=BASE/'root-metadata-controls-v1/execute-r3/root-stage-manifest.json'; m=json.loads(frozen.read_text())
 for row in m['files']:
  p=frozen.parent/row['path']; assert p.is_file(); assert len(p.read_bytes())==row['bytes']; assert 'sha256:'+hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256']
 print('PASS execute-r4 source admission; frozen r3 preserved; native/lock/compiler/remote actions=0')
if __name__=='__main__':main()
