"""Stage exact finalized source inputs & invoke retained-handle bounded Windows job."""
import argparse
import base64
import hashlib
import json
from pathlib import Path, PureWindowsPath
import subprocess

parser=argparse.ArgumentParser()
parser.add_argument('--host',choices=('image','image-star-provider','rounded-stroke','rounded-stroke-centered','rounded-stroke-circular','stack-overlay-centered'),required=True)
args=parser.parse_args()
repo=Path('/Volumes/D/claude/swiftright')
out=repo/f'factory/pipeline/pilot-delivery-five-v1/root-execution/{args.host}-compile-r1'
request=json.loads((out/'final-builder-request.json').read_text())
plan_name='plan-prebuild-native-r2.json' if args.host=='image' else 'plan-prebuild-v4.json'
builder_name='build-owned-native-r2.ps1' if args.host=='image' else 'build-owned-pilot-v1.ps1'
names=(plan_name,builder_name,'plan-final-v4.json','build-owned-final-v1.ps1','final-remote-entry.ps1')
sources=[]
for name in names:
    path=out/name
    assert path.is_file() and not path.is_symlink() and path.stat().st_size<=512*1024
    raw=path.read_bytes()
    assert b'Remove-Item' not in raw and b'SendToRecycleBin' not in raw
    sources.append({'path':name,'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),
                    'base64':base64.b64encode(raw).decode()})
assert sum(row['bytes'] for row in sources)<=1024*1024
assert sources[2]['sha256']==request['planSha256']
assert 'sha256:'+sources[3]['sha256']==request['builderSha256']
stage=str(PureWindowsPath(r'D:\Claude\swiftright\.factory-work\hosts')/args.host)
remote_script=stage+r'\stage-final-r1.ps1'
remote_receipt=stage+r'\final-r1-transport.json'
script=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Stage='__STAGE__';$Requests=Join-Path $Stage 'requests-final-r1'
if(@(Get-Process swift,swiftc,swift-build,clang,FactoryProbe -ErrorAction SilentlyContinue).Count){throw 'compiler/native lane busy'}
if(Test-Path -LiteralPath $Requests){throw 'fresh final requests required'}
New-Item -ItemType Directory -Path $Requests|Out-Null
$Rows='__ROWS__'|ConvertFrom-Json
foreach($Row in @($Rows)){
  $P=Join-Path $Requests $Row.path
  [IO.File]::WriteAllBytes($P,[Convert]::FromBase64String($Row.base64))
  $I=Get-Item -LiteralPath $P
  if($I.Length -ne $Row.bytes -or (Get-FileHash -LiteralPath $P).Hash.ToLowerInvariant() -cne $Row.sha256){throw 'staged finalized source drift'}
}
& (Join-Path $Requests 'final-remote-entry.ps1') -PreflightOnly
& (Join-Path $Requests 'final-remote-entry.ps1')
$R=Join-Path $Stage 'final-r1\observation.json'
if(-not(Test-Path -LiteralPath $R)){throw 'actual final receipt absent'}
Get-Content -Raw -LiteralPath $R
'''.replace('__STAGE__',stage).replace('__ROWS__',json.dumps(sources,separators=(',',':')))
path=out/'stage-final-r1.ps1'
with path.open('x') as stream:stream.write(script)
manifest={'kind':'factory-pilot-final-source-delivery-v1','host':args.host,
          'rows':[{k:v for k,v in row.items() if k!='base64'} for row in sources],
          'scriptSha256':hashlib.sha256(script.encode()).hexdigest(),
          'remoteScript':remote_script,'remoteReceipt':remote_receipt,'nativeActions':0}
(out/'final-source-delivery.json').write_text(json.dumps(manifest,indent=2)+'\n')
runner=Path('/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/git-root/run_pinned_windows_v1.py')
result=subprocess.run(['python3',str(runner),'--script',str(path),'--remote-script',remote_script,
                       '--remote-receipt',remote_receipt,'--archive',str(out/'actual-final-r1-transport'),
                       '--deadline','600','--compiler-budget'],timeout=720,check=False)
raise SystemExit(result.returncode)
