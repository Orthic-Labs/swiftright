# Dell, headless, build only. usage: run.ps1 -Work <new dir under D:\Claude\swiftright\.work> -Targets RightKitEngine,RightKitHub -Tag pass1
# <Work>\pkg holds the assembled package (assemble.sh); logs go to <Work>\<Tag>-<Target>.log
param([Parameter(Mandatory)][string]$Work,[string[]]$Targets=@('RightKitEngine','RightKitHub'),[string]$Tag='pass1',[string]$Stage='D:\Claude\swiftright\.factory-work\product-stage\8bf89d2dc-aa6cd909')
$tc='C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin'
$env:Path="$tc;C:\Users\adrds\AppData\Local\Programs\Swift\Runtimes\6.4.0\usr\bin;"+$env:Path
$pm="$Work\pkg\Package.swift"
if((Get-Content $pm -Raw) -match '@@PRODUCT_STAGE@@'){(Get-Content $pm -Raw).Replace('@@PRODUCT_STAGE@@',$Stage.Replace('\','\\')) | Set-Content $pm -NoNewline}
$ErrorActionPreference='Continue'
foreach($t in $Targets){
  $log="$Work\$Tag-$t.log"
  & "$tc\swift.exe" build --package-path "$Work\pkg" --scratch-path "$Work\scratch" --jobs 4 --target $t *> $log
  "$t exit=$LASTEXITCODE errors=$((Select-String -Path $log -Pattern ': error:' | Measure-Object).Count)"
}
