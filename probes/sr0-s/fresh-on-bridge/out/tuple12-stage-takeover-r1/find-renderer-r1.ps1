$ErrorActionPreference='Stop'
$expected='C62B554B4B2545B8BE2429C2530E17B8C8B78DF97E67172B627E8CD18A5FE68F'
$roots=@(
 'D:\.rightkit-managed\rightkit-build-control\ws\864173e69427',
 'D:\.rightkit-managed\remote-workspaces\swiftright-render-815231d1',
 'D:\Claude\swiftright\.work\sr0-r12',
 'D:\Claude\swiftright\.work\sr0-stage-tools',
 'D:\Claude\swiftright\render\target',
 'D:\Claude\swiftright\.factory-work\hosts'
)
$facts=@();$matches=@()
foreach($root in $roots){
 $present=Test-Path -LiteralPath $root -PathType Container
 $facts += [ordered]@{path=$root;exists=$present}
 if($present){
   $files=@(Get-ChildItem -LiteralPath $root -Filter 'swiftright_render.dll' -File -Recurse -ErrorAction Stop)
   foreach($file in $files){$hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash;$matches += [ordered]@{path=$file.FullName;bytes=$file.Length;sha256=$hash;expectedMatch=($hash -ceq $expected)}}
 }
}
[ordered]@{kind='sr0-read-only-renderer-location-audit-v1';observedAt=[DateTime]::UtcNow.ToString('o');roots=$facts;candidates=$matches;mutations=0;builds=0;nativeWindows=0}|ConvertTo-Json -Depth 8
