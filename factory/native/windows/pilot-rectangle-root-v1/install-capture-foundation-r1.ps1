$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$zip='D:\Claude\swiftright\.factory-work\rectangle-capture-foundation-r1.zip';$temp='D:\Claude\swiftright\.factory-work\hosts\rectangle\capture-foundation-r1';$producer='D:\Claude\swiftright\factory\native\windows\.work\rectangle-r11\producer';$host='D:\Claude\swiftright\.factory-work\hosts\rectangle'
if((Get-FileHash $zip).Hash.ToLowerInvariant() -cne '7108de78cbd9b9878dda6d57d0dd7a318629dc6428760bce54bbfcd9c286cf6c' -or (Test-Path $temp) -or (Test-Path $producer)){throw 'fresh exact source stage required'}
Expand-Archive -LiteralPath $zip -DestinationPath $temp
$m=Get-Content -Raw (Join-Path $temp 'stage-manifest.json')|ConvertFrom-Json
foreach($row in $m.files){$f=Join-Path $temp $row.path;$i=Get-Item $f;if($i.Length -ne $row.bytes -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or (Get-FileHash $f).Hash.ToLowerInvariant() -cne $row.sha256){throw 'source stage drift'}}
New-Item -ItemType Directory $producer|Out-Null
Copy-Item -Path (Join-Path $temp 'producer\*') -Destination $producer -Recurse
foreach($row in @($m.files|Where-Object{$_.path.StartsWith('host/')})){$f=Join-Path $host $row.path.Substring(5);if(Test-Path $f){throw 'fresh host supplement required'};New-Item -ItemType Directory ([IO.Path]::GetDirectoryName($f)) -Force|Out-Null;Copy-Item -LiteralPath (Join-Path $temp $row.path) -Destination $f}
$pre=Join-Path $host 'preflight-capture-r1.ps1';$tokens=$null;$errors=$null;[void][Management.Automation.Language.Parser]::ParseFile($pre,[ref]$tokens,[ref]$errors);if($errors.Count){throw ($errors|Out-String)}
& $pre -CompileReceiptSha256 '5c6e63f04155f9996a438d05ae42e6080403e3c7069363cdd234be35f7db0228' -ExeSha256 '62aa7d5b9a5b9001d697822d26b2d102d8934de1de4a02103f810e756f71af66' -SerializerControlSha256 '952c75251160871870cb6d5f4a3af9d4ba2b8d204fbca40aa7fc437655af1bba'
