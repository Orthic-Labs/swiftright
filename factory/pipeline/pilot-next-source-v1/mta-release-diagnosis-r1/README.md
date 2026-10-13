# MTA worker release diagnosis r1

Status is source diagnosis only. Frozen Text Count1-r5f remains unchanged. Actual native observation is not requalified.

## Confirmed blocker

Frozen worker producer writes `config.json.kind = factory-uia-snapshot-worker-config-v2` in `overlay/uia-worker-invoke-v2.ps1`. Frozen release predicate `producer/dependencies/uia-worker/support/final-exit-certificate.ps1` accepts only `factory-uia-snapshot-worker-config-v1` in `Test-FactoryUiaFinalReleaseProof`. Actual r5f evidence has config kind `v2`, while worker terminal/final certificate, retained handle, raw streams, source contract hash, worker script hash, worker executable hash, target identity, MTA worker apartment, exit code 0, kernel wait 0, cleanup status `already-signaled`, & sealed streams are present. Therefore `Test-FactoryAllUiaWorkerReleaseProofs` returns false & caller emits `All owned worker original handle proofs required`.

## Prospective source

`final-exit-certificate-v2.ps1` is exact frozen worker certificate helper with one bounded change: expected config kind is `factory-uia-snapshot-worker-config-v2`, matching producer output. It must be staged as fresh overlay source & hash-bound in integration bindings; frozen r5f helper remains historical.

Do not accept config kind alone. Keep every existing identity/ref/hash/raw-stream predicate. Root should run offline release controls before any future native launch:

1. Positive: actual worker terminal/final certificate/config/output with v2 config kind, exact source root & all contract bindings, returns true.
2. Fault: change config kind to v1, expect false.
3. Fault: change workerScriptHash, sourceContractHash, configHash, worker identity, retained handle, terminal certificate hash, one source-binding hash, or raw-stream hash, expect false.
4. Fault: remove one source binding or change sourceBinding path, expect false.
5. Assert control path performs zero compiler/native-window/lock actions & leaves original r5f evidence untouched.

## Exact evidence

Actual archive: `factory/native/windows/pilot-text-paint-root-v2/actual-count1-r5f-diagnostic/native/native-01/uia-worker/`.

- `config.json`: 2759 bytes, SHA256 `1617583c8addb6435c2dca5b9222b7147a90534d166a8d9f2ea484cabc429ce3` & kind v2.
- `final-exit-certificate.json`: 7303 bytes, SHA256 `322ea3f14e4e28f5ddf966ef0bbd0984c8293e0abf8c30a80903d55b4c408caa`.
- `terminal-worker.json`: 1589 bytes, SHA256 `69228a08d2292f0ad651e9a952f8667351809473c1300e5d6ba554faab3c861e`.
- Worker `final-start.json` retains PID 8972, handle 2664, worker path PowerShell, worker apartment MTA, source contract `cf7bad2f9e2832bd433907aeb0ad916cb8601147fcb4f4116f8016fb2cfa2f52`, worker script `144820b93ef5374f10461d798f935f5399e2eaeec7f82a6e6d2eb84c0eed9af4`.

Frozen source pins used for diagnosis:

- worker certificate helper: `3e3a2cab99320534cd8b3e43d32f3848cceb42a29fe767b7cc5994da4485230d`, 12293 bytes.
- MTA invoker: `e8b62b517bb38d21b9006bdea5a5e76dd8b19491a8c5e37403d6cfa2bfe5a547`, 11500 bytes.
- worker contract: `cf7bad2f9e2832bd433907aeb0ad916cb8601147fcb4f4116f8016fb2cfa2f52`, 1322 bytes.
- frozen release caller: `1298c3570798d6aa72cd0822e8374d4ee9f72a105cebea89b293e240109e761e`, 14408 bytes.

Prospective helper pin: `78b9edaf1b72c389f3c026a6c1e1606505568803bfe3ad67ae1e66416809475d`, 12293 bytes.

