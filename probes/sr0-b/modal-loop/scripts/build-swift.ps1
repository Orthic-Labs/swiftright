# Builds SwiftHost with the ComCtl v6 manifest dependency embedded (see gpui-drain RESULT.md, finding 1).
$ErrorActionPreference = 'Stop'
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$sw = 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe'
$p = 'D:\Claude\sr0b-modal-loop\payload'
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
Set-Location D:\Claude\sr0b-modal-loop\SwiftHost
& $sw build -c release --scratch-path D:\Claude\sr0b-modal-loop\scratch-1 "-Xcc" "-I$p\include" "-Xlinker" "/LIBPATH:$p\lib" "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" $dep 2>&1 | Select-Object -Last 15
$out = 'D:\Claude\sr0b-modal-loop\scratch-1\out\Products\Release-windows-x86_64'
Copy-Item "$p\bin\swiftright_render_probe.dll" $out -Force
"exe_exists=$(Test-Path "$out\SwiftHost.exe")"
