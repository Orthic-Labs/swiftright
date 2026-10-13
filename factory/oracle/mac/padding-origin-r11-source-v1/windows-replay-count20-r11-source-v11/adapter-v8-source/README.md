# Fresh r11 Count20 adapter v8

v8 keeps frozen v6 normalization/proof semantics & adds explicit fresh-plan admission. It rejects absent or non-regular archive refs, byte/hash drift, incomplete measured roles, duplicate `capture/<32 hex>` or `image/<32 hex>` IDs, wrong tuple/case/source/host/renderer joins, providerless rows, fixture substitution, & relabeling. It streams archive hashes in 1 MiB chunks before frozen transforms; no hashes are invented.

Root supplies fresh plan, metadata/native roots, proof bundle, Mac20 refs, case, & reader report. Use stages in order:

```text
produce-input-map-v8.py --template <template> --template-native-root <template-native> --template-metadata-root <template-metadata> --template-overlay-root <template-overlay> --metadata-root <metadata> --native-root <native> --overlay-root <overlay> --issuer-source <issuer> --issued-metadata <issued> --output <map> --repo <repo>
produce-inputs-v8.py --input-map <map> --plan <fresh-count20-plan> --archive-root <archive> --output <inputs>
run-adapter-v8.py --inputs <inputs> --plan <fresh-count20-plan> --archive-root <archive> --proof-bundle <proof-r2> --output <normalized>
run-trusted-reader-v8.py --proof-bundle <proof-r2> --plan <fresh-count20-plan> --archive-root <reader-archive> --output <reader-report>
run-paired-mac20-v8.py --plan <fresh-count20-plan> --mac-refs <fresh-mac-refs> --mac-report <mac-report> --windows-captures <normalized> --reader-report <reader-report> --case <case> --output <paired-report>
```

Reader & comparator emit observation-only diagnostics with native/lock/compiler/remote effects zero; parity, golden, & freeze remain held. `source-map-v8.json` pins every successor & frozen dependency.
