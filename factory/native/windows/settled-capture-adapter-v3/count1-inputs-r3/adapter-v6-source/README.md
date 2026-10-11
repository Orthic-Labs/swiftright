# Adapter-v6 repeat-r7 executable successor

Adapter-v6 composes frozen adapter-v5 through an in-memory overlay admission extension for exact repeat-r7 sources. Frozen adapter-v5 files remain unchanged. `produce-input-map-v6.py` verifies fresh Count20 metadata manifest (exactly 40 files), fresh issued metadata, & explicit native archive paths; it emits byte/hash refs only & fails closed when native refs are absent unless `--allow-pending` is explicit. Pending mode records no invented hashes.

`produce-inputs-v6.py` runs source admission against complete map. `run-adapter-v6.py` then normalizes actual observations & optionally attaches production proof-r2, preserving all 13 proof roles, raw stream seals, candidate joins, & parity hold. Output paths must be fresh.

Generate pending source map:

```sh
factory/.venv/bin/python factory/native/windows/settled-capture-adapter-v3/count1-inputs-r3/adapter-v6-source/produce-input-map-v6.py --template factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native20-r6/count20-input-map-r6.pending.json --metadata-root factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-count20-metadata-r7 --native-root factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native20-r7 --output <fresh-map> --allow-pending
```

After all native archive refs exist, omit `--allow-pending`, then run `produce-inputs-v6.py`, proof-r2 builder, & `run-adapter-v6.py` with exact fresh output paths.

Pure controls:

```sh
python3 test-adapter-v6-source.py
```
