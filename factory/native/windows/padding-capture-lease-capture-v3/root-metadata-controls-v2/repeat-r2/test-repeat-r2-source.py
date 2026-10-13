#!/usr/bin/env python3
"""Offline Count20 repeat-r2 source admission; no PowerShell/native effects."""
import hashlib, json
from pathlib import Path

HERE=Path(__file__).resolve().parent
CAPTURE=HERE.parents[1]
FILES={
 'resume':'resume-issued-coordinator-repeat-r2.ps1',
 'interactive':'interactive-task-repeat-r2.ps1',
 'dispatch':'dispatch-repeat-r2.ps1',
 'capture':'capture-repeat-r2.ps1',
 'guard':'integration-prefixed-ids-r1.ps1',
}
GUARD='d4a20512937c6a7cb1e5751e02566276290897cb56203a99b40cfcccf486e904'

def body(key): return (HERE/FILES[key]).read_text(encoding='utf-8')

def main():
 plan=json.loads((CAPTURE/'capture-plan.json').read_text(encoding='utf-8'))
 repeat=plan['dispatch']['repeat']
 assert repeat['count']==20 and repeat['runRoot'].endswith('actual-repeat-r1')
 assert repeat['firstProofRequired'] is True and plan['dispatch']['retries'] is False
 for name,path in FILES.items(): assert (HERE/path).is_file(),path
 all_text='\n'.join(body(k) for k in FILES)
 for bad in ('dispatch.batch','actual-batch-r1','coordinator-batch-r1','capture-repeat-batch.ps1','interactive-task-batch.ps1','resume-issued-coordinator-repeat.ps1','interactive-task-repeat.ps1','dispatch-repeat.ps1','capture-repeat-repeat.ps1'):
  assert bad not in all_text,bad
 assert 'interactive-task-repeat-r2.ps1' in body('resume')
 assert 'dispatch-repeat-r2.ps1' in body('interactive')
 assert 'capture-repeat-r2.ps1' in body('dispatch')
 assert body('guard').count("^capture/[0-9a-f]{32}$")==1
 assert body('guard').count("^image/[0-9a-f]{32}$")==1
 assert hashlib.sha256((HERE/FILES['guard']).read_bytes()).hexdigest()==GUARD
 for name in ('resume','dispatch','capture'):
  text=body(name)
  assert 'integration-prefixed-ids-r1.ps1' in text and GUARD in text
  assert 'support\\integration.ps1' not in text
  assert '[ValidateSet(20)]' in text or name=='capture'
  assert 'Assert-PaddingFirstCaptureProof' in text
 assert '[ValidateSet(20)]' in body('capture')
 manifest=json.loads((HERE/'root-stage-manifest.json').read_text(encoding='utf-8'))
 for row in manifest['files']:
  raw=(HERE/row['path']).read_bytes()
  assert len(raw)==row['bytes'] and 'sha256:'+hashlib.sha256(raw).hexdigest()==row['sha256'],row['path']
 frozen=CAPTURE/'root-metadata-controls-v1/execute-r3'
 frozen_manifest=json.loads((frozen/'root-stage-manifest.json').read_text(encoding='utf-8'))
 for row in frozen_manifest['files']:
  p=frozen/row['path'].split('/')[-1]; raw=p.read_bytes()
  assert len(raw)==row['bytes'] and 'sha256:'+hashlib.sha256(raw).hexdigest()==row['sha256'],str(p)
 print('PASS repeat-r2 source admission; native/lock/compiler/remote actions=0')

if __name__=='__main__': main()
