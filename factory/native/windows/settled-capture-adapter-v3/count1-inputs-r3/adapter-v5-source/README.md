# Adapter v5 / telemetry r8 + repeat6

This source successor preserves adapter-v4, r7/r4 scripts, raw receipts, and
proof r2. `derive-v5.py` copies exact proof role refs then derives
`actualSourceHash`, `actualHostExecutableHash`, `actualRendererHash`, and
`rawReceiptHash`; it leaves old outcome bytes untouched.

Source controls:

```sh
python3 test-v5-source.py
python3 test-r8-r5-source.py
python3 test-support-v5.py
```

Controls pass. Derived r7 reader result is blocked only on producer
`rawHashStates`; native parity remains held. New execute-r8/repeat-r5/repeat-r6 profiles pin stream state fields after existing seal/hash completion, preserve Win32 imports, cleanup, & release behavior. Repeat-r6 adds coordinator-copy metadata namespace proof. `r8-pending-input-map-v2.json` predeclares 13 roles, 21 runtime rows, 24 raw rows, fresh metadata r4, & native r8 paths without inventing future hashes.

Runnable successor path (source-only, fresh outputs required):

```sh
factory/.venv/bin/python produce-inputs-v5.py \
  --input-map <explicit-adapter-input-map.json> --archive-root <repo> \
  --output <fresh-inputs-v5.json>
factory/.venv/bin/python run-adapter-v5.py \
  --inputs <fresh-inputs-v5.json> --archive-root <repo> \
  --output <fresh-normalized-v5.json>
# After proof-r2 builder emits proof-bundle:
factory/.venv/bin/python run-adapter-v5.py \
  --inputs <fresh-inputs-v5.json> --archive-root <repo> \
  --proof-bundle <proof-bundle-r2.json> --output <fresh-derived-v5.json>
```

`produce-inputs-v5.py` validates every explicit archive ref, frozen r4-r7/r2-r4 whitelist, successor r8/r5/r6 whitelist, issuer, tuple sidecar, IDs, & optional node epochs. `run-adapter-v5.py` invokes copied adapter-v5 normalization before
proof derivation; raw observations stay byte-identical. `test-composed-v5.py`
exercises positive r7 source admission plus wrong overlay/hash/root/ID/node epoch
faults with zero native actions.

Count20 uses same composed CLI with full explicit 20-run map & repeat-r6 overlay. Repeat-r5 remains preserved historical source; repeat-r6 fixes first-proof metadata namespace joins. Issued metadata must carry `expectedCount: 20`; proof-r2 bundle must
carry 20 captures & 69 archive bindings per production proof builder. Source
shape control:

```sh
factory/.venv/bin/python test-count20-source-v5.py
factory/.venv/bin/python produce-inputs-v5.py \
  --input-map <explicit-count20-adapter-input-map.json> --archive-root <repo> \
  --output <fresh-count20-inputs-v5.json>
factory/.venv/bin/python run-adapter-v5.py \
  --inputs <fresh-count20-inputs-v5.json> --archive-root <repo> \
  --proof-bundle <count20-proof-bundle-r2.json> --output <fresh-count20-derived-v5.json>
```

`test-count20-source-v5.py` passes against preserved 20-run metadata & repeat-r4 source shape; `repeat-r6/test-repeat-r6-source.py` covers repeat-r6 baseline plus namespace/copied-hash/coordinator-hash faults. Native archive remains absent. Full normalization, proof,
reader, & paired comparison remain held until root supplies actual 20-run archive.
