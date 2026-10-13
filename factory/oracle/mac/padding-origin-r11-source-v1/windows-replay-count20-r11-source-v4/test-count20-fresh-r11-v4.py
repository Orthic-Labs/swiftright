#!/usr/bin/env python3
"""Source-only controls for fresh Count20 r11 namespace overlay."""
from __future__ import annotations
import copy, hashlib, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[5]
PACKET=ROOT/'factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v4'
MAP=PACKET/'source-map-v4.json'
EXPECTED_CASE='sha256:037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de'
EXPECTED_TUPLE='sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011'
EXPECTED_MAC='sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777'
EXPECTED_EXE='sha256:3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10'
FILES=('issue-count20-fresh-r11-v4.ps1','guard-count20-fresh-r11-v4.ps1','launch-count20-fresh-r11-v4.ps1','resume-issued-coordinator-fresh-r11.ps1','interactive-task-fresh-r11.ps1','dispatch-fresh-r11.ps1','capture-fresh-r11.ps1','integration-fresh-r11-v1.ps1')

def sha(path: Path) -> str:
    return 'sha256:'+hashlib.sha256(path.read_bytes()).hexdigest()

def validate(m: dict) -> None:
    assert m['schema']=='factory-windows-count20-r11-fresh-coordinator-source-map-v4'
    assert m['status']=='source-ready-root-controlled-native-pending'
    assert m['candidateOnly'] is True and m['count']==20 and m['donorRebindForbidden'] is True
    assert m['requiredFreshCaseHash']==EXPECTED_CASE and m['requiredFreshTupleID']==EXPECTED_TUPLE
    assert m['actualMacHostHash']==EXPECTED_MAC and m['actualWindowsExeHash']==EXPECTED_EXE
    assert m['effects']=={'compilerActions':0,'nativeWindowActions':0,'remoteActions':0,'lockActions':0}
    assert m['executionOverlay']['parameterContract']==['ProducerRoot','ControlRoot','RunRoot','OutputRoot','FreshGuardControlsPath','FreshGuardControlsHash','IntegrationGuardPath','IntegrationGuardHash']
    assert m['executionOverlay']['sequence'][0]=='issue-count20-fresh-r11-v4.ps1'
    for name in FILES:
        p=PACKET/name; assert p.exists() and m['executionOverlay']['files'][name]['sha256']==sha(p)

def source_assertions() -> None:
    texts={name:(PACKET/name).read_text() for name in FILES}
    for name,t in texts.items():
        if not name.endswith(('-v3.ps1','-v4.ps1')) and not name.startswith('integration-'):
            assert 'ProducerRoot' in t and 'RunRoot' in t and 'FreshGuardControlsPath' in t
        if not name.startswith('integration-'):
            assert 'actual-repeat-r1' not in t and 'Assert-LeaseIssuedMetadata' not in t
        if name.endswith('-v4.ps1'):
            if name.startswith(('issue-','guard-')):
                assert '037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de' in t
                assert 'f9a8e685f55c8063fde159bfb58926c637cd740fc8c6edb71de702933b7e3878' in t
            if name.startswith('issue-'):
                assert '13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777' in t
        elif not name.startswith('integration-'):
            assert 'freshGuard' in t or 'FreshGuard' in t
    assert '-ProducerRoot $c.producerRoot' in texts['interactive-task-fresh-r11.ps1']
    assert 'Assert-FactoryIntegrationSources' in texts['integration-fresh-r11-v1.ps1']
    assert '-ProducerRoot $ProducerRoot' in texts['dispatch-fresh-r11.ps1']
    assert 'capture-fresh-r11.ps1' in texts['dispatch-fresh-r11.ps1']
    cap=texts['capture-fresh-r11.ps1']
    frozen=(ROOT/'factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r7/capture-repeat-r7.ps1').read_text()
    imports=lambda x: sorted(line.strip() for line in x.splitlines() if 'DllImport(' in line)
    assert imports(cap)==imports(frozen)
    assert 'workerInventories' in texts['resume-issued-coordinator-fresh-r11.ps1']

def fault_controls(m: dict) -> dict[str,str]:
    faults={}
    cases=[
      ('tuple-id-drift',lambda q:q.__setitem__('requiredFreshTupleID','sr1-source-bound-r11-20261011')),
      ('case-hash-drift',lambda q:q.__setitem__('requiredFreshCaseHash','sha256:'+'0'*64)),
      ('mac-host-truncated',lambda q:q.__setitem__('actualMacHostHash',EXPECTED_MAC[:-1])),
      ('exe-truncated',lambda q:q.__setitem__('actualWindowsExeHash',EXPECTED_EXE[:-1])),
      ('donor-rebind',lambda q:q.__setitem__('donorRebindForbidden',False)),
      ('native-effect',lambda q:q['effects'].__setitem__('nativeWindowActions',1)),
    ]
    for name,mut in cases:
        q=copy.deepcopy(m); mut(q)
        try: validate(q)
        except (AssertionError,KeyError): faults[name]='rejected'
        else: raise AssertionError(name)
    return faults

def main() -> None:
    m=json.loads(MAP.read_text()); validate(m); source_assertions(); faults=fault_controls(m)
    print(json.dumps({'status':'PASS','positive':'fresh-r11-overlay-source-map','faults':faults,'nativeWindowActions':0,'lockActions':0,'compilerActions':0,'remoteActions':0},sort_keys=True))
if __name__=='__main__': main()
