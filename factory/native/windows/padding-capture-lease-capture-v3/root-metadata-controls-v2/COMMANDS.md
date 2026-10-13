# Root-run source commands

Run on Dell only after Count1 adapter/transport proof succeeds. Replace `<compile>`, `<exe>`, `<serializer>` with actual lowercase SHA256 values; keep paths exact.

```powershell
$root='D:\Claude\swiftright\factory\native\windows\padding-capture-lease-capture-v3'
$run=Join-Path $root 'actual-batch-r1'
$control=Join-Path $root 'coordinator-batch-r1'
$issue=Join-Path $control 'issued-metadata.json'
& (Join-Path $root 'root-metadata-controls-v2\issue-batch-before-launch.ps1') -Count 20 -RunRoot $run -OutputPath $issue -CompileReceiptSha256 '<compile>' -ExeSha256 '<exe>' -SerializerControlSha256 '<serializer>'
$guard=Join-Path $control 'metadata-guard-controls.json'
& (Join-Path $root 'root-metadata-controls-v2\test-metadata-guard-controls.ps1') -IssuedMetadataPath $issue -IssuedMetadataHash ((Get-FileHash $issue).Hash.ToLowerInvariant()) -RunRoot $run -Count 20 -CompileHash '<compile>' -ExeHash '<exe>' -SerializerHash '<serializer>' -ProducerRoot $root -ControlRoot (Join-Path $control 'guard-controls') -OutputPath $guard
```

Transport Mac tuple, schema, tool, source-binding, & archive bytes. Run local Mac venv validation with explicit files:

```bash
factory/.venv/bin/python factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/verify-common-schema.py \
  --tuple <mac-batch-candidate-tuple.json> \
  --schema factory/native/windows/settled-capture-adapter-v3/dependencies/common.schema.json \
  --root-nonce <issued-run-id> --source-hash <issued-source-hash> \
  --source-binding-file <mac-source-binding.json> --source-archive-file <mac-source-archive>
```

Root may invoke `resume-batch-issued-coordinator.ps1` only after Count1 adapter success, full guard receipt, & Mac schema receipt are independently hash-bound. Packet requires reviewed `dispatch.batch` plan/dispatcher integration for `actual-batch-r1` & fails closed while field is absent.
