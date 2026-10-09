# Runs the SwiftRightServices package build and tests on Windows (headless).
# Invoke: powershell -NoProfile -ExecutionPolicy Bypass -File D:\Claude\sr3-services\scripts\run-tests.ps1
$ErrorActionPreference = 'Continue'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Set-Location (Split-Path -Parent $PSScriptRoot)
$log = Join-Path (Get-Location) 'swift-test-windows.log'
swift build *>&1 | Tee-Object -FilePath $log
if ($LASTEXITCODE -ne 0) { Write-Output "swift build failed: $LASTEXITCODE"; exit $LASTEXITCODE }
swift test *>&1 | Tee-Object -FilePath $log -Append
$code = $LASTEXITCODE
Write-Output "swift test exit: $code (log: $log)"
exit $code
