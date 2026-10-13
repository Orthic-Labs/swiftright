# SR0 r12 parser controls v4

Archived `actual-run-raw-r3/result-workload.txt` is pinned at 2,837 bytes, SHA-256 `c841626334d8b7a2ad9c13a1e72a4db49f6e64077b6e9bc622f2e4b387d0ae3e`, with CRLF bytes preserved.

`workload-identity-v7.ps1` retains production function names. Only `$text` read adds `.Replace("`r`n","`n")`; bare CR normalization is absent. `test-parser-controls-v4.ps1` invokes original V7 first & requires archived CRLF rejection, then fresh V7 with same names and requires CRLF/LF acceptance. Missing `pid_exit`, mismatched parent, & zero handle each reject with one-second grace.

Root invocation:

```powershell
& .\test-parser-controls-v4.ps1 `
  -ResultPath '<repo>\factory\pipeline\sr0-display-selfjob-root-v4\native-r10c-recovery-v1\root-native-r12-observer-r13-r1\actual-run-raw-r3\result-workload.txt' `
  -ControlRoot '<fresh-control-root>' -WrapperPid 58252
```

No qualification claim is emitted.
