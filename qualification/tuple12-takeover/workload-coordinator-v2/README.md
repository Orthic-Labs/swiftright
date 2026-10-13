# Tuple12 Workload coordinator v2

Source-only coordinator successor to frozen v1. v2 fixes orchestrator argument construction, requires exactly three per-run worker/sampler terminal records with both stream drains, requires one PresentMon session record with native handle terminal + kernel/.NET exit equality + both drains, & releases desktop lock only after all proofs.

v3 lifecycle controls stay frozen; v4 candidate is required for native use.

Pinned build: base `0e201571e4320a3b6ccce14313fd2ad67e523904`, WorkloadWin `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`, renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`.