## Stager integration

`mta-pilot-stage-v1/stage_mta_count1_r5.py` now replaces worker helper row only inside fresh Text/Circle stage, reseals integration bindings, emits v2 helper hash in stage manifest, & requires same hash in generated closure/installer. `mta-pilot-count20-stage-v1/stage_mta_count20.py` rejects donor stages whose worker helper is not this v2 pin & emits v2 helper metadata. Renderer helper remains separate.

`test-r5f-worker-release-v2.ps1` is non-mutating offline control entry. It reads exact archived worker closure, uses exact-path reader, then injects config-kind, worker-hash, retained-handle, source-binding, raw-stream, & terminal-certificate mutations in memory. Each case captures bounded `accepted` & `error` fields; receipt is written even when control status is `source-control-fail`, so root can diagnose without rerunning native work. Positive must pass; every mutant must reject.

`supplemental-owner-release-v2.ps1` is separate root-run entry. It validates explicit coordinator/task-result/source-input/issued/compile/exe joins, exact v2 worker + frozen renderer helper pins, zero-effect control receipt, parent kernel/.NET exit, & 1 GiB memory/self-only proof, then performs exact owner-to-free CAS & writes one fresh bounded supplement. It never rewrites coordinator or native receipts.

Root staging commands use existing bounded stagers:

```powershell
python stage_mta_count1_r5.py --profile text --donor-root <fresh-r4-donor> --installer-template <install-count1-r4.ps1> --output-root <fresh-stage> --output-zip <fresh.zip> --output-installer <fresh-installer.ps1> --namespace <fresh-text-namespace>
python stage_mta_count20.py --profile text --donor-root <admitted-count1-stage> --count1-certificate <count1-certificate.json> --count1-certificate-sha256 <64hex> --count1-certificate-bytes <bytes> --lifecycle-root <count20-lifecycle> --output-root <fresh-count20-stage> --output-zip <fresh-count20.zip> --output-installer <fresh-count20-installer.ps1> --namespace <fresh-text-count20-namespace>
```

Offline control entry, run against exported r5f paths on Windows:

```powershell
& .\test-r5f-worker-release-v2.ps1 -WorkerRoot <native-01>\uia-worker -ProducerRoot <producer-count1-r5> -ControlRoot <control>\r5f-worker-release-v2
```

Supplement entry requires root-supplied exact paths & performs CAS only after proof:

```powershell
& .\supplemental-owner-release-v2.ps1 -Directory <native-01> -CoordinatorReceiptPath <control>\coordinator.json -TaskResultPath <control>\task-result.json -TaskResultHash <64hex> -ProducerRoot <producer-count1-r5> -SourceInputsPath <admission-count1-r5>\source-inputs.json -SourceInputsHash <64hex> -IssuedMetadataPath <native>\issued-metadata.json -IssuedMetadataHash <64hex> -IntegrationGuardPath <overlay-count1-r5>\integration-fresh-text-v1.ps1 -IntegrationGuardHash <64hex> -ControlsPath .\test-r5f-worker-release-v2.ps1 -ControlsHash <64hex> -ControlsReceiptPath <control>\r5f-worker-release-v2\r5f-worker-release-v2-controls.json -ControlsReceiptHash <64hex> -FrozenReleasePath <frozen>\all-owned-release-text-r1.ps1 -FrozenReleaseHash <64hex> -V2HelperPath .\final-exit-certificate-v2.ps1 -V2HelperHash <64hex> -RendererHelperPath <producer-count1-r5>\support\final-exit-certificate.ps1 -RendererHelperHash <64hex> -AllOwnedReleasePath <producer-count1-r5>\support\all-owned-release.ps1 -AllOwnedReleaseHash <64hex> -CompilePath <receipt> -CompileHash <64hex> -Exe <exe> -ExeHash <64hex> -SourceHash <sha256:...> -LockPath D:\Claude\desktop.lock -SupplementalPath <control>\supplemental-owner-release-v2.json
```
