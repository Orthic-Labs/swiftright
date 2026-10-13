$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$Exe='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe'
if((Get-FileHash -LiteralPath $Exe).Hash.ToLowerInvariant() -cne '1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'){throw 'compiler drift'}
& $Exe build --help
if($LASTEXITCODE -ne 0){throw 'help failed'}
