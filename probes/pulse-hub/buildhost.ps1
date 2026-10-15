# Dell, headless, build only: the FactoryProbe capture host (release, native build system, same flags as factory/tools/pair/build.ps1).
param([Parameter(Mandatory)][string]$Work,[string]$Tag='host1',[string]$Config='release')
$tc='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin'
$env:Path="$tc;C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;"+$env:Path
$dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$ErrorActionPreference='Continue'
$scratch="$Work\scratch-host"
& "$tc\swift.exe" build --build-system native --package-path "$Work\pkg" --scratch-path $scratch --jobs 2 -Xswiftc -j2 -c $Config --product FactoryProbe -Xlinker /MANIFEST:EMBED -Xlinker $dep -Xlinker /OPT:NOICF -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup *> "$Work\$Tag.log"
"exit=$LASTEXITCODE exe=$(Test-Path "$scratch\x86_64-unknown-windows-msvc\$Config\FactoryProbe.exe")"
