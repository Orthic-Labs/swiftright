# Tuple12 Windows Full assembler v2

Read-only assembler for exactly 16 fixture/variant configurations × 20 runs = 320 receipts. It admits only matrix v5 records, exact worker/coordinator v5 pins, renderer/EXE/driver pins, native per-variant denominator, startup guard, targeted delivery, same HWND/process/handle, and complete worker/driver cleanup proofs. Any missing or failed case remains in report; status is `qualified` only at 320 passed cases.

Source: `qualification/assemble-tuple12-windows-full-v2.py`. Controls: `qualification/test_tuple12_windows_full_v2_controls.py`. Input/output paths are reparse/symlink rejected; output uses exclusive creation. Runner source must be supplied with `--runner-path` & `--expected-runner`.
