# UIA source-closure admission v1

`assert-uia-source-closure.ps1` is source-only admission before native launch. It verifies bounded integration metadata, every relative `.files` row under producer root, regular non-reparse bytes & streamed SHA-256, worker-contract `sourceBindings`, exact integration-row joins, uniqueness, path containment, & required `invoke-worker-mta.ps1` membership. It performs no lock, process, or native action.

Root stages helper before capture preflight, then calls:

```powershell
. .\uia-source-closure-admission-v1\assert-uia-source-closure.ps1
$closure=Assert-FactoryUiaSourceClosure -ProducerRoot $ProducerRoot -WorkerSourceRoot (Join-Path $ProducerRoot 'dependencies\uia-worker') -WorkerContractPath (Join-Path $ProducerRoot 'dependencies\uia-worker\worker-contract.json') -IntegrationBindingsPath $SourceInputs.integrationBindingsRef.path -IntegrationBindingsBytes $SourceInputs.integrationBindingsRef.bytes -IntegrationBindingsHash $SourceInputs.integrationBindingsRef.sha256 -SourceBindings $Contract.sourceBindings -RequireMtaInvoker
```

Use actual `integrationBindingsRef` object fields & `.files` rows; do not substitute legacy `sourceBindings`, `bindings`, or `rows` manifests. `test-uia-source-closure-controls.ps1` contains positive admission plus missing-MTA, mutated-row, wrong-hash, traversal, & duplicate-binding rejection cases. Controls leave fresh fixtures for inspection.
