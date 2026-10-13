# Count1 execute-r4 prefixed-ID overlay

Source-only successor from accepted execute-r3. It loads hash-pinned `integration-prefixed-ids-r1.ps1`, which preserves frozen integration semantics while admitting schema-valid `capture/<32hex>` & `image/<32hex>` preissued IDs. Chain is coordinator-r4 -> interactive-task-r4 -> dispatch-r4 -> capture-repeat-r4. Prefixed issuer overlay is installed alongside these files before root reissues metadata.

`test-metadata-guard-controls-r4.ps1` preserves 13 baseline/relocated/fault controls, supports Count1 & Count20, resolves frozen integration from capture-v3 base, & dot-sources hash-pinned prefixed guard.

Offline check:

```text
factory/.venv/bin/python factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v1/execute-r4/test-execute-r4-source.py
```
