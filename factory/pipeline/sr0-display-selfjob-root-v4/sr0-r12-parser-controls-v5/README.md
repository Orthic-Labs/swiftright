# SR0 r12 parser controls v5

Use explicit `OriginalHelperPath` & `FreshHelperPath`. Original V7 is hash-pinned from `source-pins.json`, loaded first, & must reject archived CRLF. Fresh V7 keeps identical function names, adds exact CRLF→LF replacement, & must accept archived CRLF & derived LF. No bare-CR normalization exists.

Controls then reject missing `pid_exit`, mismatched parent, & zero handle with one-second grace. Fixture remains 2,837 bytes, SHA-256 `c841626334d8b7a2ad9c13a1e72a4db49f6e64077b6e9bc622f2e4b387d0ae3e`.

```powershell
& .\test-parser-controls-v5.ps1 `
  -ResultPath '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\root-native-r12-observer-r13-r1\actual-run-raw-r3\result-workload.txt' `
  -OriginalHelperPath '<repo>\native-r10c-recovery-v1\workload-identity-v7.ps1' `
  -FreshHelperPath '<fresh-stage>\workload-identity-v7.ps1' `
  -SourcePinsPath '.\source-pins.json' -ControlRoot '<fresh-control-root>' -WrapperPid 58252
```

No qualification claim is emitted.
