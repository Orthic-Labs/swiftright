param([Parameter(Mandatory = $true)][string]$InspectorPath)
$ErrorActionPreference = 'Stop'
$text = [IO.File]::ReadAllText([IO.Path]::GetFullPath($InspectorPath))
foreach ($needle in @('ReadAllBytes', 'MaxFileBytes', 'MaxTotalBytes', 'MaxFiles', 'transportJobRequired', 'recursiveJson', 'dateTimeConversion', 'CreateNew', 'File.Move')) {
    if (-not $text.Contains($needle)) { throw "inspector control needle missing: $needle" }
}
foreach ($forbidden in @('ConvertFrom-Json', 'ConvertTo-Json', 'Get-Content -Raw', 'Get-ChildItem')) {
    if ($text.Contains($forbidden)) { throw "unsafe receipt operation present: $forbidden" }
}
if (-not $text.Contains('InputPath')) { throw 'explicit input paths required' }
if (-not $text.Contains('output parent must already exist')) { throw 'output path must not create arbitrary tree' }
@{ kind = 'sr0-flat-receipt-inspector-controls-v1'; status = 'passed-source-controls'; nativeActions = 0; recursiveJson = $false; transportJobRequired = 'sr0-root-transport-job-v1' } | ConvertTo-Json -Compress
