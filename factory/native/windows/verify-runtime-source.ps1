# Verify complete frozen runtime source tree, never mutate dependency/stage.
function Assert-FactoryRuntimeSource($Plan,[string]$PackagePath) {
 $root=[IO.Path]::GetFullPath($Plan.runtimePackagePath)
 if($root -notmatch '^D:\\Claude\\factory-swiftright-[A-Za-z0-9_-]+\\'){throw 'Runtime outside owned new root'}
 $tree=Join-Path $PackagePath 'runtime-source-tree.json'
 if((Get-FileHash -LiteralPath $tree).Hash.ToLowerInvariant() -ne $Plan.runtimeSourceTreeHash.Replace('sha256:','')){throw 'Runtime source tree receipt drift'}
 $bindings=(Get-Content -Raw $tree|ConvertFrom-Json);$bound=@()
 foreach($b in $bindings){
  $path=[IO.Path]::GetFullPath((Join-Path $root $b.path))
  if(-not $path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Runtime binding escape'}
  if((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -ne $b.sha256.Replace('sha256:','')){throw 'Runtime source bytes drift'}
  $bound += $path.ToLowerInvariant()
 }
 $actual=@((Join-Path $root 'Package.swift'))+@(Get-ChildItem -LiteralPath (Join-Path $root 'Sources') -Recurse -File|ForEach-Object{$_.FullName})
 if(@($actual|Where-Object{$bound -notcontains $_.ToLowerInvariant()}).Count -ne 0 -or $actual.Count -ne $bound.Count){throw 'Runtime source manifest incomplete'}
}
