# Tuple12 workload coordinator v5

Source-only coordinator successor over v4. Root owns parser, build, native execution, and lock effects.

Coordinator v5 keeps semantic proof separate from cleanup proof. Semantic success requires exactly three valid runs, per-run signed worker/sampler terminal records, drained streams, guarded no-activate startup, `WORKLOAD-WIN-DONE` with `aborted=false`, one terminal PresentMon record, signed kernel/.NET equality, and `orchestratorExit=0`.

PresentMon proof requires raw DWORD plus signed exit equality, explicit natural/forced-owned stop, drained stdout/stderr, exact owned session stop result, and bounded `session_absent=true`. Cleanup release requires orchestrator/task quiescence, every started worker/sampler handle terminal/drained, scoped early-failure identity proof, and independent PresentMon session cleanup. Semantic failure never weakens cleanup proof.

Pinned source base is `0e201571e4320a3b6ccce14313fd2ad67e523904`; Workload EXE is `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`; renderer is `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`.
