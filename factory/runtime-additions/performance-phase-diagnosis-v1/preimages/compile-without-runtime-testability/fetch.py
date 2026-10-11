"""Fetch exact retained receipts/streams via base64, preserving Windows bytes."""
import base64,hashlib,json,subprocess
from pathlib import Path
HERE=Path(__file__).resolve().parent
root=r'D:\Claude\factory-swiftright-perfphase-pair-v1-20261011'
script='$ErrorActionPreference="Stop";$ProgressPreference="SilentlyContinue";$root="'+root+'";$files=@();foreach($dir in @($root,(Join-Path $root "compiler-version"),(Join-Path $root "original-build"),(Join-Path $root "current-build"),(Join-Path $root "original-test"),(Join-Path $root "current-test"))){if(Test-Path -LiteralPath $dir){foreach($f in Get-ChildItem -LiteralPath $dir -File){$b=[IO.File]::ReadAllBytes($f.FullName);$files+=[ordered]@{path=$f.FullName.Substring($root.Length+1);sha256=(Get-FileHash -LiteralPath $f.FullName).Hash.ToLowerInvariant();bytes=$b.Length;base64=[Convert]::ToBase64String($b)}}}};ConvertTo-Json -InputObject ([object[]]$files) -Depth 5 -Compress'
r=subprocess.run(['ssh','-o','BatchMode=yes','win','powershell','-NoProfile','-EncodedCommand',base64.b64encode(script.encode('utf-16le')).decode()],capture_output=True,timeout=60)
(HERE/'fetch-transport.stdout').write_bytes(r.stdout);(HERE/'fetch-transport.stderr').write_bytes(r.stderr)
if r.returncode:raise RuntimeError('SSH fetch failed '+str(r.returncode))
rows=json.loads(r.stdout.decode('utf-8-sig'));dest=HERE/'captured';dest.mkdir(exist_ok=True)
for row in rows:
 raw=base64.b64decode(row.pop('base64'));assert len(raw)==row['bytes'] and hashlib.sha256(raw).hexdigest()==row['sha256'];f=dest/row['path'].replace('\\','/');assert '..' not in f.parts;f.parent.mkdir(exist_ok=True,parents=True)
 if f.exists():assert f.read_bytes()==raw
 else:f.write_bytes(raw)
(HERE/'captured-input-manifest.json').write_text(json.dumps({'remoteRoot':root,'files':rows},indent=2)+'\n')
print(len(rows),'captured files')
