"""Pin & stage two parser versions plus archived fixture for Windows controls."""
import base64
import hashlib
import json
from pathlib import Path

repo = Path(__file__).resolve().parents[4]
out = Path(__file__).resolve().parent
donor = repo / 'factory/pipeline/sr0-display-selfjob-root-v4/native-r10c-recovery-v1/workload-identity-v7.ps1'
fresh = repo / 'factory/pipeline/sr0-display-selfjob-root-v4/sr0-r12-parser-controls-v4/workload-identity-v7.ps1'
control = repo / 'factory/pipeline/sr0-display-selfjob-root-v4/sr0-r12-parser-controls-v5/test-parser-controls-v5.ps1'
pins = repo / 'factory/pipeline/sr0-display-selfjob-root-v4/sr0-r12-parser-controls-v5/source-pins.json'
fixture = repo / 'factory/pipeline/sr0-display-selfjob-root-v4/native-r10c-recovery-v1/root-native-r12-observer-r13-r1/actual-run-raw-r3/result-workload.txt'
rows = [('original.ps1', donor), ('fresh.ps1', fresh), ('controls.ps1', control), ('pins.json', pins), ('fixture.txt', fixture)]
sources = {}
for name, path in rows:
    assert path.is_file() and not path.is_symlink() and path.stat().st_size <= 65536
    sources[name] = path.read_bytes()
original, revised = sources['original.ps1'], sources['fresh.ps1']
old = b'$text=[IO.File]::ReadAllText($item.FullName)'
new = b'$text=([IO.File]::ReadAllText($item.FullName)).Replace("`r`n","`n")'
assert original.count(old) == 1 and original.replace(old, new) == revised
assert hashlib.sha256(original).hexdigest() == '4e7af8708f78b1613196cc710c6cd7222f9a0485984326bd2e390df422a2d9ad'
assert hashlib.sha256(sources['fixture.txt']).hexdigest() == 'c841626334d8b7a2ad9c13a1e72a4db49f6e64077b6e9bc622f2e4b387d0ae3e'
remote = r'D:\Claude\swiftright\.factory-work\root-tools\sr0-parser-controls-v5-r1'
def q(value):
    return "'" + value.replace("'", "''") + "'"
ps = "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'\n$root=" + q(remote) + ";if(Test-Path -LiteralPath $root){throw 'fresh parser controls required'};[IO.Directory]::CreateDirectory($root)|Out-Null\n"
manifest = []
for name, raw in sources.items():
    sha = hashlib.sha256(raw).hexdigest()
    manifest.append({'name': name, 'bytes': len(raw), 'sha256': sha})
    ps += "$f=Join-Path $root " + q(name) + ";[IO.File]::WriteAllBytes($f,[Convert]::FromBase64String(" + q(base64.b64encode(raw).decode()) + "));if((Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne " + q(sha) + "){throw 'parser control source drift'}\n"
ps += "& (Join-Path $root 'controls.ps1') -ResultPath (Join-Path $root 'fixture.txt') -OriginalHelperPath (Join-Path $root 'original.ps1') -FreshHelperPath (Join-Path $root 'fresh.ps1') -SourcePinsPath (Join-Path $root 'pins.json') -ControlRoot (Join-Path $root 'actual') -WrapperPid 58252\n"
with (out / 'run-controls.ps1').open('x') as stream:
    stream.write(ps)
with (out / 'source-inputs.json').open('x') as stream:
    stream.write(json.dumps({'files': manifest, 'nativeActions': 0, 'qualificationClaim': False}, indent=2) + '\n')
print(json.dumps({'status': 'prepared-parser-controls', 'files': len(manifest), 'nativeActions': 0}))
