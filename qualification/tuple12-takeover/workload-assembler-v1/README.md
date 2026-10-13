# Tuple12 workload assembler v1

Read-only scoped assembler for one fresh Workload packet. It binds coordinator receipt, three-run result, PresentMon console/CSV, build metadata, & analyzer report to exact EXE/DLL hashes. Any missing console, failed coordinator, non-release build, missing incremental gate, failed report, or proof mismatch produces `incomplete`; inputs remain untouched.

Observed v7 packet is intentionally incomplete. Root must stage v8 controls & analyzer v2, produce release build metadata plus genuine `Base\\incremental.json`, then run fresh native workload before rerunning assembler.
