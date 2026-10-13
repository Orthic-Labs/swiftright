# Text Count20 r10 kernel-stage source packet

Source-only successor for Text r9 donor. It keeps frozen r9 bytes untouched, substitutes root-v3 retained-handle cleanup at renderer & UIA roles, binds measured EXE hash, preserves 30 s renderer, 15 s exit, 5 s drain, lock, background, stream, job, & original-handle gates. Count1 certificate is mandatory before any Count20 installer is emitted; packet makes no capture or qualification claim.

`stage-r10-source-graph-v2.py` accepts only explicit `r9-source-files.json` rows, rejects reparse/traversal/collision/oversize paths, streams hashes, bounds JSON, reseals worker contract, source inputs, binding rows, stage rows, & transformed callsites, then emits `r10-source-graph.json`, `r10-reseal-plan.json`, bounded ZIP inventory, ZIP, & installer. Graph records source-list hash/bytes/count & aggregate output bytes. It derives `expectedExeHash` from fresh source-inputs; no PID lookup or guessed EXE hash is accepted.

Root command after transporting measured r9 pack, Count1 certificate, & helper:

```text
python3 stage-r10-source-graph-v2.py --donor-root <r9-source-pack> --output-root D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count20-r10\source-pack --source-list r9-source-files.json --helper-source cleanup-kernel-authority-v3.ps1 --zip-path D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count20-r10\source-pack.zip --installer-path D:\Claude\swiftright\factory\native\windows\.work\text-mta-r11-count20-r10\install-count20-r10.ps1 --old-namespace text-mta-r11-count20-r9 --namespace text-mta-r11-count20-r10
```

Root must review emitted graph, ZIP inventory, source-input hash joins, Count1 certificate, & generated PowerShell before staging. Historical r9 receipts remain immutable.

`test-r10-source-staging-controls.py` calls same `validate_graph` production guard for one baseline & 14 mutations covering Count1 prerequisite, count, EXE/helper hashes, lifecycle budget, source-list/aggregate bytes, donor mutation, native/compiler/lock action state, row hash, traversal, & duplicate row. It does not synthesize native evidence.
