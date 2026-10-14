# Windows: build each probe target against the staged SwiftRight runtime, headless. Never delete; output goes to $Work.
# usage: run.ps1 -Stage <product-stage dir> -Work <new empty dir under D:\Claude\swiftright\.work> -Src <this dir>
param([Parameter(Mandatory)][string]$Stage,[Parameter(Mandatory)][string]$Work,[Parameter(Mandatory)][string]$Src)
$tc='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin'
$env:Path="$tc;C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;"+$env:Path
New-Item -ItemType Directory -Force "$Work\pkg" | Out-Null
Copy-Item -Recurse -Force "$Src\Sources" "$Work\pkg\Sources"
(Get-Content "$Src\Package.swift" -Raw).Replace('@@PRODUCT_STAGE@@', $Stage.Replace('\','\\')) | Set-Content "$Work\pkg\Package.swift" -NoNewline
$ErrorActionPreference='Continue'
$res=@()
foreach($t in (Get-Content "$Src\targets.txt")){
  $log="$Work\$t.log"
  & "$tc\swift.exe" build --package-path "$Work\pkg" --scratch-path "$Work\scratch" --target $t *> $log
  $ok=($LASTEXITCODE -eq 0)
  $first=(Select-String -Path $log -Pattern 'error:' | Where-Object { $_.Line -notmatch 'SwiftCompile|Build failed' } | Select-Object -First 1).Line
  $res += "$t $(if($ok){'OK'}else{'FAIL'}) $first"
}
$res | Set-Content "$Work\results.txt"
