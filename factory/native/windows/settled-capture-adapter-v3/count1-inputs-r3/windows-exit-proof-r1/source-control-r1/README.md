# WindowsExitProof source-control capsule r1

`test-windows-exit-proof-source-control-r1.py` invokes production `verify_windows_exit_admission` against exact preserved old-r3 raw bytes. It binds all 13 proof roles, runs exact production compile/argv predicates, & records missing compiler transport without synthesis. Synthetic capture/image IDs carry `control-only`; output is blocked, grants no native parity, & performs zero native/lock/remote actions.

Source-only command:

```sh
python3 factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/windows-exit-proof-r1/source-control-r1/test-windows-exit-proof-source-control-r1.py \
  --repo . \
  --output /tmp/windows-exit-proof-source-control-r1.json
```

Observed old-r3 blockers: observation lacks `ownedIdentity`; observation `hwnd` is null while owned-close `hwnd` is 41093876. All 8 compile/argv checks pass. Compiler transport remains held because expected SHA256 `1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a` has no local bytes.
