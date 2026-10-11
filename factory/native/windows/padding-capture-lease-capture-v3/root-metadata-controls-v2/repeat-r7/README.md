# Count20 repeat-r7 source successor

repeat-r7 is prospective source-only successor to frozen repeat-r6. It preserves capture, UIA, cleanup, release, timing, metadata, & Win32 behavior while fixing scheduled-task dependency scope: `first-proof-repeat-r7.ps1` self-loads exact `dependencies/uia-worker/schema.ps1` bytes (SHA256 `ca1590fa7d41669ff4217ad282c1a1d1af747ffcb0b14ee002bcad0c3eafbb61`) before first-proof functions are invoked. Dispatch & coordinator each dot-source this helper, so child task scope does not depend on parent imports.

`test-repeat-r7-source.py` verifies five overlay sources, schema hash, both helper call sites, Win32 import invariance, & faults for schema drift or helper omission. It performs no PowerShell, lock, GUI, compiler, remote, or native action.

Run:

```sh
python3 factory/native/windows/padding-capture-lease-capture-v3/root-metadata-controls-v2/repeat-r7/test-repeat-r7-source.py
```
