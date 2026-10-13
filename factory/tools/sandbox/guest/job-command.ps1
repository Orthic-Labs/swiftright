# job-command.ps1 - kind=command. args: {"script":"<powershell text>"}. Runs it in a child powershell, stores stdout+stderr in out.txt, result.json has the exit code.
param([Parameter(Mandatory)][string]$JobDir)
$ErrorActionPreference = 'Continue'
$job = Get-Content -LiteralPath "$JobDir\job.json" -Raw | ConvertFrom-Json
$enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes([string]$job.args.script))
& powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $enc 2>&1 | ForEach-Object { [string]$_ } | Out-File -LiteralPath "$JobDir\out.txt" -Encoding utf8
$ec = $LASTEXITCODE
[IO.File]::WriteAllText("$JobDir\result.json", (ConvertTo-Json @{ kind = 'command'; ok = ($ec -eq 0); exit_code = $ec }), (New-Object Text.UTF8Encoding($false)))
exit 0
