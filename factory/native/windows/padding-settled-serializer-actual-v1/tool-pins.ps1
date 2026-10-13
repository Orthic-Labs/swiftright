$ErrorActionPreference='Stop'
$compiler='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swiftc.exe'
$renderer='D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll'
@{compilerPath=$compiler;compilerSha256=(Get-FileHash -LiteralPath $compiler).Hash.ToLowerInvariant();compilerBytes=(Get-Item -LiteralPath $compiler).Length;rendererSha256=(Get-FileHash -LiteralPath $renderer).Hash.ToLowerInvariant();nativeActions=0;lockActions=0}|ConvertTo-Json
