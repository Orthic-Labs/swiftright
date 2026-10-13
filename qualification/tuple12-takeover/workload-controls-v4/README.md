# Tuple12 Workload lifecycle controls v4

Source-only successor to frozen v3. v4 retains v3 defaults & adds strict per-run sampler stdout/stderr drains, sampler handle/kernel exit records, aggregate sampler proof initialized true then cleared on any start/terminal/drain failure, & PresentMon native handle terminal proof with kernel/.NET exit equality.

Pinned candidate artifacts remain base `0e201571e4320a3b6ccce14313fd2ad67e523904`, source manifest `f45b9e0dab99428194946341b0170f3e0beed874f9f552d01fd9046f3200b7ca`, materialized `26705e8f1fdd0164a9963c9cb0f730fda2e313e5c07348097c8fe8ab3ef7e468`, WorkloadWin `7e749248800da8e6058b0b69ccbab2a5ce2e43a1a719475616da5e92936d930c`, renderer `7578cd5da8a6831900c66680c4b94f89e64b6b294623709817848b02219aeac2`.

Root must parse/Add-Type before native use. v3 stays frozen for provenance.
