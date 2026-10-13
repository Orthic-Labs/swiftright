# MTA profile repair v1

Prospective source-only repair for next Text & Circle Count1 MTA profiles. It stages an explicit row list, applies measured whole-token replacements, writes fresh output, then creates final `integration-bindings.json` & `admission/source-inputs.json`. It never edits donor files, discovers directories, overwrites output, or treats `count1-r1` as prefix of `count1-r10`.

`repair_mta_profile_v1.py` is the staging/sealing entry. Replacement manifests carry base64 bytes so newline/encoding changes are explicit. Each replacement must match exactly one token with non-token boundaries. Every donor row is checked for regular non-symlink status, size, bytes & SHA-256 before use; final rows are resealed after mutations. Source-inputs binding fields & MTA worker fields are updated only after final binding bytes exist. Receipt records final source-inputs hash; qualification remains held.

`assert-mta-profile-closure-v1.ps1` is production predicate. It validates bounded rows, safe paths, exact bytes/hashes, exact profile kind/path, MTA worker hash, binding ref & source-inputs hash. `test-mta-profile-repair-controls.ps1` calls same predicate against baseline plus 11 mutations: worker hash, row hash, row bytes, duplicate, traversal, binding hash, binding ref, profile path, profile, `r100` tag, missing MTA row & wrong kind.

Current measured donor closures are r4 only. Empty Text/Circle manifests intentionally stage unchanged donor closure for source admission rehearsal; root must add actual measured replacements before new candidate, then rerun predicate. No native/remote/test result is claimed here.

Root stages each profile in fresh ignored namespace, with exact source roots & output paths:

```powershell
$python = 'C:\Python313\python.exe'
$repair = 'D:\Claude\swiftright\factory\pipeline\pilot-next-source-v1\mta-profile-repair-v1\repair_mta_profile_v1.py'
$base = 'D:\Claude\swiftright\factory\native\windows\pilot-text-paint-root-v2\capture-count1-r4-sources\producer'
& $python $repair --source-root $base --binding-template (Join-Path $base 'integration-bindings.json') --source-inputs-template 'D:\Claude\swiftright\factory\native\windows\pilot-text-paint-root-v2\capture-count1-r4-sources\admission\source-inputs.json' --replacement-manifest 'D:\Claude\swiftright\factory\pipeline\pilot-next-source-v1\mta-profile-repair-v1\text-replacement-manifest.json' --output-root 'D:\Claude\swiftright\factory\native\windows\.work\text-mta-profile-r1' --profile text --tag count1-mta-text-r1 --binding-kind root-text-helper-bindings-v1 --binding-ref-path 'D:\Claude\swiftright\factory\native\windows\.work\text-mta-profile-r1\producer\integration-bindings.json' --expected-path-fragment text-paint

& 'D:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File 'D:\Claude\swiftright\factory\pipeline\pilot-next-source-v1\mta-profile-repair-v1\test-mta-profile-repair-controls.ps1' -ProducerRoot 'D:\Claude\swiftright\factory\native\windows\.work\text-mta-profile-r1\producer' -IntegrationBindingsPath 'D:\Claude\swiftright\factory\native\windows\.work\text-mta-profile-r1\producer\integration-bindings.json' -SourceInputsPath 'D:\Claude\swiftright\factory\native\windows\.work\text-mta-profile-r1\admission\source-inputs.json' -Profile text -ExpectedBindingKind root-text-helper-bindings-v1 -ExpectedPathFragment text-paint -ExpectedMtaWorkerHash e8b62b517bb38d21b9006bdea5a5e76dd8b19491a8c5e37403d6cfa2bfe5a547
```

Repeat with Circle r4 root, Circle manifest, `root-circle-helper-bindings-v1`, `circle-mta-profile-r1` & `circle-r11` path fragment. Stage MTA support from `mta-release-diagnosis-v1`; keep renderer `producer/support/final-exit-certificate.ps1` distinct from `producer/dependencies/uia-worker/support/final-exit-certificate.ps1`. Recompute integration rows & source-inputs after every mutation; never perform sequential string replacement on `r1`/`r10`.

Circle command uses exact measured donor paths:

```powershell
$base = 'D:\Claude\swiftright\factory\native\windows\pilot-circle-root-v1\capture-count1-r4-sources\producer'
& $python $repair --source-root $base --binding-template (Join-Path $base 'integration-bindings.json') --source-inputs-template 'D:\Claude\swiftright\factory\native\windows\pilot-circle-root-v1\capture-count1-r4-sources\admission\source-inputs.json' --replacement-manifest 'D:\Claude\swiftright\factory\pipeline\pilot-next-source-v1\mta-profile-repair-v1\circle-replacement-manifest.json' --output-root 'D:\Claude\swiftright\factory\native\windows\.work\circle-mta-profile-r1' --profile circle --tag count1-mta-circle-r1 --binding-kind root-circle-helper-bindings-v1 --binding-ref-path 'D:\Claude\swiftright\factory\native\windows\.work\circle-mta-profile-r1\producer\integration-bindings.json' --expected-path-fragment circle-r11
& 'D:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -File 'D:\Claude\swiftright\factory\pipeline\pilot-next-source-v1\mta-profile-repair-v1\test-mta-profile-repair-controls.ps1' -ProducerRoot 'D:\Claude\swiftright\factory\native\windows\.work\circle-mta-profile-r1\producer' -IntegrationBindingsPath 'D:\Claude\swiftright\factory\native\windows\.work\circle-mta-profile-r1\producer\integration-bindings.json' -SourceInputsPath 'D:\Claude\swiftright\factory\native\windows\.work\circle-mta-profile-r1\admission\source-inputs.json' -Profile circle -ExpectedBindingKind root-circle-helper-bindings-v1 -ExpectedPathFragment circle-r11 -ExpectedMtaWorkerHash e8b62b517bb38d21b9006bdea5a5e76dd8b19491a8c5e37403d6cfa2bfe5a547
```

Before staging root must replace empty manifest entries only with measured exact old/new bytes. After staging, root must independently bind capture-plan, case, tuple, compile receipt, renderer, serializer & producer integration rows; this packet does not manufacture those refs.
