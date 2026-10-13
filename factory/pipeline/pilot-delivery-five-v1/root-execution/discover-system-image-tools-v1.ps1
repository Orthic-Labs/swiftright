$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
function Row([string]$P){$I=Get-Item -LiteralPath $P -Force;if($I.PSIsContainer -or $I.Length -gt 67108864 -or ($I.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'bounded regular input required'};[ordered]@{path=$I.FullName;bytes=$I.Length;sha256=(Get-FileHash -LiteralPath $P).Hash.ToLowerInvariant()}}
$VsWhere='C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
if(-not(Test-Path -LiteralPath $VsWhere)){throw 'vswhere unavailable'}
$Install=@(& $VsWhere -latest -products '*' -property installationPath)
if($Install.Count -ne 1 -or [string]::IsNullOrWhiteSpace($Install[0])){throw 'one VS installation required'}
$Root=$Install[0];$Versions=@(Get-ChildItem -LiteralPath (Join-Path $Root 'VC\Tools\MSVC') -Directory)
if($Versions.Count -lt 1 -or $Versions.Count -gt 16){throw 'bounded MSVC version inventory required'}
$Version=$Versions|Sort-Object {[version]$_.Name} -Descending|Select-Object -First 1
$Cl=Join-Path $Version.FullName 'bin\Hostx64\x64\cl.exe';$VcVars=Join-Path $Root 'VC\Auxiliary\Build\vcvars64.bat'
$Fonts=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$Matches=@($Fonts.PSObject.Properties|Where-Object{$_.Name -eq 'Segoe Fluent Icons (TrueType)'})
if($Matches.Count -ne 1){throw 'installed Segoe Fluent Icons registration unavailable'}
$Font=[string]$Matches[0].Value;if(-not[IO.Path]::IsPathRooted($Font)){$Font=Join-Path 'C:\Windows\Fonts' $Font}
$D=[ordered]@{kind='factory-system-image-measured-tool-inventory-v1';vswhere=(Row $VsWhere);compiler=(Row $Cl);vcvars64=(Row $VcVars);font=(Row $Font);fontRegistration=$Matches[0].Name;desktopLock=(Get-Content -LiteralPath 'D:\Claude\desktop.lock' -Raw).Trim();nativeActions=0;compilerActions=0;deletionActions=0}
$D|ConvertTo-Json -Depth 8
