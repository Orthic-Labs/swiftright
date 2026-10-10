# F2 block registry

`manifest.json` is maintainer-curated membership for five Round 1 & five Round 2 blocks. `symbols` contains exact module-qualified paths today; selectors may be prefixed with `path:`. Once F1 catalogue is generated, pin each selector as `usr:<USR>`. Builder resolves every selector to one non-hidden catalogue entry and writes only those USRs. It never copies symbol status into block status.

`inventoryStatus` & `progress` are explicit manifest fields (defaulting to `inventory` & `not-started`). `unsupported` must be declared by curation; `blocked` progress requires a reason, RFC3339 `openedAt`, & owner. Semantic dependencies must name blocks in same registry. Any dependency cycle requires one shared `bootstrapGroup`.

Run from repository root:

```sh
python -m factory.registry
```

Override inputs with `--catalogue`, `--manifest`, & `--output`. API: `build_registry(catalogue, manifest=...)`; `validate_registry(artifact)` returns schema & cross-reference errors. Unresolved or ambiguous selectors and invalid dependencies exit with an error; builder does not emit partial output.
