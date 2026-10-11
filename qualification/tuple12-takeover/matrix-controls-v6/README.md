# Tuple12 matrix controls v6

Source-only successor for one product-label mismatch in F6-reduced. Frozen r6 trace emits `F6-reduced`; worker-v4 expected `F6 reduced`, causing worker exit 1 after valid native `11/11` output. v5 matches exact product label only for this variant. Native assertions & denominator stay strict.

`run-matrix-v6.ps1 -Mode F6Reduced` runs exactly 20 targeted F6-reduced cases. `-Mode Full` retains all 16 configurations × 20 runs. Root owns parser, native launch, lock, & admission.
