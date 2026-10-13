"""Prepare bounded SR0 archive export & capture-held production controls."""
import base64
import hashlib
import json
from pathlib import Path

out = Path(__file__).resolve().parent
repo = out.parents[4]
packet = repo / 'factory/pipeline/sr0-display-selfjob-root-v4/sr0-r13-capture-held-reader-v1'
remote = r'D:\Claude\swiftright\.factory-work\root-tools\sr0-r13-export-r1'
root = r'D:\Claude\swiftright\factory\native\windows\.work\sr0-display-selfjob-v4\one-run-v7-r13'

def q(s):
    return "'" + s.replace("'", "''") + "'"

ps = "$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'\n$export=" + q(remote) + ";if(Test-Path $export){throw 'fresh SR0 archive export required'};[IO.Directory]::CreateDirectory($export)|Out-Null\n"
for name in ('capture-held-predicate-v13.ps1', 'test-capture-held-controls-v1.ps1', 'source-pins.json'):
    p = packet / name
    assert p.is_file() and not p.is_symlink() and p.stat().st_size < 131072
    b = p.read_bytes()
    ps += "$f=Join-Path $export " + q(name) + ";[IO.File]::WriteAllBytes($f,[Convert]::FromBase64String(" + q(base64.b64encode(b).decode()) + "));if((Get-FileHash $f).Hash.ToLowerInvariant() -cne " + q(hashlib.sha256(b).hexdigest()) + "){throw 'archive control pin mismatch'}\n"
ps += '$root=' + q(root) + ';$run=Join-Path $root run\n'
ps += "& (Join-Path $export 'test-capture-held-controls-v1.ps1') -CaptureRoot $run -PredicatePath (Join-Path $export 'capture-held-predicate-v13.ps1') -SourcePinsPath (Join-Path $export 'source-pins.json') -ControlRoot (Join-Path $export controls) | Set-Content (Join-Path $export capture-held-controls.json) -Encoding UTF8\n"
ps += """
$groups=@(@{name='run';root=$run;recurse=$true},@{name='factory';root=$root;recurse=$false},@{name='controls';root=(Join-Path $export controls);recurse=$true})
$files=@();$total=[long]0
foreach($g in $groups){
 $items=@(Get-ChildItem -LiteralPath $g.root -Force -Recurse:$g.recurse)
 if($items.Count -gt 512){throw 'archive inventory bound'}
 foreach($f in $items){
  if(($f.Attributes -band [IO.FileAttributes]::ReparsePoint)-ne 0){throw 'archive reparse rejected'}
  if($f.PSIsContainer){continue}
  if($f.Length -gt 4194304){throw 'archive file bound'}
  $total+=$f.Length;if($files.Count -ge 512 -or $total -gt 33554432){throw 'archive aggregate bound'}
  $files+=@{path=($g.name+'/'+$f.FullName.Substring($g.root.Length+1).Replace('\','/'));originalPath=$f.FullName;bytes=$f.Length;sha256=(Get-FileHash $f.FullName).Hash.ToLowerInvariant()}
 }
}
$f=Get-Item (Join-Path $export capture-held-controls.json);$files+=@{path='capture-held-controls.json';originalPath=$f.FullName;bytes=$f.Length;sha256=(Get-FileHash $f.FullName).Hash.ToLowerInvariant()};$total+=$f.Length
$manifest=Join-Path $export export-manifest.json
@{kind='sr0-r13-raw-capture-export-v1';files=$files;totalBytes=$total;count=$files.Count;qualificationClaim=$false;nativeActions=0}|ConvertTo-Json -Depth 16|Set-Content $manifest -Encoding UTF8
Add-Type -AssemblyName System.IO.Compression
$zip=Join-Path $export raw.zip;$s=[IO.File]::Open($zip,[IO.FileMode]::CreateNew);$a=[IO.Compression.ZipArchive]::new($s,[IO.Compression.ZipArchiveMode]::Create,$false)
try{foreach($row in $files){$e=$a.CreateEntry($row.path);$o=$e.Open();$i=[IO.File]::OpenRead($row.originalPath);try{$i.CopyTo($o,1048576)}finally{$i.Dispose();$o.Dispose()};if((Get-FileHash $row.originalPath).Hash.ToLowerInvariant() -cne $row.sha256){throw 'archive input changed'}};$e=$a.CreateEntry('export-manifest.json');$o=$e.Open();$i=[IO.File]::OpenRead($manifest);try{$i.CopyTo($o,1048576)}finally{$i.Dispose();$o.Dispose()}}finally{$a.Dispose();$s.Dispose()}
@{status='exported';zipPath=$zip;zipBytes=(Get-Item $zip).Length;zipSha256=(Get-FileHash $zip).Hash.ToLowerInvariant();files=$files.Count;bytes=$total;qualificationClaim=$false;nativeActions=0}|ConvertTo-Json
"""
(out / 'export-native-r1.ps1').open('x').write(ps)
print(json.dumps({'status': 'prepared', 'nativeActions': 0, 'qualificationClaim': False}))
