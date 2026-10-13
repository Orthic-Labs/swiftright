# Adapter v10 source successor

v10 extends frozen v9 with strict issued lineage. Current r16 evidence carries runID `01acb1d24a04471fa5709dac1c4a73c5` & issued metadata SHA256 `sha256:7216cd29266556cff4fec9a214f4bd5b403218db27d2007edc90823334e500e6`. Producer input map requires completed task result, validates exact issued metadata bytes/hash, and binds task result ref. Normalizer, adapter, and trusted reader require same lineage from derived plan.

Task memory receipt must report actual job limit 1 GiB, `JOB_OBJECT_LIMIT_JOB_MEMORY` flags `0x200`, active process count `1`, `killOnJobClose=false`, nonnegative peak no greater than limit, positive parent PID, and exact issued run/hash. `test-memory-lineage-fixture-controls-v10.py` reseals baseline & nonce/hash/cap/active/flag/kill/peak mutations under caller control root. Fixture result explicitly carries `nativeEvidence=false` & `fixture-only-no-fresh-qualification`.

Run order after root transfers verified archive: v10 input-map producer → v10 input producer → v10 adapter/proof composition → v10 trusted reader (`--input-map`, `--input-archive-root`, `--archive-root`). Existing v9 sources remain frozen.

For each fresh candidate, `derive-adapter-plan-r16.py` reads issued metadata from repository-relative path, streams measured bytes/hash, validates source/case/20 capture/image joins, and emits successor plan lineage from actual runID. It does not accept caller-only nonce claims. `test-r16-plan-deriver-fixtures.py` covers alternate valid run, malformed run, source/case drift, and duplicate capture faults; fixture output remains non-evidence.
