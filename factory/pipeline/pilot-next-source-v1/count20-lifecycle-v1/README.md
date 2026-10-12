# Count1/Count20 lifecycle successor

Prospective source-only overlay derived from frozen `count1-lifecycle-v3`. It accepts exactly `count=1` or `count=20`; Count20 requires issued captures with runs `1..20`, `native-01..native-20`, exact case/tuple/source/compile/renderer/serializer bindings, & one retained parent handle plus 1 GiB self-job proof for each completed task. Every run keeps native window, worker, stream, terminal, & owned-release receipts. Lock release requires whole-batch terminal proof; no qualification or parity claim is emitted.

Budgets are count-specific: setup is 180 seconds, each native window remains 30 seconds, native exit remains 15 seconds, capture is 60 seconds for Count1 & 600 seconds for Count20, cleanup is 60 seconds, outer is 300 seconds for Count1 & 840 seconds for Count20, scheduler is 5 minutes for Count1 & 15 minutes for Count20. These values are source controls, not relaxed native assertions.

Root stages these files beside existing producer dependencies, runs source preflight, then controls/native effects. `PreflightOnly` remains effect-free. Frozen Count1 files remain unchanged.
