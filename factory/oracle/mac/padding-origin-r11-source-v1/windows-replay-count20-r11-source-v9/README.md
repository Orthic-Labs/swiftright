# Fresh Count20 r11 metadata controls source-v9

v9 validates active v8 integration error contracts. It runs baseline, relocated resealed positive, & 11 resealed faults against actual `Assert-LeaseIssuedMetadata`, including valid-path fresh-case context drift. It uses fresh repo `.factory-work` ControlRoot, writes mutation evidence, performs no deletion, TempPath use, native, compiler, GUI, remote, or lock action.

Stage `integration-fresh-r11-v5.ps1` & run controls before native:

```powershell
pwsh -NoProfile -File .\\test-full-metadata-controls-v9.ps1 `
  -IssuedMetadataPath <issued-metadata.json> -IssuedMetadataHash <sha256> `
  -RunRoot <fresh-run-root> -CompileHash 1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf `
  -ExeHash 3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10 `
  -SerializerHash <metadata.serializerControlSha256> -ProducerRoot <producer-root> `
  -ControlRoot <repo\\.factory-work\\metadata-controls\\fresh-guid> -OutputPath <receipt.json> `
  -IntegrationScript <staged-v9>\\integration-fresh-r11-v5.ps1
```
