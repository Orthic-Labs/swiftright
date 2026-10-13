# Round2 extra generator v2

Source-only successor for held F4 candidate recipes. It emits 19 descriptors across five blocks and performs no compiler, native, registry, or qualification work.

v1 review found two binding faults: negative manifests pointed at positive Witness files, and public `generate(packet, dir)` accepted empty source-use selections. v2 binds each negative manifest to its exact `Negative_round2` source identity, requires exact frozen source-use paths, order, cardinality, nonempty USRs, policy fields, and validates every emitted manifest before writing it.

Frozen inputs remain pinned to candidate `e7366d2f...5febf`, source join `71141aa8...3353a`, validation `44096669...f0ba`, native holds `2610d49e...18270`, and catalogue `740f000f...f5270`. Review remains identity/source-only; no promotion is claimed.
