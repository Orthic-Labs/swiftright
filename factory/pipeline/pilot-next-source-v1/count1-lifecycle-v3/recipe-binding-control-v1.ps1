param(
 [Parameter(Mandatory=$true)][string]$PlanPath,
 [Parameter(Mandatory=$true)][string]$SourceInputsPath,
 [Parameter(Mandatory=$true)][string]$RepositoryRoot
)
$ErrorActionPreference='Stop'
function Read-BoundedJson([string]$Path){
 $item=Get-Item -LiteralPath $Path -ErrorAction Stop
 if(-not $item.PSIsContainer -and $item.Length -le 2MB -and -not($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){
  return (Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json)
 }
 throw 'bounded regular JSON required'
}
function CanonicalRefHash([string]$Value){
 if($Value -notmatch '^(sha256:)?[0-9a-fA-F]{64}$'){throw 'recipe reference hash format'}
 return $Value.ToLowerInvariant().Replace('sha256:','')
}
function Assert-RecipeReference([object]$Plan,[object]$Source,[string]$Root){
 if($null -eq $Plan.recipeRef -or $null -eq $Source.recipeRef){throw 'plan/source recipeRef required'}
 foreach($ref in @($Plan.recipeRef,$Source.recipeRef)){
  if([string]::IsNullOrWhiteSpace([string]$ref.path) -or [string]::IsNullOrWhiteSpace([string]$ref.sha256) -or $ref.bytes -isnot [int] -and $ref.bytes -isnot [long]){throw 'recipeRef path/hash/bytes required'}
  if([int64]$ref.bytes -le 0 -or [int64]$ref.bytes -gt 2MB){throw 'recipeRef bytes bound'}
  [void](CanonicalRefHash ([string]$ref.sha256))
 }
 if([string]$Plan.recipeRef.path -cne [string]$Source.recipeRef.path -or [string]$Plan.recipeRef.sha256 -cne [string]$Source.recipeRef.sha256 -or [int64]$Plan.recipeRef.bytes -ne [int64]$Source.recipeRef.bytes){throw 'plan/source recipeRef mismatch'}
 $rootPath=[IO.Path]::GetFullPath($Root);$relative=[string]$Plan.recipeRef.path
 if([IO.Path]::IsPathRooted($relative)){throw 'recipeRef must be repository-relative'}
 $path=[IO.Path]::GetFullPath((Join-Path $rootPath $relative))
 if(-not $path.StartsWith($rootPath.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'recipeRef escapes repository'}
 $item=Get-Item -LiteralPath $path -ErrorAction Stop
 if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -ne [int64]$Plan.recipeRef.bytes){throw 'recipeRef file bytes/path drift'}
 if((Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -cne (CanonicalRefHash ([string]$Plan.recipeRef.sha256))){throw 'recipeRef content hash drift'}
}
$plan=Read-BoundedJson ([IO.Path]::GetFullPath($PlanPath));$source=Read-BoundedJson ([IO.Path]::GetFullPath($SourceInputsPath))
Assert-RecipeReference $plan $source ([IO.Path]::GetFullPath($RepositoryRoot))
Write-Output 'recipe-binding-pass'
