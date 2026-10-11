$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$managed='D:\.rightkit-managed\remote-workspaces\swiftright-render-815231d1\slot1'
$target='D:\.rightkit-managed\rightkit-build-control\ws\864173e69427\g\002\t'
$dest='D:\Claude\swiftright\.work\sr0-stage-inputs'
$rows=@'
[{"path": "Cargo.toml", "bytes": 908, "sha256": "0258ef747fca4ec75544f09266f1e122dbfabac0fdbe9b49389066688246df7a"}, {"path": "README.md", "bytes": 3021, "sha256": "dca12487b10b46f0e84903e25f165b58b855695d29da2e729fcc4ea3244823f4"}, {"path": "src/abi.rs", "bytes": 14996, "sha256": "d6a18eea18cf2b6c0baba05d5d8e02b0de873268e1bea41ca0783105d7f53c3f"}, {"path": "src/ax.rs", "bytes": 10873, "sha256": "d75f0d047b87e30f835703cafae4630831b6f285ef63d8b4fc2ac2d532a850f9"}, {"path": "src/lib.rs", "bytes": 22028, "sha256": "2194c421d1e309a5199a9e1b6280d7d88c38fadf67dbd491778cae0b147172e2"}, {"path": "src/pace.rs", "bytes": 12660, "sha256": "f8fbc916a3be659935dd007b10eda32fd087a14476599b4a54e2a5667751ef26"}, {"path": "src/rt.rs", "bytes": 16903, "sha256": "9bae2f321f76af221e80b0cdabd3f5a172014f736628401095c07ef2cd5a3e13"}, {"path": "src/text.rs", "bytes": 13103, "sha256": "a5c7aa71b587700504b062b5a23e6df44938e486b5ebe64f2ff76955904c3bc4"}, {"path": "src/trace.rs", "bytes": 12493, "sha256": "881408dca3287ceffd83e361af0665aba61988d4a65ad776d25770aab79cbe53"}, {"path": "src/tree.rs", "bytes": 37564, "sha256": "f7964b864e825f9708c8899ba45ea4727c65ea1b88c668d7d8192d3f2764d095"}, {"path": "src/view.rs", "bytes": 70088, "sha256": "bcc373ff84ad8a51e5ec2d16ccdd21b499482b303f2977ef882a1d70909562bf"}]
'@|ConvertFrom-Json
foreach($r in $rows){$f=Join-Path $managed ($r.path -replace '/','\');if((Get-Item -LiteralPath $f).Length -ne $r.bytes -or (Get-FileHash -LiteralPath $f).Hash.ToLowerInvariant() -cne $r.sha256){throw ('Managed source drift '+$r.path)}}
$lock=Join-Path $managed 'Cargo.lock'
if((Get-Item -LiteralPath $lock).Length -ne 181537 -or (Get-FileHash -LiteralPath $lock).Hash.ToLowerInvariant() -cne '0e28d8bbbb13208c1951341741ec28a66b9c9e74a351708070207d973c478c9c'){throw 'Actual resolved Cargo.lock drift'}
$dll=Join-Path $target 'x86_64-pc-windows-msvc\release\swiftright_render.dll'
if(-not(Test-Path -LiteralPath $dll -PathType Leaf)){throw 'Managed DLL absent'}
[IO.Directory]::CreateDirectory($dest)|Out-Null
foreach($f in @($dll,$lock)){$d=Join-Path $dest ([IO.Path]::GetFileName($f));if(Test-Path -LiteralPath $d){throw ('Immutable staged destination exists '+$d)};[IO.File]::Copy($f,$d,$false)}
$refs=@();foreach($f in @('swiftright_render.dll','Cargo.lock')){$d=Join-Path $dest $f;$refs+=[ordered]@{path=$d;bytes=(Get-Item -LiteralPath $d).Length;sha256=(Get-FileHash -LiteralPath $d).Hash.ToLowerInvariant()}}
[ordered]@{kind='sr0-recovered-renderer-managed-artifact-v1';requestID='rr-1791721085329-353f80ea918740ef';brokerID='4f6ad8cd-0eaa-49af-a7bd-4ea220014e96';rendererSourceCommit='4b1ca6d0fb89963ee20cd5bd7adf8b7c8b9b24e2';nonLockSourceFilesVerified=$rows.Count;resolvedLockChanged=$true;files=$refs;nativeLaunches=0;lockActions=0;at=[DateTimeOffset]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 8
