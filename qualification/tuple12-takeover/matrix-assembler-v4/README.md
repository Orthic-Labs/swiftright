# Tuple12 Full16x20 assembler v4

Strict assembler binding for matrix-v6 worker/coordinator/runner and R6 diagnostic driver. v4 changes one worker label predicate: product emits `F6-reduced`, so worker-v5 expects that exact label. Native denominator remains `11`; all 16 configurations × 20 runs (`320`) remain mandatory.

Pure controls:

```sh
python3 qualification/test_tuple12_windows_full_v4_controls.py
```
