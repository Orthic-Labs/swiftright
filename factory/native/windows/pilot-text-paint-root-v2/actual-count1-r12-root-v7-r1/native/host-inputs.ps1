# Shared production guard: exact compiler membership plus raw hashes, no process/window calls.
function Assert-HostCompilerInputs([string]$PackagePath,$Bindings) {
 $package=[IO.Path]::GetFullPath($PackagePath)
 $actual=@((Join-Path $package 'Package.swift'))+@(Get-ChildItem -LiteralPath (Join-Path $package 'Sources') -Recurse -File|ForEach-Object{$_.FullName})
 $expected=@($Bindings|Where-Object{$_.path -eq 'Package.swift' -or $_.path.Replace('\','/').StartsWith('Sources/',[StringComparison]::Ordinal)}|ForEach-Object{[IO.Path]::GetFullPath((Join-Path $package $_.path))})
 if($actual.Count -ne $expected.Count -or @($actual|Where-Object{$expected -notcontains $_}).Count -ne 0){throw 'Host compiler input membership drift'}
 foreach($binding in $Bindings){
  $file=[IO.Path]::GetFullPath((Join-Path $package $binding.path))
  if(-not $file.StartsWith($package+'\',[StringComparison]::OrdinalIgnoreCase) -or (Get-FileHash -LiteralPath $file).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:','')){throw 'Host source drift'}
 }
}
