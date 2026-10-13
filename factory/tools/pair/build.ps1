# Build FactoryProbe from an already-extracted package dir. Exit code = swift exit code.
param([Parameter(Mandatory)][string]$Pkg)
$ErrorActionPreference='Stop'
$tc='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin'
$env:Path="$tc;C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;"+$env:Path
$dep="/MANIFESTDEPENDENCY:type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'"
$ErrorActionPreference='Continue'   # swift prints deprecation warnings on stderr
$scratch=Join-Path $Pkg 'scratch'
& "$tc\swift.exe" build --build-system native --package-path $Pkg --scratch-path $scratch --jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1 -c release -Xlinker /MANIFEST:EMBED -Xlinker $dep -Xlinker /SUBSYSTEM:WINDOWS -Xlinker /ENTRY:mainCRTStartup *> (Join-Path $Pkg 'build.log')
$code=$LASTEXITCODE
if($code -eq 0 -and -not (Test-Path (Join-Path $scratch 'x86_64-unknown-windows-msvc\release\FactoryProbe.exe'))){$code=99}
exit $code
