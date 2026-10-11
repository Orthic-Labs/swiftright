# F2 comparator guard v3

This snapshot preserves comparator-guard-v2 bytes & adds one invariant: frozen manifest & expected-membership hashes are checked again against exact raw bytes consumed after dependency verification, before JSON parsing. This rejects verify-to-consumption replacement races while passing exact final-candidate & fault controls.

Inputs remain frozen v1 manifest SHA `7a2e80bf7ce132955e46b676c4818f96bfaebde279f5d5a4868da5d3bb482cf1` & expected-membership SHA `f1d482a89d7d09d741cb3dc0d49fc6532cb06a758a28c27efd09836f17728af3`.
