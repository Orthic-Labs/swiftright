# Centered paired verifier

`compare-centered-paired20-v1.py` reads existing Mac full-viewport & Windows centered native Count1 or Count20 evidence. It performs no native launch, compiler action, resampling, masking, normalization, golden promotion, or parity promotion. It decodes source PNGs to RGBA without changing channel values, records each source mode & declared conversion, then compares decoded RGBA bytes exactly beside original PNG file hashes.

Count20 invocation:

```text
python3 compare-centered-paired20-v1.py --expected-count 20 --mac-root <observed-mac20-rN> --windows-root <actual-native-rN/files> --mac-build-receipt <build-rN/receipt.json> --output <paired-count20-report.json>
```

Count1 invocation uses one archive directory or a directory containing only `run-001`:

```text
python3 compare-centered-paired20-v1.py --expected-count 1 --mac-root <observed-count1-rN-or-run-root> --windows-root <actual-native-rN/files> --mac-build-receipt <build-rN/receipt.json> --expected-case-json <case-bearing-manifest.json> --output <paired-count1-report.json>
```

`--expected-case-json` is optional when Mac manifest already carries exact case; it is useful when caller must bind same case context explicitly. Missing Mac case still fails strict join validation.

Run after Windows archive exists:

```sh
python3 factory/pipeline/pilot-delivery-five-v1/root-execution/compare-centered-paired20-v1.py \
  --mac-root factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-full-viewport-v1/observed-mac20-r1 \
  --windows-root factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-centered-capture-count20-r1/actual-native-r1/files \
  --mac-build-receipt factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-full-viewport-v1/build-r1/receipt.json \
  --output factory/pipeline/pilot-delivery-five-v1/root-execution/rectangle-centered-capture-count20-r1/paired-comparison-v1.json
```

Verifier requires one Mac archive or exact `run-001` for Count1, exact `run-001` through `run-020` for Count20, one matching Windows coordinator/batch, exact source/case/witness/runtime/renderer/compile-receipt joins, issued metadata & plan joins, Windows retained-handle lifecycle, DPI/client geometry, PNG row hashes, supervision joins, & original-process joins. Use `--expected-case-json` when binding an external case context; its `case.id` & `case.hash` must exactly match Mac archive case. Each pair records exact paint bytes, decoded RGBA/file hashes, source PNG modes, differing pixel count/bounds, semantic channel status, & lifecycle bounds. Semantic AX/geometry comparison remains pending when Mac archive reports `accessibilityAttempted=false`; performance timing comparison remains pending with raw timing paths retained. `qualified` remains false because output is diagnostic.

Windows compile receipt kind is closed to `factory-rectangle-owned-compile-v1` or `factory-pilot-five-owned-compile-v1`; both retain identical lifecycle, source, case, executable, & hash joins.

Every run also executes six bounded negative controls through `verify_mac_run` against temporary Count1 copies. These controls exercise Mac-side artifact faults only; they make no Windows negative-control claim. Witness, case, runtime, renderer, & client mutations must reject through production joins; one-pixel mutation must survive coherent row sealing then fail exact decoded-RGBA comparison.
