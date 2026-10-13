"""Validate measured r13 admission exports & write pinned native entry."""
import base64
import hashlib
import json
from pathlib import Path

out = Path(__file__).resolve().parent
p = out / 'actual-policy-transport-r2'
transport = json.loads((p / 'transport.json').read_text(encoding='utf-8-sig'))
assert transport['childTerminal'] and transport['childExitRaw'] == 0 and transport['childExitIdentity']
assert transport['streamsSealed'] and transport['selfOnly'] and not transport['memoryCapExceeded']
raw = (p / 'transport.json.stdout.bin').read_bytes()
assert len(raw) < 1048576
text = raw.decode('utf-8-sig')
start = text.rfind('\n{')
assert start >= 0
export = json.loads(text[start + 1:])
assert export['admissionStatus'] == 'root-source-admission-complete' and export['status'] == 'exported'
assert export['nativeActions'] == export['lockActions'] == 0
assert len(export['files']) == 3
verified = {}
for row in export['files']:
    assert row['path'] in ('plan.json', 'preflight.ps1', 'drain-controls.json') and row['path'] not in verified
    b = base64.b64decode(row['base64'], validate=True)
    assert len(b) == row['bytes'] <= 1048576 and hashlib.sha256(b).hexdigest() == row['sha256']
    verified[row['path']] = (row, b)
assert sum(len(b) for _, b in verified.values()) == export['bytes']
plan = json.loads(verified['plan.json'][1].decode('utf-8-sig'))
drain = json.loads(verified['drain-controls.json'][1].decode('utf-8-sig'))
assert len(plan['sourceFiles']) == 33 and plan['deadlineSeconds'] == 900 and plan['runs'] == 1
assert plan['noActivate'] and plan['noResources'] and not plan['qualificationClaim']
assert drain['status'] == 'passed-source-controls'
inputs = json.loads((out / 'installer-inputs.json').read_text())
args = inputs['arguments']
archive = out / 'actual-admission-r2'
archive.mkdir()
for name, (row, b) in verified.items():
    (archive / name).open('xb').write(b)
(archive / 'export-verification.json').open('x').write(json.dumps({
    'status': 'verified-source-admission', 'files': [{k: v for k, v in row.items() if k != 'base64'} for row, _ in verified.values()],
    'sourceCount': 33, 'qualificationClaim': False,
}, indent=2) + '\n')
old = out.parent / 'root-native-r12-observer-r13-r1/run-native.ps1'
entry = old.read_text()
entry = entry.replace('sr0-r12-root-v4-installer', 'sr0-r13-root-v1-installer').replace('v5-root-r12b', 'v5-root-r13').replace('one-run-v7-r12b', 'one-run-v7-r13')
observer = inputs['files']['observer-source-r13.ps1']
entry = entry.replace("23979,'b4e8f8c87a90a0bcd8aa444760ccc6d163ba109aacdcb9a6866639de17ef2c7e'", str(observer['bytes']) + ", '" + observer['sha256'] + "'")
entry = entry.replace('c20382642f5b05ffe73e6288a4204a1acb76a116ecf895f2bdc59ce8723951d6', verified['plan.json'][0]['sha256'])
entry = entry.replace("24291,'", str(verified['plan.json'][0]['bytes']) + ",'", 1)
entry = entry.replace('b5a38209e029e2df4dd57708e746174b2fda4b1c398dfa161c19f3b6992ee92c', verified['drain-controls.json'][0]['sha256'])
entry = entry.replace("9483,'", str(verified['drain-controls.json'][0]['bytes']) + ",'", 1)
entry = entry.replace('-DeadlineSeconds 1100', '-DeadlineSeconds 1000')
assert '-DeadlineSeconds 1000' in entry and 'root-r12' not in entry and 'root-r13' in entry
assert inputs['files']['preflight-r12.ps1']['sha256'] == verified['preflight.ps1'][0]['sha256']
(out / 'run-native-r1.ps1').open('x').write(entry)
print(json.dumps({'status': 'native-entry-prepared', 'planSha256': verified['plan.json'][0]['sha256'], 'sourceCount': 33, 'observerDeadlineSeconds': 1000, 'transportDeadlineSeconds': 1100, 'qualificationClaim': False}))
