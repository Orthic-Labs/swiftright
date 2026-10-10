# Local reports

Build a local dashboard & one Markdown/HTML report per registered block:

```sh
python -m factory.reports \
  --registry factory/spec/examples/rectangle-v0.1/example-block-registry.json \
  --cases factory/spec/examples/rectangle-v0.1/example-case.json \
  --captures factory/reports/examples/rectangle-synthetic-input/captures.json \
  --verdicts factory/reports/examples/rectangle-synthetic-input/verdicts.json \
  --output-dir factory/reports/examples/rectangle-synthetic
```

`--registry` takes block-registry object with `blocks` array. `--cases`, `--captures`, `--verdicts` & `--gate-receipts` each take an array, one matching artifact object, or an object with the corresponding collection array. `--demand` accepts `{ "blockCapabilities": { "block.id": ["capability"] }, "journeys": [{ "id": "journey.id", "name": "Journey name", "blocks": ["block.id"] }] }`. These are the only accepted JSON shapes. The cases input is fixed manifest & denominator; observed artifacts do not add cases.

Case status `pass` requires a supplied passing F10 receipt from `factory.gate/0.1` bound to case & capture hashes and exact tuple; without it, verdict pass remains blocked. Receipt fields are displayed as supplied evidence. Provide `--gate-receipts` for that input.

The checked-in [Rectangle report](examples/rectangle-synthetic/index.md) uses spec-example data. It is explicitly synthetic, with blocked status; it makes no parity claim. Reports stay local.
