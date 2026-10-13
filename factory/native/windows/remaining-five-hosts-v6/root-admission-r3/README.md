# Remaining-five rolling-root admission r3

Source-only successor for five held cases, preserving r2 plans while adding exact v5 transfer dependency pin (70 rows), runtime lifecycle admission (`activeRootCount <= 3` plus quiescence before reuse/move), and Count1 adapter transport. No compiler/native/remote actions occur here. Runtime facts input is explicitly unobserved; root must provide fresh facts before any reuse/move/Windows effect.

Run from repo root:

```text
PYTHONDONTWRITEBYTECODE=1 python3 factory/native/windows/remaining-five-hosts-v6/root-admission-r3/verify_source_packet.py
```
