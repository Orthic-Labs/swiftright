# Fresh Mac r11 common.schema verifier

`verify-common-schema-r11.py` validates fresh tuple identity, exact case/host/source joins & common.schema offline. It requires `--expected-tuple-id`; old tuple IDs, source hashes, source-binding refs & host hashes reject before any factory action.

Use factory venv Python with explicit files:

```sh
factory/.venv/bin/python verify-common-schema-r11.py \
  --tuple <fresh-candidate-tuple.json> \
  --schema factory/native/windows/settled-capture-adapter-v3/dependencies/common.schema.json \
  --root-nonce <issued-run-id-hex> \
  --source-hash sha256:b969817f59b409121be96eea473322186969ff355d632be9aea227150582554b \
  --expected-tuple-id sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011 \
  --source-binding-file factory/oracle/mac/padding-origin-r11-source-v1/windows-root-headless-r11-r1/observed-headless-r11-r1/actual-inputs/source-binding.json \
  --source-archive-file <exact-source-archive-file>
```

Output receipt keeps v10 coordinator fields: receipt kind/version/status, nonce, source hash, tuple/case/host joins, candidate tuple/schema/tool/source refs & zero effect counters. Source-binding archive must match measured source-binding bytes/hash. It remains observation-only; tuple stays unfrozen.

Run bounded source controls with same arguments through `factory/tools/supervise-job.py`; baseline must pass & wrong tuple ID, source-binding hash & source hash must reject with no effects:

```sh
python3 factory/tools/supervise-job.py --seconds 30 --rss-mib 256 --out <fresh-control-log> -- \
  factory/.venv/bin/python test-common-schema-r11.py <same verifier arguments>
```

Controls require baseline acceptance & reject wrong tuple ID, source-binding ref, source hash, source archive, Mac host hash & Windows host hash with zero effects.
