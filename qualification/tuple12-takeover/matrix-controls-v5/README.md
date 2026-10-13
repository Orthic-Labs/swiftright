# Tuple12 matrix controls v5

Source-only runner successor. Worker & coordinator are frozen v4 copies; runner v5 executes each case through `ProcessStartInfo`, retains original coordinator handle before wait, drains stdout/stderr, & records terminal kernel status. Each case writes immutable raw streams plus `matrix-run.json`, including failures; one failed case does not abort remaining 320 cases. Overall exit is 1 when any case fails, with all case records preserved.

Inputs remain base `0e201571e4320a3b6ccce14313fd2ad67e523904`, driver `5c7295a4c71014ec053082f3d04095773b5c2af6183fcf3c2ad95cb4218b58c4`, EXE `87b8cb27ce6730e56681fac3ea22ed3dfb859b3dddb697c339318f4ce60eb374`, renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`, worker/coordinator v4 pins. Root owns parse & native execution.
