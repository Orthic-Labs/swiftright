# Tuple12 workload coordinator v4

Source-only Windows coordinator candidate. Root owns parser, build, native run, & lock effects.

Coordinator v4 separates `SemanticProof` from `CleanupProof`:

- Semantic success still requires exactly 3 runs, each worker/sampler kernel terminal with non-259 exit, all four streams drained, one terminal PresentMon session, signed kernel/.NET exit equality (including explicitly recorded `forced-owned` stop), lifecycle markers, & orchestrator exit 0.
- Cleanup release requires orchestrator terminal, outer streams drained, scheduled task quiescent, exact PresentMon cleanup proof, & every started worker/sampler handle terminal with native kernel exit proof plus stream drains. Fewer than 3 started runs are valid only for cleanup after early failure; they never produce semantic success.
- If no worker result exists because failure happened before worker launch, release requires task quiescence plus scoped `Win32_Process` identity snapshot showing no exact workload executable path or run-tagged resource sampler. Snapshot failure preserves lock.
- No process-name polling, global kill, or destructive cleanup is used. Receipt uses `CreateNew`.

Pinned inputs are inherited from tuple12 Workload source build: base `0e201571e4320a3b6ccce14313fd2ad67e523904`, Workload EXE `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`, renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`.
