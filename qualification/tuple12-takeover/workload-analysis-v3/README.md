# Tuple12 workload analyzer v3

Immutable successor over v2. PID joins accept v7 retained handles. Clock-domain calibration now uses every captured WorkloadWin present start, including dropped presents; displayed-row eligibility remains independently strict. Preserved v7 evidence gives calibration p95 below 0.2 ms while displayed rows remain 52/62/56, so packet remains incomplete. No threshold is relaxed.
