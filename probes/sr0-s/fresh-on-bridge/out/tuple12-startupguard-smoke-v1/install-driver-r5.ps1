$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.work\sr0-stage-inputs\startupguard-driver5-source.zip';$stage='D:\Claude\swiftright\.work\sr0-stage-inputs\startupguard-driver5-source';$dst='D:\Claude\swiftright\.work\sr0-matrix-controls-v1\drive-fixture-noactivate-focus-r5.ps1'
if((Get-FileHash -LiteralPath $zip).Hash.ToLowerInvariant() -cne '62180a350cd2f72e0732ddb62016b4fb1e9505bb2702b219b86ec3b0fb12bae1' -or (Test-Path -LiteralPath $stage) -or (Test-Path -LiteralPath $dst)){throw 'exclusive driver5 stage drift'}
Expand-Archive -LiteralPath $zip -DestinationPath $stage;$src=Join-Path $stage 'drive-fixture-noactivate-focus-r5.ps1'
if((Get-FileHash -LiteralPath $src).Hash.ToLowerInvariant() -cne '5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4' -or (Get-Item -LiteralPath $src).Length -ne 28994){throw 'driver5 member drift'}
$tokens=$null;$errors=$null;[System.Management.Automation.Language.Parser]::ParseFile($src,[ref]$tokens,[ref]$errors)|Out-Null;if($errors.Count){throw 'driver5 actualWindowsparsefailed'}
[IO.File]::Copy($src,$dst,$false);@{status='PASS_EXACT_DRIVER5_WINDOWS_PARSER';path=$dst;sha256='5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4';bytes=28994;nativeActions=0}|ConvertTo-Json
