# F10 Rectangle reader input v2

Consumes explicit `actual-count20-r4/export-manifest.json` plus separate artifact-binding JSON. Manifest count must equal current row count; no fixed 760 assumption. Requires exact tuple/case CLI values, native-01..native-20 proof roles, global plan/compile/runtime/source roles, parent kernel certificates, & compiler/exe/renderer refs joined by exact path, bytes, SHA. Emits `qualified=false`, `nativeParityGranted=false`; no copying, discovery, aliasing, or golden claim.

Root command shape:

```text
python prepare_f10_adapter_input.py --export-manifest <actual-count20-r4/export-manifest.json> --artifact-bindings <measured-artifacts.json> --expected-tuple <measured-tuple.id> --expected-case <measured-case.id> --output <fresh-input-map.json>
```

`measured-artifacts.json` must contain `compiler`, `exe`, `renderer` objects with `path`, `bytes`, `sha256`; each path must already be present in export manifest. Missing artifact rows remain held.
