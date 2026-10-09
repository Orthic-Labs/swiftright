# Builds the "new" (0.1.1) tree for the R2/R5 old/new MSIX pair inside a CLONE (never the primary checkout): bumps the version
# fields and makes one Swift-only change (a diagnostic string in WindowsBootstrap.swift), exactly the R2 recipe
# (RESULT-R2.md: version fields + one Swift diagnostic string). Run from the clone, then commit the result clone-locally
# (the source gate needs a clean tree).
#   bump-version-win.ps1 -AppDir D:\Claude\sr0-r5\clean2\examples\SliceApp [-From 0.1.0] [-To 0.1.1]
param([Parameter(Mandatory)][string]$AppDir, [string]$From = '0.1.0', [string]$To = '0.1.1')
$ErrorActionPreference = 'Stop'
$enc = New-Object Text.UTF8Encoding($false)
function Edit([string]$rel, [string]$find, [string]$repl) {
    $p = Join-Path $AppDir $rel
    $t = [IO.File]::ReadAllText($p)
    if (-not $t.Contains($find)) { throw "$rel does not contain: $find" }
    [IO.File]::WriteAllText($p, $t.Replace($find, $repl), $enc)
}
Edit 'package.json' ('"version": "' + $From + '"') ('"version": "' + $To + '"')
Edit 'swift-package.json' ('"version": "' + $From + '"') ('"version": "' + $To + '"')
Edit 'swift-package.json' ('"msixVersion": "' + $From + '.0"') ('"msixVersion": "' + $To + '.0"')
Edit 'right-release.config.mjs' ('const VERSION = "' + $From + '";') ('const VERSION = "' + $To + '";')
Edit 'right-release.config.mjs' ('const MSIX_VERSION = "' + $From + '.0";') ('const MSIX_VERSION = "' + $To + '.0";')
Edit 'Windows\SliceApp.manifest' ('name="Orthic.SliceApp" version="' + $From + '.0"') ('name="Orthic.SliceApp" version="' + $To + '.0"')
Edit 'Sources\SliceApp\Windows\WindowsBootstrap.swift' 'print("SLICE_RUN_ERROR: \(error)")' ('print("SLICE_RUN_ERROR (' + $To + '): \(error)")')
"bumped $From -> $To in $AppDir"
