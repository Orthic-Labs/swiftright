$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.factory-work\text-capture-foundation-v2.zip';$temp='D:\Claude\swiftright\.factory-work\hosts\text-baseline\capture-foundation-v2';$producer='D:\Claude\swiftright\factory\native\windows\.work\text-baseline-r11-v2\producer';$stageRoot='D:\Claude\swiftright\.factory-work\hosts\text-baseline'
if(@(Get-Process swift,swiftc,swift-build,clang -ErrorAction SilentlyContinue).Count){throw 'compiler busy'}
if((Get-FileHash $zip).Hash.ToLowerInvariant() -cne 'da0f08868dfbeb0c0900090828c2d1128e9d288568764fb51ded236de138a403' -or (Test-Path $temp) -or (Test-Path $producer)){throw 'fresh pinned foundation required'}
Expand-Archive -LiteralPath $zip -DestinationPath $temp;$m=Get-Content -Raw (Join-Path $temp 'stage-manifest.json')|ConvertFrom-Json
foreach($row in $m.files){$f=Join-Path $temp $row.path;if((Get-Item $f).Length -ne $row.bytes -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne $row.sha256){throw 'source stage drift'}}
New-Item -ItemType Directory $producer|Out-Null;Copy-Item -Path (Join-Path $temp 'producer\*') -Destination $producer -Recurse
foreach($row in @($m.files|Where-Object{$_.path.StartsWith('host/')})){$f=Join-Path $stageRoot $row.path.Substring(5);if(Test-Path $f){throw 'fresh supplement required'};New-Item -ItemType Directory ([IO.Path]::GetDirectoryName($f)) -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $temp $row.path) -Destination $f}
& (Join-Path $stageRoot 'preflight-capture-text-v2.ps1') -CompileReceiptSha256 'a5842fbea8266587cf4749ed2376fb18d42a19c8ee0996346cc503f9358feb8f' -ExeSha256 'bca8fe5528b7845bf6000b31c1f45006db0685c6e8d16db1b650945db1a7a5e5' -SerializerControlSha256 '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
