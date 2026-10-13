# Text Count1 r10 kernel stage

Source-only successor from frozen `capture-count1-r5g-sources`. Donor bytes stay immutable. Fresh plan, case, tuple, compile receipt & serializer receipt are required as measured inputs; no prior Count1 metadata flag substitutes for receipt, source graph, termination proof or helper joins.

Stager validates regular bounded files, exact donor rows, Text final renderer plan, case/tuple identity, successful compile receipt (`exitCode=0`, sealed streams, retained original handle, kernel wait `0`, active job count `0`, owned exit), successor cleanup helper, & one `ExpectedExeHash` per retained-handle cleanup call. It rewrites exact namespace tokens only, reseals staged `source-inputs.json`, emits stage manifest, source graph & optional ZIP. Output namespace must be fresh.

Root command, after transporting exact measured inputs:

```text
factory/.venv/bin/python factory/pipeline/pilot-next-source-v1/text-count1-r10-kernel-stage-v3/stage-text-count1-r10.py --donor-root <frozen-r5g-source-pack> --output-root D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count1-r10\source-pack --source-list <frozen-r5g-source-pack>\stage-manifest.json --plan <fresh-observed-text-plan.json> --case <fresh-observed-text-case.json> --tuple <fresh-observed-text-tuple.json> --compile-receipt <fresh-observed-text-compile-receipt.json> --serializer <fresh-observed-text-serializer-receipt.json> --cleanup-helper <root-v3-cleanup-kernel-authority.ps1> --namespace text-mta-r11-count1-r10 --old-namespace text-mta-r11-count1-r9 --zip-path D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count1-r10\source-pack.zip
```

Pass each measured old-to-new Windows namespace/package token with repeatable `--path-replace OLD=NEW`; only exact tokens are rewritten. External measured compiler, renderer, serializer & receipt paths remain unchanged unless explicitly listed.

Root must archive emitted `sourceGraphSha256`, `stageManifestSha256`, & ZIP hash, then run `test-text-count1-r10-source-controls.py` through bounded supervisor. Native entry remains separate: first run issuer/preflight against staged fresh source graph, then Count1 coordinator. Count20 may consume only explicit `count1-certificate.json` produced by this fresh Count1 run with matching source graph, helper, executable, plan, case, tuple, & terminal proof.

`test-text-count1-r10-source-controls.py` has one admitted baseline & twelve mutations covering count/certificate, executable, native/compiler/lock effects, all three lifecycle budgets, helper hash, row hash & traversal. Controls are source controls only; they do not claim native qualification.
