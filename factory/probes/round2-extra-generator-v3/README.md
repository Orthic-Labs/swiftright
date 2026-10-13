# Round2 extra generator v3

Source-only successor for held F4 candidate recipes. It emits 19 descriptors across five blocks with 14 positive projections & 5 must-not-compile negatives; it performs no compiler, native, registry, or qualification work.

Independent v2 review found output-binding HOLD: case identity check was tautological & emitted source metadata was not bound to actual reconstructed bytes. v3 requires exact `case.id == descriptor.id`, exact descriptor membership in frozen validation descriptors, exact descriptor hash, frozen recipe & witness identity, declared Swift type, projected body hash, canonical expected source bytes, source filename, source hash, & equality against bytes passed to public `generate(packet, output_dir)`.

Frozen inputs remain pinned to candidate `e7366d2f...5febf`, source join `71141aa8...3353a`, validation `44096669...f0ba`, native holds `2610d49e...18270`, & catalogue `740f000f...f5270`. Review remains identity/source-only; no promotion is claimed.
