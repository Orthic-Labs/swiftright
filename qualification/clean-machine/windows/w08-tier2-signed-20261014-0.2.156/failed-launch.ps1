# Failed-launch control (runs in the Windows Sandbox through client.py command). Release-signed old 0.1.0.0 from run 38551981243, installed on platform trust.
# A spawn failure of the guard installer is forced by denying the Sandbox user Execute on powershell.exe (Sandbox only; ownership and ACL are restored in the finally block and verified by spawning powershell again):
# CreateProcessW in the app then fails with access denied. (Pointing SystemRoot at a missing folder was tried first: the packaged app then does not start at all, so it cannot reach the installer code.) Expected: install-launch-failure.json with launchFailure, NO install-attempt.json,
# repair.log "[app] installer launch failed"; after SystemRoot is restored the next launch spawns the installer: task registered, failure record cleared.
$ErrorActionPreference = 'Continue'
$pkg = 'OrthicLabs.SliceApp'; $msix = 'C:\w08t2\pkgs-signed-0.2.156\old.msix'
$dir = Join-Path $env:LOCALAPPDATA 'SliceApp\repair'
function P([string]$m) { try { Add-Content -LiteralPath 'C:\sbq\fl-progress.txt' -Value ((Get-Date).ToString('HH:mm:ss.fff') + ' ' + $m) } catch { } }
P 'start'
$o = [ordered]@{ startedUtc = (Get-Date).ToUniversalTime().ToString('o'); oldSha256 = (Get-FileHash $msix -Algorithm SHA256).Hash.ToLower() }
function Launch { $p = Get-AppxPackage -Name $pkg | Select-Object -First 1; $id = [string](Get-AppxPackageManifest -Package $p.PackageFullName).Package.Applications.Application.Id; Start-Process explorer.exe ('shell:AppsFolder\' + $p.PackageFamilyName + '!' + $id) }
function StopApp { Get-Process SliceApp -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue }
function ReadG([string]$n) { try { (Get-Content -LiteralPath (Join-Path $dir $n) -Raw -ErrorAction Stop) -replace '\s+', ' ' } catch { $null } }
function State { [ordered]@{ files = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }); installAttemptJson = (ReadG 'install-attempt.json'); installLaunchFailureJson = (ReadG 'install-launch-failure.json'); taskRegistered = [bool](Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'OrthicLabs.SliceApp*-Repair' }); repairLog = @(Get-Content -LiteralPath (Join-Path $dir 'repair.log') -ErrorAction SilentlyContinue | ForEach-Object { [string]$_ }) } }
function WaitFor([scriptblock]$c, [int]$sec) { $e = (Get-Date).AddSeconds($sec); while ((Get-Date) -lt $e) { if (& $c) { return $true }; Start-Sleep -Milliseconds 500 }; return $false }
try {
    # clean slate (Sandbox only)
    StopApp
    Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'OrthicLabs*' } | ForEach-Object { Unregister-ScheduledTask -InputObject $_ -Confirm:$false -ErrorAction SilentlyContinue }
    Get-AppxPackage -Name $pkg -AllUsers | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'SliceApp') -Recurse -Force -ErrorAction SilentlyContinue
    P 'installing'; Add-AppxPackage -Path $msix -ErrorAction Stop; P 'installed'
    $o.installed = (Get-AppxPackage -Name $pkg | ForEach-Object { [string]$_.Version + ':' + [string]$_.Status })
    # phase 1: spawn failure
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $o.acl_before = (& icacls.exe $ps) -join ' | '
    & takeown.exe /f $ps | Out-Null
    & icacls.exe $ps /deny ($me + ':(X)') | Out-Null; P 'denied'
    $o.acl_denied = (& icacls.exe $ps) -join ' | '
    P 'phase1 launch'; Launch
    $o.phase1_failure_logged = WaitFor { (ReadG 'repair.log') -match 'installer launch failed' } 30
    Start-Sleep -Seconds 3
    P 'phase1 waited'; $o.phase1 = State; P 'phase1 state'
    StopApp
    # phase 2: spawn succeeds (ACL restored first)
    & icacls.exe $ps /remove:d $me | Out-Null
    & icacls.exe $ps /setowner 'NT SERVICE\TrustedInstaller' | Out-Null
    $o.acl_restored = (& icacls.exe $ps) -join ' | '
    Launch
    P 'phase2 launch'; $o.phase2_task_registered = WaitFor { [bool](Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'OrthicLabs.SliceApp*-Repair' }) } 60
    Start-Sleep -Seconds 3
    P 'phase2 waited'; $o.phase2 = State; P 'phase2 state'
    $o.phase2_install_result = ReadG 'install-result.json'
} catch { $o.error = $_.Exception.Message }
finally {
    & icacls.exe $ps /remove:d $me | Out-Null
    & icacls.exe $ps /setowner 'NT SERVICE\TrustedInstaller' | Out-Null
    $o.acl_final = (& icacls.exe $ps) -join ' | '
    P 'final'; $o.powershell_spawn_works = [bool]((Start-Process -FilePath $ps -ArgumentList '-NoProfile','-Command','exit 0' -Wait -PassThru -WindowStyle Hidden).ExitCode -eq 0); P 'done'
    StopApp
    Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like 'OrthicLabs*' } | ForEach-Object { Unregister-ScheduledTask -InputObject $_ -Confirm:$false -ErrorAction SilentlyContinue }
    Get-AppxPackage -Name $pkg -AllUsers | ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'SliceApp') -Recurse -Force -ErrorAction SilentlyContinue
    $o.endedUtc = (Get-Date).ToUniversalTime().ToString('o')
}
'JSON-BEGIN'; ($o | ConvertTo-Json -Depth 6); 'JSON-END'
