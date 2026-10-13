# Fresh Count20 r11 integration validator source-v6

v6 is immutable successor to v5. It retains frozen Count1 delegation & v4 execution helpers, then adds exact measured donor receipt closure, fresh raw/semantic case joins, source-equivalence refs, prefixed capture IDs with run indexes, & one-literal-backslash descendant binding. Donor observation must prove `exitCode=0`, `timedOut=false`, `ownedExited=true`, `streamDrainComplete=true`, `nativeWindowOpened=false`, exact `exeSha256`, exact `sourceHash`, runtime commit/tree, compiler, renderer, plan & receipt hashes.

Stage `integration-fresh-r11-v3.ps1` with frozen support/integration dependencies. Run `test-fresh-integration-v6.ps1` against issued Count20 metadata before any native action. It calls actual v6 admission once positively, then mutates plan ref, historical case ID, capture ID, run index, & executable hash; each mutation must reject. Output reports native/compiler/lock/remote actions as zero.

Use `source-map-v6.json` for measured bytes/hashes. No compiler, GUI, native, lock, remote, or Git effects occur in source validation.

Headless invocation after source staging:

```powershell
pwsh -NoProfile -File .\test-fresh-integration-v6.ps1 `
  -IntegrationScript .\integration-fresh-r11-v3.ps1 `
  -MetadataPath <issued-metadata.json> -MetadataHash <issued-metadata-sha256> `
  -RunRoot <metadata.runRoot> -CompileHash 1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf `
  -ExeHash 3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10a `
  -SerializerHash <metadata.serializerControlSha256> -ProducerRoot <producer-root>
```
