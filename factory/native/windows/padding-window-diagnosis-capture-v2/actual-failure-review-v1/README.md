# Padding window diagnosis v2 actual failure review

Read-only audit of `actual-single-r1` & `coordinator-single-r1`.

Observed receipts: renderer PID `36616` reached final retained-handle kernel `0`/exit `0` & sealed raw streams. UIA worker PID `56152` failed with `Owned renderer identity drift`; cleanup recorded kernel `258`, `killAttempted=true`, `confirmedOwnedExit=false`, status `hold-cleanup`. Its failure receipt was durable before raw drain; final worker receipt stayed failed.

Coordinator recorded `hold-harness-error` yet `wholeBatchExitConfirmed=true` & `lockReleased=true`. Renderer final certificate cannot establish auxiliary UIA worker exit, so release claim is blocked. No causal claim beyond receipt evidence; qualification stays hold.

No native, remote, compiler, process, GUI, lock or Git action was performed.
