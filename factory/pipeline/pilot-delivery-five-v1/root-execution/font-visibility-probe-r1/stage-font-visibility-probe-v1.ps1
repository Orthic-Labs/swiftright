# Root-run bounded source staging for DirectWrite registration visibility probe.
[CmdletBinding()]
param(
    [string]$Repo = 'D:\Claude\swiftright',
    [string]$Package = 'D:\Claude\swiftright\factory\pipeline\pilot-delivery-five-v1\root-execution\font-visibility-probe-r1',
    [string]$InputRoot = 'D:\Claude\swiftright\.factory-work\root-tools\font-visibility-probe-r1'
)
$ErrorActionPreference = 'Stop'
if ([IO.Path]::GetFullPath($Repo) -cne 'D:\Claude\swiftright') { throw 'canonical repository path required' }
if ([IO.Path]::GetFullPath($Package) -cne (Join-Path $Repo 'factory\pipeline\pilot-delivery-five-v1\root-execution\font-visibility-probe-r1')) { throw 'canonical packet path required' }
function H([string]$Path, [Int64]$Cap) {
    $i = Get-Item -LiteralPath $Path -Force
    if ($i.PSIsContainer -or ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $i.Length -gt $Cap) { throw "bounded regular file required: $Path" }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
$rows = @(
    @{name='FontCollectionVisibilityProbe.cpp'; sha='ffe9c95e4aa4da0523861fb49601438fb0253b454376b57876641b6a44a0aa4f'; cap=16777216},
    @{name='ProviderOwnedJobProcess.cs'; sha='0ed9cec5f361faa1f8a7cf7308435f2ffb0c01232e1e0532825d65b9a24fab86'; cap=16777216},
    @{name='Tinos-Regular.ttf'; sha='60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61'; cap=67108864}
)
if (Test-Path -LiteralPath $InputRoot) { throw 'fresh probe input directory required' }
New-Item -ItemType Directory -Path $InputRoot | Out-Null
foreach ($row in $rows) {
    $source = Join-Path $Package $row.name
    if ((H $source $row.cap) -cne $row.sha) { throw "source hash mismatch: $($row.name)" }
    $dest = Join-Path $InputRoot $row.name
    Copy-Item -LiteralPath $source -Destination $dest
    if ((H $dest $row.cap) -cne $row.sha) { throw "staged hash mismatch: $($row.name)" }
}
[ordered]@{kind='factory-font-visibility-probe-stage-v1';input=$InputRoot;sourceCount=$rows.Count;sourceSha256=@($rows | ForEach-Object { [ordered]@{name=$_.name;sha256=('sha256:' + $_.sha)} });nativeActions=0;status='staged'} | ConvertTo-Json -Depth 8
