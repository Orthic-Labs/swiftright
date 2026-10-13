"""Complete installed r13 admission with production AST fault controls."""
import base64
import hashlib
import json
from pathlib import Path

out = Path(__file__).resolve().parent
repo = out.parents[4]
controls = repo / 'factory/pipeline/sr0-display-selfjob-root-v4/root-failed-observer-controls-v2'
pins = json.loads((controls / 'source-pins.json').read_text())
failure = repo / pins['failureRoot']
remote = r'D:\Claude\swiftright\.factory-work\root-tools\sr0-r13-policy-completion-r2'
installer = r'D:\Claude\swiftright\.factory-work\root-tools\sr0-r13-root-v1-installer'
inputs = json.loads((out / 'installer-inputs.json').read_text())
args = inputs['arguments']

def q(s):
    return "'" + s.replace("'", "''") + "'"

def bounded(p):
    assert p.is_file() and not p.is_symlink() and p.stat().st_size < 131072
    return p.read_bytes()

files = {name: bounded(failure / name) for name in ('collector.json', 'coordinator.json', 'launcher.json')}
files['pins.json'] = bounded(controls / 'source-pins.json')
files['controls.ps1'] = bounded(controls / 'test-held-predicate-v13.ps1')
policy = bounded(out / 'test-observer-kernel-policy-r12.ps1').decode()
assert policy.count('$base=[pscustomobject]') == 1
# Preserve every schedule/native exit decision control. Held failure controls
# execute production AST against archived receipts separately below.
policy = policy.split('$base=[pscustomobject]')[0]
policy += "[ordered]@{status='passed-source-controls';cases=5;nativeActions=0;qualificationClaim=$false}|ConvertTo-Json\n"
files['schedule-controls.ps1'] = policy.encode()
observer = bounded(out / 'observer-source-r13.ps1')
assert hashlib.sha256(observer).hexdigest() == pins['observerSha256']
ps = "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'\n"
ps += "$root=" + q(remote) + ";if(Test-Path -LiteralPath $root){throw 'fresh policy completion required'};[IO.Directory]::CreateDirectory($root)|Out-Null\n"
for name, raw in files.items():
    h = hashlib.sha256(raw).hexdigest()
    ps += "$f=Join-Path $root " + q(name) + ";[IO.File]::WriteAllBytes($f,[Convert]::FromBase64String(" + q(base64.b64encode(raw).decode()) + "));if((Get-FileHash $f).Hash.ToLowerInvariant() -cne " + q(h) + "){throw 'completion source pin drift'}\n"
observer_path = installer + r'\observer-source-r13.ps1'
ps += "if((Get-FileHash " + q(observer_path) + ").Hash.ToLowerInvariant() -cne " + q(pins['observerSha256']) + "){throw 'installed observer drift'}\n"
ps += '& (Join-Path $root schedule-controls.ps1) -ObserverPath ' + q(observer_path) + '\n'
ps += '& (Join-Path $root controls.ps1) -FailureRoot $root -ObserverPath ' + q(observer_path) + ' -SourcePinsPath (Join-Path $root pins.json) -ControlRoot (Join-Path $root fault-results)\n'
ps += '& ' + q(installer + r'\test-manifest-admission-controls-r12.ps1') + ' -AdmissionManifestPath ' + q(args['ManifestPath']) + ' -ExpectedTaskName SR0-factory-display-selfjob-v7-root-r13 -ExpectedRunRoot ' + q(args['RunRoot']) + ' -AdmissionHelperPath ' + q(args['StageRoot'] + r'\admission-helper-r12.ps1') + ' -AdmissionHelperSha256 0a7f63f92ef3b83811acee15c4298e08e8b7c398c477695c056f9d467d78812b -ControlRoot (Join-Path $root manifest-controls)\n'
ps += '& ' + q(installer + r'\preflight-r12.ps1') + ' -StageRoot ' + q(args['StageRoot']) + ' -PlanPath ' + q(args['PlanPath']) + ' -AdmissionManifestPath ' + q(args['ManifestPath']) + ' -RunManifestPath ' + q(args['RunManifestPath']) + ' -ControlsReceiptPath ' + q(args['FactoryRoot'] + r'\drain-controls-r11.json') + ' -ReceiptPath (Join-Path $root fresh-preflight.json)\n'
ps += "$rows=@();$total=0;foreach($pair in @("
ps += ','.join('@(' + q(name) + ',' + q(path) + ')' for name, path in (
    ('plan.json', args['PlanPath']),
    ('drain-controls.json', args['FactoryRoot'] + r'\drain-controls-r11.json'),
    ('preflight.ps1', installer + r'\preflight-r12.ps1'),
))
ps += ")){$f=Get-Item $pair[1];if($f.Length -gt 1048576 -or ($f.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'completion export bound'};$raw=[IO.File]::ReadAllBytes($f.FullName);$total+=$raw.Length;if($total -gt 2097152){throw 'completion aggregate bound'};$rows+=@{path=$pair[0];bytes=$raw.Length;sha256=(Get-FileHash $f.FullName).Hash.ToLowerInvariant();base64=[Convert]::ToBase64String($raw)}}\n"
ps += "[ordered]@{status='exported';admissionStatus='root-source-admission-complete';files=$rows;bytes=$total;nativeActions=0;lockActions=0;qualificationClaim=$false}|ConvertTo-Json -Depth 12\n"
entry = out / 'run-policy-completion-r2.ps1'
entry.open('x').write(ps)
print(json.dumps({'status': 'prepared', 'bytes': entry.stat().st_size, 'nativeActions': 0}))
