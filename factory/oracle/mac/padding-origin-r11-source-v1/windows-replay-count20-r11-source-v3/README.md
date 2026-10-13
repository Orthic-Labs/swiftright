# Fresh Count20 r11 coordinator overlay source-v3

This packet provides fresh-namespace coordinator, interactive task, dispatcher, and capture overlays. It clones frozen repeat-r7 execution structure while requiring explicit `ProducerRoot`, `ControlRoot`, `RunRoot`, `OutputRoot`, integration-guard lineage, and fresh r11 guard receipt. Donor `coordinator-repeat-r1` and `actual-repeat-r1` paths are never reused.

Corrected issuer/guard/launch are `issue-count20-fresh-r11-v3.ps1`, `guard-count20-fresh-r11-v3.ps1`, and `launch-count20-fresh-r11-v3.ps1`; v2 remains historical rejected source. Sequence is issue -> guard -> launch gate -> `resume-issued-coordinator-fresh-r11.ps1` -> interactive task -> dispatch -> capture. Resume validates both existing full metadata controls and fresh r11 guard receipt before desktop lock acquisition. Child stages pass same lineage, preserve worker handle retention, raw drain, UIA proof, exhaustive terminal inventory, cleanup, and lock release.

All compiled/runtime/helper dependencies remain frozen repeat-r7 bytes. `source-map-v3.json` records exact overlay hashes, measured Mac host hash `sha256:13bfe5b8fbd9e5a4daa5bae9d50464dbd00b189c55fe7ec8286b287ab4be9777`, Windows executable hash `sha256:3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10`, and zero source-side effects.

Run offline controls:

```sh
factory/.venv/bin/python factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-count20-r11-source-v3/test-count20-fresh-r11-v3.py
```

Root installs overlay only after source hashes pass, then supplies fresh issuer/guard paths and new rolling `.factory-work` namespaces. This packet creates no native window, compiler, lock, GUI, remote, or Git effects.
