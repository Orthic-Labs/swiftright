# Source-only identity join for current 37429120 custom Layout host.
$ErrorActionPreference='Stop'
$CustomPlanHash='766a4c57988bd1a2a9dae0ae5f951bfd77e3404309e89eac53b3ed70d72c2e97'
$CustomPackagePath='D:\Claude\swiftright\.factory-work\hosts\custom-layout-lifecycle\package'
$CustomRendererHash='e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93'
$CustomRuntimeCommit='37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b'
$CustomRuntimeTreeHash='c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e'
$CustomCompilerHash='1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a'
$CustomWitnessHash='7b87f5dbfb5d248ba035747e81b8376bdc559ab57ddfa3caaaf31f23437d6b25'
$CustomManifestHash='aec6842e2c6de7b918d76117b23a4e94671c4b9add146b6c72290f45229fe090'
$CustomRuntimeAPI=@{
 'Sources\SwiftRightRuntime\Layout.swift'='229baee2f56f649ab93de9800119a86da4e5d03cd41a2227c60309e1131cb990'
 'Sources\SwiftRightRuntime\LayoutEngine.swift'='1322f549d76a5902a185cfd880f3e8c6d5f074785420ae9629d0f088bd69fa98'
 'Sources\SwiftRightRuntime\Graph.swift'='c81543a78ab0516df42a22947ae9f66a1d2635e961d0a5c0706a48924ad1f91f'
 'Sources\SwiftRightRuntime\Geometry.swift'='acc003c678fd38f9a89a3af299e1450be19561e0935731f9961afbbedf585b6e'
}
function Assert-CustomLayoutSource([string]$Package) {
 $packagePath=[IO.Path]::GetFullPath($Package)
 if($packagePath -cne $CustomPackagePath){throw 'Exact canonical custom Layout package required'}
 $planPath=Join-Path $packagePath 'plan.json'
 if((Get-FileHash -LiteralPath $planPath).Hash.ToLowerInvariant() -cne $CustomPlanHash){throw 'Custom Layout plan drift'}
 $plan=Get-Content -Raw -LiteralPath $planPath|ConvertFrom-Json
 if($plan.kind -cne 'windows-custom-layout-lifecycle-source-plan' -or $plan.diagnosticScope -cne 'factory-custom-layout-host-lifecycle-v1' -or $plan.executionEligible -ne $false -or $plan.nativeParity -cne 'hold' -or $plan.frozenTupleBound -ne $false){throw 'Custom Layout source plan identity/scope drift'}
 if($plan.case.id -cne 'swiftui.custom-layout.recipe/case/b30ed0b185e8cb29' -or $plan.sourceHash -ne ('sha256:'+$CustomWitnessHash) -or $plan.manifestHash -ne ('sha256:'+$CustomManifestHash) -or $plan.rendererSha256 -ne $CustomRendererHash){throw 'Custom Layout case/source/renderer join drift'}
 if($plan.runtimeSourceCommit -cne $CustomRuntimeCommit -or $plan.runtimeSourceTreeHash -ne ('sha256:'+$CustomRuntimeTreeHash) -or $plan.compilerHash -ne $CustomCompilerHash){throw 'Custom Layout runtime/compiler lineage drift'}
 if($plan.compileRequest.packagePath -cne $CustomPackagePath){throw 'Compiled host package path differs from canonical custom source inputs'}
 foreach($binding in @($plan.sourceBindings)){
  $sourceInput=[IO.Path]::GetFullPath((Join-Path $packagePath $binding.path))
  if(-not $sourceInput.StartsWith($packagePath+'\',[StringComparison]::OrdinalIgnoreCase)){throw ('Source binding escapes package: '+$binding.path)}
  if((Get-FileHash -LiteralPath $sourceInput).Hash.ToLowerInvariant() -ne $binding.sha256.Replace('sha256:','')){throw ('Custom Layout source binding drift: '+$binding.path)}
 }
 foreach($proof in @('runtime-source-receipt.json','runtime-source-tree.json')){
  $proofPath=Join-Path $packagePath $proof
  if(-not(Test-Path -LiteralPath $proofPath -PathType Leaf)){throw ('Runtime source proof missing: '+$proof)}
 }
 if((Get-FileHash (Join-Path $packagePath 'runtime-source-receipt.json')).Hash.ToLowerInvariant() -ne $plan.runtimeSourceReceiptHash.Replace('sha256:','')){throw 'Runtime source receipt drift'}
 if((Get-FileHash (Join-Path $packagePath 'runtime-source-tree.json')).Hash.ToLowerInvariant() -ne $plan.runtimeSourceTreeFileHash.Replace('sha256:','')){throw 'Runtime source tree proof drift'}
 $runtime=[IO.Path]::GetFullPath($plan.runtimePackagePath)
 if(-not $runtime.StartsWith('D:\Claude\swiftright\.factory-work\runtime-stage\runtime',[StringComparison]::OrdinalIgnoreCase)){throw 'Runtime path is not current staged 374 source'}
 foreach($entry in $plan.currentRuntimeLayoutAPI.files){
  $apiPath=[IO.Path]::GetFullPath((Join-Path $runtime ($entry.path -replace '/','\')))
  if(-not $apiPath.StartsWith($runtime+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Runtime API path escapes staged runtime'}
  if((Get-FileHash -LiteralPath $apiPath).Hash.ToLowerInvariant() -ne $entry.sha256.Replace('sha256:','')){throw ('Current runtime API drift: '+$entry.path)}
 }
 $witness=Get-Content -Raw (Join-Path $packagePath 'Sources\FactoryProbe\Witness.swift')
 foreach($token in @('LayoutSize','LayoutRect','LayoutPoint','sizeThatFits(proposal: ProposedViewSize','subview.place(at: LayoutPoint')){if($witness -notmatch [regex]::Escape($token)){throw ('Current custom Layout witness token missing: '+$token)}}
 if($witness -match 'func sizeThatFits\([^\n]*\) -> CGSize' -or $witness -match 'func placeSubviews\(in bounds: CGRect'){throw 'Older CGRect/CGSize witness path present'}
 $main=Get-Content -Raw (Join-Path $packagePath 'Sources\FactoryProbe\main.swift')
 foreach($marker in @('window-closed-enter','graph-teardown-return','measure-release-return','shutdown-complete-return','unhook-enter','unhook-return','bridge-run-enter','bridge-run-return','case "Layout"','FACTORY_CUSTOM_LAYOUT_NODE')){if($main -notmatch [regex]::Escape($marker)){throw ('Lifecycle/custom host marker missing: '+$marker)}}
 [ordered]@{planHash=$CustomPlanHash;manifestHash=$CustomManifestHash;sourceHash=$CustomWitnessHash;runtimeCommit=$CustomRuntimeCommit;runtimeTreeHash=$CustomRuntimeTreeHash;rendererHash=$CustomRendererHash;caseID=$plan.case.id;diagnosticScope=$plan.diagnosticScope;nativeParity='hold';frozenTupleBound=$false}
}
