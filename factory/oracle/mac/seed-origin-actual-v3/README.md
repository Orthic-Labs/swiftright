# Seed origin actual v3 successor index

V3 is index-only. It references immutable `../seed-origin-actual-v2` capture bytes, summaries, compiler/AX receipts, raw files, case joins, archive map & stage manifest; no recapture or byte copy occurred. V2 review found one historical archive-map mismatch: map expected `fault-controls.json` SHA `202cd05d...`, while immutable current bytes are `233714ad...`; both are 1,153 bytes. Cause: `test_actual_v2.py` rewrote frozen `fault-controls.json` after archive-map generation when v2 archive gained verifier/test files, changing baseline metadata. V2 files remain untouched.

V3 writes controls only to `fault-controls-v3.json`, records exact v2 source hash, & keeps decision `BLOCKED_ARCHIVE_HISTORY_ONLY` until parent review handles historical mismatch.
