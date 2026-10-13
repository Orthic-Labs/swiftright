"""Fresh SR0 staging: preserve r12 contracts, repair CRLF & failed-run reporting."""
import base64
import hashlib
import json
import re
import zipfile
from pathlib import Path

out = Path(__file__).resolve().parent
repo = out.parents[4]
old = out.parent / 'root-source-admission-r12-v4'
cache = Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/git-root')
def read(path):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size <= 2 * 1024 * 1024
    return path.read_bytes()
def sha(raw):
    return hashlib.sha256(raw).hexdigest()
def write(path, raw):
    with path.open('xb') as stream:
        stream.write(raw)
def q(value):
    return "'" + value.replace("'", "''") + "'"
inputs = json.loads(read(old / 'installer-inputs.json'))
entry = read(old / 'run-admission.ps1').decode()
files = {}
pattern = r"Join-Path \$root '([^']+)';\[IO.File\]::WriteAllBytes\(\$f,\[Convert\]::FromBase64String\('([^']+)'\)"
for name, encoded in re.findall(pattern, entry):
    raw = base64.b64decode(encoded, validate=True)
    pin = inputs['files'][name]
    assert len(raw) == pin['bytes'] and sha(raw) == pin['sha256']
    files[name] = raw
assert set(files) == set(inputs['files'])
meta = json.loads(read(old / 'source-pack-metadata.json'))
fresh_helper = repo / 'factory/pipeline/sr0-display-selfjob-root-v4/sr0-r12-parser-controls-v4/workload-identity-v7.ps1'
identity = next(row for row in meta['sourceRows'] if row['name'] == 'identityHelper')
original = read(repo / identity['source'])
needle = b'$text=[IO.File]::ReadAllText($item.FullName)'
replacement = b'$text=([IO.File]::ReadAllText($item.FullName)).Replace("`r`n","`n")'
assert original.count(needle) == 1 and original.replace(needle, replacement) == read(fresh_helper)
identity['source'] = fresh_helper.relative_to(repo).as_posix()
identity['bytes'] = fresh_helper.stat().st_size
identity['sha256'] = sha(read(fresh_helper))
zip_path = cache / 'sr0-r13-root-v1-sources.zip'
total = 0
with zipfile.ZipFile(zip_path, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
    for row in meta['sourceRows']:
        raw = read(repo / row['source'])
        assert len(raw) == row['bytes'] and sha(raw) == row['sha256']
        total += len(raw)
        assert total <= 2 * 1024 * 1024
        archive.writestr('source/' + row['path'], raw)
    meta['sourceTotalBytes'] = total
    raw_meta = (json.dumps(meta, indent=2) + '\n').encode()
    archive.writestr('source-pack-metadata.json', raw_meta)
files['metadata.json'] = raw_meta
files['install_r12_sources.ps1'] = files['install_r12_sources.ps1'].replace(b'SR0-factory-display-selfjob-v7-root-r12', b'SR0-factory-display-selfjob-v7-root-r13')
observer = files['observer-source-r13.ps1'].decode()
old_line = next(line for line in observer.splitlines() if line.startswith('function Test-FailedQuiescentReceipts('))
new_line = "function Test-FailedQuiescentReceipts([object]$launcher,[object]$collector,[object]$coordinator){if($null -eq $launcher -or $null -eq $collector -or $null -eq $coordinator){return $false};return ([string]$launcher.status -ceq 'held' -and [string]$collector.status -ceq 'failed' -and [string]$coordinator.status -ceq 'held' -and [bool]$launcher.coordinatorHandleAcquired -and [bool]$launcher.coordinatorTerminal -and [bool]$launcher.coordinatorExitIdentity -and [bool]$launcher.collectorHandleAcquired -and [bool]$launcher.collectorTerminal -and [bool]$launcher.collectorExitIdentity -and [bool]$launcher.aggregateDescendantsQuiesced -and [int64]$launcher.aggregateActiveAfter -eq 1 -and [bool]$coordinator.parentKernelTerminal -and [int64]$coordinator.parentExitRaw -eq 1 -and [int64]$coordinator.parentExitSigned -eq 1 -and [int64]$coordinator.parentExitDotnet -eq 1 -and [bool]$collector.parentOriginalHandleRetained -and [bool]$collector.presentMonHandleAcquired -and [bool]$collector.presentMonTerminal -and [bool]$collector.presentMonExitIdentity -and [bool]$collector.workloadHandleAcquired -and [bool]$collector.workloadTerminal -and [bool]$collector.workloadExitIdentity -and [bool]$collector.activeSelfOnly -and [int64]$collector.activeAfter -eq 1)}"
assert observer.count(old_line) == 1
files['observer-source-r13.ps1'] = observer.replace(old_line, new_line).encode()
remote = r'D:\Claude\swiftright\.factory-work\root-tools\sr0-r13-root-v1-installer'
args = {key: value.replace('sr0-r12-root-v4', 'sr0-r13-root-v1').replace('v5-root-r12b', 'v5-root-r13').replace('one-run-v7-r12b', 'one-run-v7-r13') for key, value in inputs['arguments'].items()}
args['ZipPath'] = r'D:\Claude\swiftright\.factory-work\root-tools\sr0-r13-root-v1-sources.zip'
ps = "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'\n$root=" + q(remote) + ";if(Test-Path -LiteralPath $root){throw 'fresh r13 installer required'};[IO.Directory]::CreateDirectory($root)|Out-Null\n"
for name, raw in files.items():
    write(out / name, raw)
    ps += "$f=Join-Path $root " + q(name) + ";[IO.File]::WriteAllBytes($f,[Convert]::FromBase64String(" + q(base64.b64encode(raw).decode()) + "));if((Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne " + q(sha(raw)) + "){throw 'r13 installer pin drift'}\n"
    if name.endswith('.ps1'):
        ps += "$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($f,[ref]$t,[ref]$e);if($e.Count){throw 'r13 source parse failure'}\n"
zip_sha = sha(read(zip_path))
ps += "if((Get-FileHash -LiteralPath " + q(args['ZipPath']) + ").Hash.ToLowerInvariant() -cne " + q(zip_sha) + "){throw 'r13 ZIP pin drift'}\n"
ps += '& ' + q(remote + r'\install_r12_sources.ps1') + ' ' + ' '.join('-' + key + ' ' + q(value) for key, value in args.items()) + ' -RunControls\n'
ps += '& ' + q(remote + r'\test-manifest-admission-controls-r12.ps1') + ' -AdmissionManifestPath ' + q(args['ManifestPath']) + ' -ExpectedTaskName SR0-factory-display-selfjob-v7-root-r13 -ExpectedRunRoot ' + q(args['RunRoot']) + ' -AdmissionHelperPath ' + q(args['StageRoot'] + r'\admission-helper-r12.ps1') + ' -AdmissionHelperSha256 0a7f63f92ef3b83811acee15c4298e08e8b7c398c477695c056f9d467d78812b -ControlRoot ' + q(remote + r'\admission-controls') + '\n'
ps += '& ' + q(remote + r'\test-observer-kernel-policy-r12.ps1') + ' -ObserverPath ' + q(remote + r'\observer-source-r13.ps1') + '\n'
ps += "[ordered]@{status='root-source-admission-complete';sourceCount=33;nativeActions=0;lockActions=0}|ConvertTo-Json\n"
write(out / 'run-admission.ps1', ps.encode())
proof = {'files': {name: {'bytes': len(raw), 'sha256': sha(raw)} for name, raw in files.items()}, 'arguments': args, 'zipPath': args['ZipPath'], 'zipSha256': zip_sha, 'nativeActions': 0, 'qualificationClaim': False}
write(out / 'installer-inputs.json', (json.dumps(proof, indent=2) + '\n').encode())
print(json.dumps({'status': 'prepared', 'sourceCount': 30, 'zipSha256': zip_sha, 'nativeActions': 0}))
