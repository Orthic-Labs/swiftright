# Dell, headless. Type-checks every file of one probe module in ONE frontend run (all errors of all files in the log), and emits a
# partial .swiftmodule (-experimental-allow-module-with-compiler-errors) so dependent modules can be checked past the errors.
# usage: tc.ps1 -Work <dir with pkg\ and scratch\ from run.ps1> -Module RightKitHub -Tag tc1 [-Skip file1.swift,file2.swift]
param([Parameter(Mandatory)][string]$Work,[Parameter(Mandatory)][string]$Module,[string]$Tag='tc1',[string[]]$Skip=@(),[string]$Swift='5',[string]$ModsDir='mods')
$tc='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin'
$env:Path="$tc;C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;"+$env:Path
$prod="$Work\scratch\out\Products\Debug-windows-x86_64"
$mods="$Work\$ModsDir"; New-Item -ItemType Directory -Force $mods | Out-Null
$files=Get-ChildItem "$Work\pkg\Sources\$Module" -Recurse -Filter *.swift | Where-Object { $Skip -notcontains $_.Name } | % FullName
$a=@('-emit-module','-emit-module-path',"$mods\$Module.swiftmodule",'-module-name',$Module,'-swift-version',$Swift,'-parse-as-library','-wmo','-Xfrontend','-experimental-allow-module-with-compiler-errors','-Xfrontend','-continue-building-after-errors','-I',$mods,'-I',$prod,'-Xcc','-I','-Xcc',"$Work\pkg\Sources\CRightKitEngine\include",'-Xcc',"-fmodule-map-file=$Work\scratch\out\Intermediates.noindex\GeneratedModuleMaps-windows-x86_64\CRightKitEngine.modulemap")+$files
$ErrorActionPreference='Continue'
& "$tc\swiftc.exe" @a *> "$Work\$Tag-$Module.log"
"$Module exit=$LASTEXITCODE errors=$((Select-String -Path "$Work\$Tag-$Module.log" -Pattern ': error:' | Measure-Object).Count)"
