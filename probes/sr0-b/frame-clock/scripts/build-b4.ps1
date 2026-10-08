# Batch-4 SwiftHost build. Run ON the Windows host as a file (powershell -File) so the
# manifest-dependency quotes survive; inline commands over SSH strip them.
$ErrorActionPreference = 'Stop'
$root = 'D:\Claude\sr0b-frame-clock\b4'
$payload = "$root\payload"; $scratch = "$root\scratch-b4m"
$env:Path = 'C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Set-Location "$root\SwiftHost"
$dep = "/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
& swift build -c release --scratch-path $scratch "-Xcc" "-I$payload\include" "-Xlinker" "-L$payload\lib" "-Xlinker" "/MANIFEST:EMBED" "-Xlinker" $dep
"swift build exit=$LASTEXITCODE"
$bin = "$scratch\out\Products\Release-windows-x86_64"
Copy-Item "$payload\bin\*.dll" $bin -Force
$mt = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\mt.exe' | Sort-Object FullName | Select-Object -Last 1
& $mt.FullName -nologo "-inputresource:$bin\SwiftHost.exe;#1" "-out:$bin\SwiftHost.manifest.txt" | Out-Null
"manifest:"; Get-Content "$bin\SwiftHost.manifest.txt" | Select-String 'assemblyIdentity'
