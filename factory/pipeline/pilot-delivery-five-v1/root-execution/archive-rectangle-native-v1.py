from pathlib import Path
import argparse,hashlib,json,subprocess,zipfile
p=argparse.ArgumentParser();p.add_argument('--count',type=int,choices=(1,20),required=True);p.add_argument('--revision',type=int,required=True);p.add_argument('--archive-attempt',type=int,choices=range(1,5),default=1);p.add_argument('--prepare-only',action='store_true');a=p.parse_args()
assert 1<=a.revision<=5
tag=('r' if a.count==1 else 'count20-r')+str(a.revision)
base=Path('factory/pipeline/pilot-delivery-five-v1/root-execution')/('rectangle-color-capture-'+tag)
ns='D:\\Claude\\swiftright\\.factory-work\\hosts\\rectangle\\captures\\color-'+tag
counttag='count'+str(a.count)+'-r1'
script=r'''$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Root='__ROOT__';$CountTag='__TAG__';$Zip=Join-Path $Root 'actual-native-r__ATTEMPT__.zip';$Manifest=Join-Path $Root 'actual-native-manifest-r__ATTEMPT__.json'
if(Test-Path -LiteralPath $Zip){throw 'fresh native archive required'}
$Co=Get-Content -LiteralPath (Join-Path $Root ('control-'+$CountTag+'\coordinator.json')) -Raw|ConvertFrom-Json
if($Co.status -cne 'completed-source-bound-observation' -or $Co.count -ne __COUNT__ -or -not $Co.lockReleased -or -not $Co.wholeBatchExitConfirmed -or @($Co.cleanupErrors).Count -or $Co.taskParentProof.kernelWait -ne 0 -or $Co.taskParentProof.kernelExitCode -ne 0 -or $Co.taskParentProof.dotNetExitCode -ne 0){throw 'fresh native completion required'}
$Rows=@();$Total=0
foreach($Rel in @(('control-'+$CountTag),('native\'+$CountTag))){
 foreach($F in @(Get-ChildItem -LiteralPath (Join-Path $Root $Rel) -File -Recurse)){
  $Total+=$F.Length;if($Rows.Count -ge 1600 -or $F.Length -gt 16777216 -or $Total -gt 33554432 -or ($F.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'archive size/path cap'}
  $Rows+=@{path=$F.FullName.Substring($Root.Length+1).Replace('\','/');bytes=$F.Length;sha256=(Get-FileHash -LiteralPath $F.FullName).Hash.ToLowerInvariant()}
 }
}
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$Z=[IO.Compression.ZipFile]::Open($Zip,[IO.Compression.ZipArchiveMode]::Create)
try{foreach($R in $Rows){[IO.Compression.ZipFileExtensions]::CreateEntryFromFile($Z,(Join-Path $Root $R.path),$R.path,[IO.Compression.CompressionLevel]::Optimal)|Out-Null}}finally{$Z.Dispose()}
$M=[ordered]@{kind='factory-rectangle-actual-native-archive-v1';root=$Root;count=__COUNT__;files=$Rows;bytes=$Total;zipBytes=(Get-Item -LiteralPath $Zip).Length;zipSha256=(Get-FileHash -LiteralPath $Zip).Hash.ToLowerInvariant();sourceHash='sha256:5a41b5d411509e5e9d293cc56943c7270394c176ba863b0533921ac22a87792d';exeHash=$Co.exeHash;compileReceiptHash=$Co.compileReceiptHash;lockReleased=$Co.lockReleased;qualified=$false}
$M|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Manifest -Encoding UTF8
[ordered]@{count=$M.count;files=$Rows.Count;bytes=$Total;manifestSha256=(Get-FileHash -LiteralPath $Manifest).Hash.ToLowerInvariant();zipSha256=$M.zipSha256;qualified=$false}|ConvertTo-Json
'''.replace('__ROOT__',ns).replace('__TAG__',counttag).replace('__COUNT__',str(a.count)).replace('__ATTEMPT__',str(a.archive_attempt))
if a.prepare_only:
 dest=base/('archive-native-r'+str(a.archive_attempt)+'.ps1');assert not dest.exists();dest.write_text(script);print(str(dest));raise SystemExit
out=base/('actual-native-r'+str(a.archive_attempt));out.mkdir()
zipname='actual-native-r'+str(a.archive_attempt)+'.zip';manifestname='actual-native-manifest-r'+str(a.archive_attempt)+'.json'
for name in (zipname,manifestname):
 subprocess.run(['scp','-q','win:'+ns.replace('\\','/')+'/'+name,str(out/name)],check=True,timeout=20)
def sha(path):
 assert path.is_file() and not path.is_symlink() and path.stat().st_size<=33554432
 h=hashlib.sha256()
 with path.open('rb') as f:
  for b in iter(lambda:f.read(1048576),b''):h.update(b)
 return h.hexdigest()
m=json.loads((out/manifestname).read_text(encoding='utf-8-sig'))
assert m['count']==a.count and m['lockReleased'] and not m['qualified'] and len(m['files'])<=1600 and m['bytes']<=33554432
assert (out/zipname).stat().st_size==m['zipBytes'] and sha(out/zipname)==m['zipSha256']
expected={r['path']:r for r in m['files']};assert len(expected)==len(m['files'])
with zipfile.ZipFile(out/zipname) as archive:
 assert len(archive.infolist())==len(expected)
 for info in archive.infolist():
  rel=Path(info.filename);assert not rel.is_absolute() and '..' not in rel.parts and '\\' not in info.filename and ':' not in info.filename
  row=expected[info.filename];assert info.file_size==row['bytes'] and info.file_size<=16777216
  dest=out/'files'/rel;dest.parent.mkdir(parents=True,exist_ok=True)
  with archive.open(info) as source,dest.open('xb') as target:
   while True:
    b=source.read(1048576)
    if not b:break
    target.write(b)
  assert sha(dest)==row['sha256']
print(json.dumps({'count':a.count,'files':len(expected),'bytes':m['bytes'],'status':'actual-bytes-verified','qualified':False}))
