[CmdletBinding()]
param(
    [string]$Repo = 'D:\Claude\swiftright'
)
$ErrorActionPreference = 'Stop'
$runtime = Join-Path $Repo '.factory-work\runtime-stage\runtime'
$scratch = Join-Path $Repo '.factory-work\runtime-stage\runtime-api-image-r1-scratch'
if ($runtime -ne 'D:\Claude\swiftright\.factory-work\runtime-stage\runtime') { throw 'canonical runtime stage required' }
if (-not (Test-Path -LiteralPath (Join-Path $runtime 'Package.swift'))) { throw 'runtime package missing' }
if (Test-Path -LiteralPath $scratch) { throw 'fresh scratch path required' }
$swift = 'swift.exe'
$argv = @(
    'test',
    '--package-path', $runtime,
    '--scratch-path', $scratch,
    '--jobs', '1',
    '-Xswiftc', '-j1',
    '-Xswiftc', '-num-threads',
    '-Xswiftc', '1'
)
& $swift @argv
$code = $LASTEXITCODE
if ($null -eq $code) { throw 'swift exit code unavailable' }
exit ([int]$code)
