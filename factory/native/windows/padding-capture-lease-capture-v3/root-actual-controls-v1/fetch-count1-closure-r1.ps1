$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$rows=@(
 @{name='case.json';path='D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package\case.json';sha256=''},
 @{name='swiftright_render.dll';path='D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll';sha256='e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'},
 @{name='powershell.exe';path='C:\WINDOWS\System32\WindowsPowerShell\v1.0\powershell.exe';sha256='60c9b29843624dd8af6b6a7b26147753be6aeef65098b9a503cc50850afe410f'}
)
$zipPath='D:\Claude\swiftright\.factory-work\transports\count1-closure-r1.zip'
if(Test-Path -LiteralPath $zipPath){throw 'exclusive archive already exists'}
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($zipPath))|Out-Null
Add-Type -AssemblyName System.IO.Compression
$stream=[IO.File]::Open($zipPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
$zip=New-Object IO.Compression.ZipArchive($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
$manifest=@()
try{foreach($r in $rows){$bytes=[IO.File]::ReadAllBytes($r.path);$sha=(Get-FileHash -LiteralPath $r.path -Algorithm SHA256).Hash.ToLowerInvariant();if($r.sha256 -and $sha -cne $r.sha256){throw ('source hash drift '+$r.name)};$entry=$zip.CreateEntry($r.name);$out=$entry.Open();try{$out.Write($bytes,0,$bytes.Length)}finally{$out.Dispose()};$manifest+=@{path=$r.name;recordedPath=$r.path;bytes=$bytes.Length;sha256=$sha}}
$doc=[Text.Encoding]::UTF8.GetBytes((@{kind='root-count1-native-source-closure-fetch-v1';files=$manifest}|ConvertTo-Json -Depth 8));$entry=$zip.CreateEntry('manifest.json');$out=$entry.Open();try{$out.Write($doc,0,$doc.Length)}finally{$out.Dispose()}
}finally{$zip.Dispose();$stream.Dispose()}
@{zipPath=$zipPath;bytes=(Get-Item -LiteralPath $zipPath).Length;sha256=(Get-FileHash -LiteralPath $zipPath).Hash.ToLowerInvariant();files=$manifest}|ConvertTo-Json -Depth 8
