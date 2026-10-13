param(
    [Parameter(Mandatory)][string]$ProducerRoot,
    [Parameter(Mandatory)][string]$IntegrationBindingsPath,
    [Parameter(Mandatory)][string]$SourceInputsPath,
    [Parameter(Mandatory)][ValidateSet('text','circle')][string]$Profile,
    [Parameter(Mandatory)][string]$ExpectedBindingKind,
    [Parameter(Mandatory)][string]$ExpectedPathFragment,
    [Parameter(Mandatory)][string]$ExpectedMtaWorkerHash
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'assert-mta-profile-closure-v1.ps1')
$binding = Read-BoundedJson $IntegrationBindingsPath
$inputs = Read-BoundedJson $SourceInputsPath
$base = Assert-MtaProfileClosure -ProducerRoot $ProducerRoot -IntegrationBindingsPath $IntegrationBindingsPath -SourceInputsPath $SourceInputsPath -BindingDocument $binding -SourceInputs $inputs -Profile $Profile -ExpectedBindingKind $ExpectedBindingKind -ExpectedPathFragment $ExpectedPathFragment -ExpectedMtaWorkerHash $ExpectedMtaWorkerHash
if (-not $base.accepted) { throw 'positive closure did not admit' }

function Copy-Json($x) { return (ConvertFrom-Json (ConvertTo-Json $x -Depth 32)) }
function Expect-Reject([string]$Name, [scriptblock]$Action) {
    try { & $Action; throw "fault accepted: $Name" } catch {
        if ($_.Exception.Message -like "fault accepted: $Name") { throw }
    }
}
$cases = @(
    @{ name='mta-worker-hash'; mutate={ param($b,$i) ($b.files | Where-Object path -ceq 'dependencies/uia-worker/invoke-worker-mta.ps1').sha256 = ('0' * 64) } },
    @{ name='row-sha'; mutate={ param($b,$i) $b.files[0].sha256 = ('1' * 64) } },
    @{ name='row-bytes'; mutate={ param($b,$i) $b.files[0].bytes = [int64]$b.files[0].bytes + 1 } },
    @{ name='duplicate-row'; mutate={ param($b,$i) $b.files = @($b.files) + $b.files[0] } },
    @{ name='unsafe-row'; mutate={ param($b,$i) $b.files[0].path = '../escape.ps1' } },
    @{ name='binding-hash'; mutate={ param($b,$i) $i.integrationBindingsHash = ('2' * 64) } },
    @{ name='binding-ref'; mutate={ param($b,$i) $i.integrationBindingsRef.sha256 = 'sha256:' + ('3' * 64) } },
    @{ name='profile-path'; mutate={ param($b,$i) $i.capturePlanPath = 'D:\wrong\profile\capture-plan.json' } },
    @{ name='cross-profile-path'; mutate={ param($b,$i) $i.capturePlanPath = 'D:\circle-r11\capture-plan.json' } },
    @{ name='tag-r10-substring'; mutate={ param($b,$i) $i.capturePlanPath = 'D:\text-paint-r100\capture-plan.json' } },
    @{ name='missing-mta-row'; mutate={ param($b,$i) $b.files = @($b.files | Where-Object path -cne 'dependencies/uia-worker/invoke-worker-mta.ps1') } },
    @{ name='kind'; mutate={ param($b,$i) $b.kind = 'root-rectangle-helper-bindings-v1' } }
)
foreach ($case in $cases) {
    $b = Copy-Json $binding; $i = Copy-Json $inputs; & $case.mutate $b $i
    Expect-Reject $case.name { Assert-MtaProfileClosure -ProducerRoot $ProducerRoot -IntegrationBindingsPath $IntegrationBindingsPath -SourceInputsPath $SourceInputsPath -BindingDocument $b -SourceInputs $i -Profile $Profile -ExpectedBindingKind $ExpectedBindingKind -ExpectedPathFragment $ExpectedPathFragment -ExpectedMtaWorkerHash $ExpectedMtaWorkerHash | Out-Null }
}
[pscustomobject]@{ status='SOURCE_CONTROLS_PASS'; positive=$base; rejectedFaults=$cases.Count; nativeActions=0; remoteActions=0 }
