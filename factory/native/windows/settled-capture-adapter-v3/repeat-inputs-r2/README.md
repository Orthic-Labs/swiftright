# Count20 repeat adapter-input producer r2

Source-only successor for `repeat-r2`. It requires twenty explicit run maps, exact repeat-r2 overlay paths/SHA256, standalone prefixed issuer ref, complete producer/runtime/worker closures, & prefixed issuer provenance. It refuses Count1, guessed paths, synthetic fallback, unsafe refs, overwrite, incomplete closure, & historical relabel.

```text
factory/.venv/bin/python factory/native/windows/settled-capture-adapter-v3/repeat-inputs-r2/produce-repeat-inputs-r2.py \
  --archive-root <archive-root> \
  --input-map <explicit-count20-input-map.json> \
  --output <fresh-inputs.json>
```

No native, GUI, compiler, remote, lock, or signing action occurs.
