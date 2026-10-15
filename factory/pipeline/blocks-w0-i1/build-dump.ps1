# Builds the I1 console decode-dump host (ImageDump) from an extracted package dir on the Dell. Exit code = swift exit code. (The FactoryProbe build.ps1 links /SUBSYSTEM:WINDOWS; this one is a console exe.)
param([Parameter(Mandatory)][string]$Pkg)
$ErrorActionPreference='Stop'
$tc='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin'
$env:Path="$tc;C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;"+$env:Path
$ErrorActionPreference='Continue'
$scratch=Join-Path $Pkg 'scratch'
& "$tc\swift.exe" build --build-system native --package-path $Pkg --scratch-path $scratch --jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1 -c release *> (Join-Path $Pkg 'build.log')
$code=$LASTEXITCODE
if($code -eq 0 -and -not (Test-Path (Join-Path $scratch 'x86_64-unknown-windows-msvc\release\ImageDump.exe'))){$code=99}
exit $code
