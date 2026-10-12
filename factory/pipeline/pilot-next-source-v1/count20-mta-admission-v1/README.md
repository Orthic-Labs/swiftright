# Count20 MTA admission v1

`stage-count20-mta-admission.ps1` stages frozen Count20 lifecycle sources & Count1-r9 producer closure into fresh output. It enumerates integration `.files`, copies each bounded source exactly once, replaces active lifecycle invoker/capture with pinned MTA overlay sources, preserves original lifecycle copies under source names, requires worker-contract `sourceBindings` including `invoke-worker-mta.ps1`, then calls `uia-source-closure-admission-v1` before emitting source-only admission JSON.

Root invocation after original successful Count1 certificate is available:

```powershell
.\stage-count20-mta-admission.ps1 `
  -Count1SourcesRoot D:\Claude\swiftright\factory\native\windows\pilot-rectangle-fixed-root-v2\capture-count1-r9-sources `
  -Count20LifecycleRoot D:\Claude\swiftright\factory\pipeline\pilot-next-source-v1\count20-lifecycle-v1 `
  -OutputRoot D:\Claude\swiftright\factory\native\windows\.work\rectangle-count20-mta-admission-r1 `
  -OriginalCount1CertificatePath <fresh-count1-certificate.json> `
  -OriginalCount1CertificateHash <sha256> `
  -OriginalCount1CertificateBytes <bytes>
```

Output contains `lifecycle/`, `producer/`, `closure/`, & `count20-mta-admission.json`. Active `lifecycle/capture-rectangle-count20-v1.ps1` is bound to active `lifecycle/uia-worker-invoke-v2.ps1`, whose worker apartment is fixed `MTA`; original lifecycle files remain preserved under `*-source-v1.ps1`. Fresh output is required; script refuses overwrite. It performs no lock, process, compiler, SSH, or native action. Count20 native admission remains pending root review & actual certificate.

Admission rejects stale certificate hash/bytes, incomplete Count1 status/parent kernel/.NET zero-exit proof, lifecycle source drift, duplicate or escaping paths, missing integration rows, mutated worker sources, contract/source-binding mismatch, missing `invoke-worker-mta.ps1`, & any copy overwrite. `test-count20-count1-certificate-controls.ps1` calls strict production certificate guard against positive, status, whole-batch, lock, kernel, .NET, & missing-field faults. Closure controls remain in `uia-source-closure-admission-v1`; its current helper pin is 8202 B `65452d50bed0ac3f581a6fe485954c506aa60314af49b49be61030d5f47ffe0b`.

## Fresh Count20 execution preparation

After issuer creates fresh metadata, `prepare-count20-execution-v1.ps1` validates exact Count20 metadata, source-input joins, issuer/coordinator/guard bytes, & staged lifecycle rows, then writes fresh coordinator JSON consumed by existing `coordinator-count20-lifecycle-v1.ps1`. It performs no lock, process, compiler, SSH, or native action.

```powershell
.\prepare-count20-execution-v1.ps1 `
  -AdmissionPath <count20-mta-admission.json> `
  -SourceInputsPath <fresh-count20-source-inputs.json> -SourceInputsHash <64hex> `
  -IssuedMetadataPath <fresh-count20-issued-metadata.json> -IssuedMetadataHash <64hex> `
  -IssuerPath <issue-rectangle-metadata-v1.ps1> -IssuerHash <64hex> `
  -CoordinatorPath <coordinator-count20-lifecycle-v1.ps1> -CoordinatorHash <64hex> `
  -Package <fresh-package-root> -ProducerRoot <staged-producer> -AdmissionRoot <admission-root> `
  -OverlayRoot <staged-output-root> -ControlRoot <fresh-control-root> -OutputRoot <fresh-output-root> `
  -RunRoot <fresh-output-root>\replays\r1 `
  -IntegrationGuardPath <fresh-integration-guard.ps1> -IntegrationGuardHash <64hex> `
  -OutputPath <fresh-control-root>\count20-execution-template.json
```

Preparation rejects Count1 aliases, stale run roots, wrong issuer/coordinator bytes, non-Count20 metadata, unordered or unprefixed IDs, source/case drift, & incomplete closure. Result records `nativeActions=0`, `compilerActions=0`, `remoteActions=0`, & `lockActions=0`; root may pass result to existing coordinator only after review.
