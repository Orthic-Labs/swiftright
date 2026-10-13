# Count20 repeat-r2 prefixed-ID overlay

Source-only successor from accepted repeat-r1. It keeps `dispatch.repeat`, `actual-repeat-r1`, Count20 first-proof, release, worker, renderer, cleanup, & retry guards. It loads hash-pinned `integration-prefixed-ids-r1.ps1` before metadata admission, so preissued `capture/<32hex>` & `image/<32hex>` IDs satisfy canonical schema while frozen integration remains archived.

Chain: `resume-issued-coordinator-repeat-r2.ps1` -> `interactive-task-repeat-r2.ps1` -> `dispatch-repeat-r2.ps1` -> `capture-repeat-r2.ps1`.

Offline check:

```text
factory/.venv/bin/python factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r2/test-repeat-r2-source.py
```

No native, compiler, GUI, remote, or lock effects are performed by source checks.
