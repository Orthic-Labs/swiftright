$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$path='D:\Claude\swiftright\.gitignore'
$old=if(Test-Path -LiteralPath $path){[IO.File]::ReadAllText($path)}else{''}
if($old -notmatch '(?m)^/\.factory-work/\r?$'){[IO.File]::AppendAllText($path,"`n# Local factory runtime, staging & scratch`n/.factory-work/`n",(New-Object Text.UTF8Encoding($false)))}
[pscustomobject]@{path=$path;ignoredPattern='/.factory-work/';verified=([IO.File]::ReadAllText($path) -match '(?m)^/\.factory-work/\r?$')}|ConvertTo-Json
