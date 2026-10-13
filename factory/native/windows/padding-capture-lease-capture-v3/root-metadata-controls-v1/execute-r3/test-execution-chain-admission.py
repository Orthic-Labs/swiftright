"""Headless Count1 r3 chain admission; source/fixture checks only."""
from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

def read(p: Path): return json.loads(p.read_text(encoding='utf-8-sig'))
def digest(p: Path): return hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok: bool, msg: str):
    if not ok: raise SystemExit(msg)

def manifest_gate(manifest: dict, binding: Path, hash_override=None, bytes_override=None):
    rows=[x for x in manifest.get('files',[]) if x.get('path')=='factory/native/windows/padding-capture-lease-capture-v3/integration-bindings.json']
    require(len(rows)==1, 'manifest binding row missing/duplicate')
    expected='sha256:'+digest(binding) if hash_override is None else hash_override
    expected_bytes=binding.stat().st_size if bytes_override is None else bytes_override
    return rows[0].get('sha256')==expected and rows[0].get('bytes')==expected_bytes

ap=argparse.ArgumentParser()
ap.add_argument('--source-root', required=True, help='capture-v3 source root')
ap.add_argument('--overlay-root', required=True, help='installed execute-r3 directory')
ap.add_argument('--actual-root', required=True, help='archived root-actual-controls-v1 fixture root')
a=ap.parse_args(); source=Path(a.source_root).resolve(); overlay=Path(a.overlay_root).resolve(); actual=Path(a.actual_root).resolve()
manifest=read(source/'root-stage-manifest.json'); binding=source/'integration-bindings.json'
require(overlay.name=='execute-r3', 'unexpected overlay root')
files={name:(overlay/name).read_text(encoding='utf-8') for name in ('coordinator-r3.ps1','interactive-task-r3.ps1','dispatch-r3.ps1','capture-repeat-r3.ps1')}
for name,text in files.items():
    require('$baseRoot=[IO.Path]::GetFullPath((Join-Path $overlayRoot \'..\\..\'))' in text, f'{name} lacks explicit base root')
    require('$PSScriptRoot' in text, f'{name} lacks explicit overlay root source')
    if name == 'interactive-task-r3.ps1':
        require('$c.count -ne 1' in text, f'{name} is not Count1-only')
    else:
        require('[ValidateSet(1)]' in text, f'{name} is not Count1-only')
    require('$bindingEntry[0].hash' not in text, f'{name} retains stale hash field')
for name in ('coordinator-r3.ps1','dispatch-r3.ps1','capture-repeat-r3.ps1'):
    text=files[name]
    require('$bindingEntry[0].sha256' in text and '$bindingEntry[0].bytes' in text, f'{name} lacks sha256+bytes gate')
# Chain wiring is explicit and overlay-local.
require("interactive-task-r3.ps1" in files['coordinator-r3.ps1'], 'coordinator chain edge missing')
require("dispatch-r3.ps1" in files['interactive-task-r3.ps1'], 'interactive chain edge missing')
require("capture-repeat-r3.ps1" in files['dispatch-r3.ps1'], 'dispatch chain edge missing')
# Gate ordering: manifest checks precede lock/native entry points.
coord=files['coordinator-r3.ps1']; dispatch=files['dispatch-r3.ps1']; capture=files['capture-repeat-r3.ps1']
require(coord.index('$bindingEntry[0].sha256') < coord.index("$lock='D:\\Claude\\desktop.lock'"), 'coordinator manifest gate follows lock declaration')
require(dispatch.index('$bindingEntry[0].sha256') < dispatch.index('$buildPreflightPath'), 'dispatch manifest gate follows launch preflight')
require(capture.index('$bindingEntry[0].sha256') < capture.index('Initialize-FactoryFinalExitNative'), 'capture manifest gate follows native initializer')
# Baseline + deliberate manifest faults, without changing any file.
cases={
    'baseline': manifest_gate(manifest,binding),
    'manifest-wrong-hash': manifest_gate(manifest,binding,hash_override='sha256:'+'0'*64),
    'manifest-wrong-bytes': manifest_gate(manifest,binding,bytes_override=binding.stat().st_size+1),
}
require(cases['baseline'] is True, 'baseline manifest gate failed')
require(cases['manifest-wrong-hash'] is False, 'wrong hash fault was admitted')
require(cases['manifest-wrong-bytes'] is False, 'wrong bytes fault was admitted')
# Archived actual fixture joins remain required before any native path.
issued=actual/'observed-metadata-r1/coordinator-single-r1/issued-metadata.json'
tuple_file=actual/'observed-metadata-r1/coordinator-single-r1/candidate-tuple.json'
guard=actual/'observed-metadata-r1/actual/metadata-controls-r1.json'
schema=actual/'mac-schema-receipt-r1.json'; review=actual/'root-metadata-review-r1.json'
for p in (issued,tuple_file,guard,schema,review): require(p.is_file(), 'fixture missing: '+str(p))
idoc=read(issued); g=read(guard); sr=read(schema); rv=read(review)
require(idoc.get('expectedCount')==1 and g.get('count')==1, 'fixture Count1 mismatch')
require(digest(issued)==g.get('issuedMetadataSha256')==rv.get('issuedMetadataSha256'), 'issued metadata join mismatch')
require(digest(guard)==rv.get('guardControlsSha256'), 'guard review join mismatch')
require(g.get('baseline',{}).get('accepted') is True and len(g.get('faultControls',[]))==12, 'guard fixture incomplete')
require(sr.get('rootNonce')==idoc.get('runID') and sr.get('exitCode')==0, 'schema fixture nonce/exit mismatch')
require(sr.get('candidateTupleRef',{}).get('sha256')=='sha256:'+digest(tuple_file), 'schema tuple hash mismatch')
require(sr.get('candidateTupleRef',{}).get('bytes')==tuple_file.stat().st_size, 'schema tuple bytes mismatch')
print(json.dumps({'kind':'factory-count1-r3-headless-chain-admission','status':'passed-source-only','cases':{k:('accepted' if v else 'rejected') for k,v in cases.items()},'fixtureIssuedMetadataSha256':digest(issued),'fixtureGuardControlsSha256':digest(guard),'nativeWindowActions':0,'lockActions':0},sort_keys=True))
