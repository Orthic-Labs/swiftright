# Fresh Count20 r11 native overlay source-v10

v10 is new overlay over v9 controls & frozen capture/release helpers. It removes donor host-layout assumptions, binds compiled package path from staged `capture-plan.json`, records fresh issued case beside compiled donor case, accepts explicit schema path, & provides coordinator/dispatcher/capture source-only preflight switches.

Stage all v10 files beside ProducerRoot dependencies/support. Use namespace:

```powershell
$ns='D:\Claude\swiftright\.factory-work\windows-replay-r11'
$producer="$ns\producer"
$control="$ns\coordinator-r1"
$output="$ns\replays"
$run="$output\r1"
```

Run v10 controls first, then coordinator preflight before lock/GUI:

```powershell
pwsh -NoProfile -File .\resume-issued-coordinator-fresh-r11-v10.ps1 `
  -CompileReceiptHash <actual-receipt-sha256> -ExeHash 3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a `
  -SerializerControlSha256 <metadata.serializerControlSha256> `
  -IssuedMetadataPath "$control\issued-metadata.json" -IssuedMetadataHash <issued-sha256> `
  -GuardControlsPath <full-guard-receipt> -GuardControlsHash <full-guard-sha256> `
  -MacSchemaReceiptPath <mac-schema-receipt> -MacSchemaReceiptHash <mac-schema-sha256> `
  -ProducerRoot $producer -ControlRoot $control -RunRoot $run -OutputRoot $output `
  -FreshGuardControlsPath <v9-controls-receipt> -FreshGuardControlsHash <v9-controls-sha256> `
  -IntegrationGuardPath "$producer\integration-fresh-r11-v6.ps1" -IntegrationGuardHash <integration-sha256> `
  -SchemaPath <staged-common.schema.json> -PreflightOnly
```

Coordinator preflight writes `coordinator-preflight.json` under ControlRoot & performs zero lock/native/GUI actions. Dispatcher or capture can run `-PreflightOnly` separately; capture writes `capture-preflight.json` without creating RunRoot. Remove `-PreflightOnly` only after root reviews receipts.
