import copy
import datetime
import hashlib
import json
import pathlib
import struct

ROOT = pathlib.Path('/Volumes/D/claude/swiftright')
PACKET = ROOT / 'factory/native/windows/first-capture-corrections-v1'
BUILD = PACKET / 'build-actual-r1'

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def load(p):
    return json.loads(p.read_text(encoding='utf-8-sig'))

def validate(receipt, owned, plan):
    assert receipt['exitCode'] == 0 and receipt['timedOut'] is False and receipt['ownedExited'] is True
    assert receipt['nativeWindowOpened'] is False and receipt['nativeParity'] == 'hold'
    assert receipt['frozenTupleBound'] is False and receipt['closureBinding'] is None
    assert receipt['pid'] == owned['pid'] and receipt['processStartedAt'] == owned['startedAt']
    assert receipt['cwd'] == owned['cwd'] == 'D:\\Claude\\swiftright\\factory\\native\\windows\\first-capture-corrections-v1\\package'
    assert owned['path'] == plan['compilerPath']
    assert receipt['argv'] == owned['argv']
    cwd = receipt['cwd']
    dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
    expected = 'build --package-path "' + cwd + '" --scratch-path "' + cwd + '\\build-r1\\scratch" -c release -Xlinker /MANIFEST:EMBED -Xlinker "' + dep + '" -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup'
    assert receipt['argv'] == expected
    dates = [datetime.datetime.fromisoformat(receipt[k].replace('Z', '+00:00')) for k in ('startedAt', 'processStartedAt', 'finishedAt')]
    assert dates[0] <= dates[1] < dates[2] and (dates[2] - dates[0]).total_seconds() < 310
    assert receipt['planSha256'] == digest(PACKET / 'package/plan.json')
    for k in ('sourceHash', 'rendererSha256', 'runtimeSourceCommit', 'runtimeSourceTreeHash', 'compilerHash'):
        assert receipt[k] == plan[k]
    assert receipt['exePath'] == cwd + '\\build-r1\\scratch\\out\\Products\\Release-windows-x86_64\\FactoryProbe.exe'
    assert receipt['exeSha256'] == digest(BUILD / 'FactoryProbe.exe')
    assert receipt['exeSubsystem'] == 2
    assert {x['path'] for x in receipt['files']} == {'FactoryProbe.exe', 'owned-process.json', 'compile.stdout.txt', 'compile.stderr.txt'}
    assert len(receipt['files']) == 4
    for row in receipt['files']:
        assert row['sha256'] == digest(BUILD / row['path'])

def main():
    receipt = load(BUILD / 'observation.json')
    owned = load(BUILD / 'owned-process.json')
    plan = load(PACKET / 'package/plan.json')
    validate(receipt, owned, plan)
    binary = (BUILD / 'FactoryProbe.exe').read_bytes()
    assert binary[:2] == b'MZ'
    pe = struct.unpack_from('<I', binary, 60)[0]
    assert binary[pe:pe+4] == b'PE\0\0'
    assert struct.unpack_from('<H', binary, pe+4)[0] == 0x8664
    assert struct.unpack_from('<H', binary, pe+24)[0] == 0x20b
    assert struct.unpack_from('<H', binary, pe+24+68)[0] == 2
    assert (BUILD / 'compile.stderr.txt').read_bytes() == b''
    assert b'Build complete!' in (BUILD / 'compile.stdout.txt').read_bytes()
    faults = [('exeSha256', '0'*64), ('planSha256', '0'*64), ('pid', receipt['pid']+1),
              ('processStartedAt', receipt['finishedAt']), ('argv', receipt['argv']+' -Xswiftc -D WRONG'),
              ('runtimeSourceCommit', 'wrong'), ('sourceHash', 'wrong'), ('exitCode', 1),
              ('timedOut', True), ('ownedExited', False), ('exeSubsystem', 3)]
    rejected = []
    for key, value in faults:
        changed = copy.deepcopy(receipt); changed[key] = value
        try:
            validate(changed, owned, plan)
        except AssertionError:
            rejected.append(key)
        else:
            raise AssertionError('fault accepted: '+key)
    print(json.dumps({'baseline':'pass', 'faultsRejected':rejected, 'reviewerNativeExecution':0,
                      'reviewerCompilerExecution':0, 'argvEvidence':'constructed ProcessStartInfo arguments & receipt; no OS-CIM observed argv claim'}, indent=2))

if __name__ == '__main__':
    main()
