# Continuous geometry probe actual R2

Root-owned bounded macOS windowless probe completed successfully. Raw stdout is 17,148 bytes, SHA-256 `59f798f3258b1d1bd4ff42aa0be17b226e182c25fffbdf2893642100c5e1566b`. Probe includes original, aspect-ratio, zero-radius, translated, and large-radius controls.

R2 evidence confirms normalized three-cubic coefficients across ordinary radii, but disconfirms treating `min(width,height)/(2*extent)` as an effective radius for unsupported large requests. `40x20,r100` uses extent 10 while retaining distinct control adjustment; `48x48,r23` uses extent 24 while retaining requested radius 23. `r0` is a five-element rectangle. These large-radius controls remain outside current generic adapter support and must reject explicitly until independently modeled.
