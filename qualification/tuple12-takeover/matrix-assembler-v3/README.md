# Tuple12 Full16x20 assembler v3

Read-only assembler source for exactly 16 Windows fixture/variant configurations x 20 runs (320 total). v3 binds R6 diagnostic driver `0b95be5be7e208e9f2d1eefe60287184278e39b6738a9c4fd8388b23f0828d1c` to frozen R5 `5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4`. R6 adds exactly four readiness timing lines; native denominators, markers, noactivate, targeted delivery, identity, handle, kernel, and drain checks remain strict.

Root owns native execution & final admission. Run pure controls first:

```sh
python3 qualification/test_tuple12_windows_full_v3_controls.py
```
