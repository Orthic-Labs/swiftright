# Bounded adapter v4 proposal

Frozen settled-capture-adapter-v3 accepts standard role refs but does not validate `executionOverlay`. Keep v3 immutable & use its output only as observational hold.

After first actual Count1 input is archived, bounded v4 requires one `executionOverlay` object with:

- `kind=factory-root-execution-overlay-v1`, exact overlay root, base producer profile ref, & non-empty file refs;
- exact `/execute-r4` overlay root & each overlay ref SHA256/bytes, including four r4 execution scripts & prefixed-ID guard;
- base producer profile hash unchanged & distinct from overlay refs;
- output `executionOverlaySha256` joined to input/output receipt.

v4 preserves all v3 joins & qualification holds, rejects absent/unknown overlay refs before any reader action, & never converts observational output into parity or qualification. Frozen settled-capture-adapter-v3 remains unchanged; this bounded source packet is source-ready pending root reissue.
