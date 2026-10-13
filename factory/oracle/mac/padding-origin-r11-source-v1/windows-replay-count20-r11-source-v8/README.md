# Fresh Count20 r11 native overlay source-v8

v8 is immutable successor to frozen v4 helpers. It fixes fresh fault validation (`badFaults.Count -ne 0`), requires exact runtime-module equality, requires candidate canonical-input & source-binding hash joins, & stages expected `support\\first-proof-fresh-r11.ps1` from admitted repeat-r7 proof source.

Run v7 full metadata controls first. Stage v8 integration, coordinator, capture, & proof source under one ProducerRoot. Run coordinator headless with issued metadata, v7 receipt, Mac schema receipt, & v8 integration receipt before any native action. Coordinator still requires baseline relocation plus 11 uniquely named rejected metadata faults, all outer metadata resealed, & zero compiler/native/GUI/remote/lock actions.

```powershell
pwsh -NoProfile -File .\\test-full-metadata-controls-v7.ps1 `
  -IssuedMetadataPath <issued-metadata.json> -IssuedMetadataHash <sha256> `
  -RunRoot <fresh-run-root> -CompileHash <actual-receipt-sha256> `
  -ExeHash <actual-exe-sha256> -SerializerHash <metadata.serializerControlSha256> `
  -ProducerRoot <staged-v8-producer-root> -ControlRoot <fresh-repo\\.factory-work\\metadata-controls\\guid> `
  -OutputPath <v7-receipt.json> -IntegrationScript <staged-v8 integration-fresh-r11-v4.ps1>
```

v8 remains source-only until root runs Windows headless controls & serializes native effects. Historical v4/v6/v7 files remain unchanged.
