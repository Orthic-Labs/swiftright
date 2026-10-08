# SR0-B frame-clock probe: builds SwiftHost.exe against the render probe payload (run on Windows).
# Payload layout: payload\bin\swiftright_render_probe.dll, payload\lib\swiftright_render_probe.lib, payload\include\*.h
# Same ComCtl v6 manifest link flags as gpui-drain (TaskDialogIndirect needs comctl32 v6).
param(
    [string]$Payload = 'D:\Claude\sr0b-frame-clock\payload',
    [string]$Scratch = 'D:\Claude\sr0b-frame-clock\scratch-1'
)
$ErrorActionPreference = 'Stop'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Set-Location 'D:\Claude\sr0b-frame-clock\SwiftHost'
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
& swift build -c release --scratch-path $Scratch "-Xcc" "-I$Payload\include" "-Xlinker" "-L$Payload\lib" "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" $dep
"swift build exit=$LASTEXITCODE"
