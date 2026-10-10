# Acceptance, normalizers & coverage v0.1

Recipes, capability obligations, tolerances, masks, comparator code, normalizers & golden promotion are protected acceptance configuration. Their hash is tuple-bound. Each normalizer rule declares ID, precise scope `(fixture, step, leaf, node)`, reason, before/after samples, owner, & injected-fault control hash. Rule activation requires its fault control to fail with rule active; broad allowances & untested rules reject. Native trees remain retained alongside normalized projections.

Mac capture starts in candidate lane. It becomes accepted only after maintainer review binds candidate hash, diff hash, tuple, reviewer identity, timestamp, & decision. Promotion preserves prior accepted golden & never edits it. Automation, candidate generation, seed capture, receipt generation, or pass verdict cannot promote any golden. An accepted golden can only be used when case & tuple match exactly. A candidate or new tuple is compared to accepted output first; drift remains candidate or blocked.

Recipe expansion fixes expected case set hash. Pairwise axes use declared deterministic generator & seed; declared interacting axes use full product; stateful sequences are obligatory. Missing expected case is failure. Trusted gate additionally creates random cases from gate-chosen seed, persists inputs & seed, captures Mac candidate evidence for that exact seed, qualifies it with 20 Mac runs, then runs 20 Windows replays. Seeded references never promote or replace accepted goldens, & absent/unstable Mac evidence blocks seed comparison.

Headless results are unit evidence only. They may report state, identity, event order, & recorded-native-measurement arithmetic but cannot grant parity.
