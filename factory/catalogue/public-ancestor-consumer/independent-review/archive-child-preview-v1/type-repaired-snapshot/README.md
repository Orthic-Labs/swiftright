# Public ancestor catalogue consumer

This folder will hold a versioned strict-v0.1 catalogue derived from the
immutable base catalogue plus independently replayed public-ancestor proof.
The base catalogue and symbol-graph metadata remain unchanged; additions are
limited to exact compiler USRs absent from the original graph closure.

`consumer.py` implements the fail-closed merge boundary. It checks the pinned
base identity/hash, complete source-start accounting, exact graph membership,
single canonical compiler path per USR, proof classifications, proof-provided
hidden reasons, compiler-record/source-start joins, public child-to-parent joins,
and strict catalogue schema. It uses original raw graph files when present; if
any original is absent, it reconstructs every input through pinned lossless
archive reader & manifest, verifies every whole-file hash & the original 836
USR closure, then removes its temporary internal-cache output. A present but
changed original fails closed without archive substitution. Production entrypoint still needs
final guard/evidence hashes before it can hydrate proof and atomically write the
candidate plus derivation manifest. The manifest binds candidate byte &
canonical hashes, original base raw-source hash, final proof/guard/836 hashes,
all proof-input refs, source/record/child coverage counts, and shared fixed
`createdAt`; original base `sourceHash` does not stand in for augmented-source
provenance. Pair writes roll back if either replace fails. No merged candidate is written while proof inputs/status remain
mutable or Oracle review is pending.

The separate census `v1` is historical & cannot be regenerated because its
original parser bytes are unavailable. Any next raw census must use a copied,
versioned parser file whose SHA-256 is frozen before capture starts, retain full
source/index/request/tool bytes, & leave v1 untouched. The final proof guard
must independently rebuild source-start denominator & classifications from
those pins; this consumer will only use proof rows returned by its production
loader.

Run focused checks with:

```sh
PYTHONPATH=. factory/.venv/bin/python factory/catalogue/public-ancestor-consumer/test_consumer.py
```
