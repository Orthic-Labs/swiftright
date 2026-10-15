# Dell, headless. Rebuilds the shim module (stubs) and type-checks the four probe modules in order. usage: iter.ps1 -Work <dir> -Tag <name>
param([Parameter(Mandatory)][string]$Work,[Parameter(Mandatory)][string]$Tag,[string]$Swift='5',[string]$ModsDir='mods')
$tc='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin'
$env:Path="$tc;C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;"+$env:Path
$prod="$Work\scratch\out\Products\Debug-windows-x86_64"; $mods="$Work\$ModsDir"; New-Item -ItemType Directory -Force $mods | Out-Null
$ErrorActionPreference='Continue'
$sh=Get-ChildItem "$Work\pkg\Sources\SwiftUI" -Filter *.swift | % FullName
& "$tc\swiftc.exe" -emit-module -emit-module-path "$mods\SwiftUI.swiftmodule" -module-name SwiftUI -swift-version $Swift -parse-as-library -wmo -I $prod @sh *> "$Work\$Tag-SwiftUI.log"
"SwiftUI shim exit=$LASTEXITCODE errors=$((Select-String -Path "$Work\$Tag-SwiftUI.log" -Pattern ': error:' | Measure-Object).Count)"
foreach($m in 'RightKitHub','RightKitHubQA','PulseHub','PulseHubFixtures'){ & "$Work\tc.ps1" -Work $Work -Module $m -Tag $Tag -Swift $Swift -ModsDir $ModsDir }
