# Measured factory pipeline

Run from repository root with `factory/.venv/bin/python -m factory.pipeline`.
Commands preserve current `inputs/`, `cases/`, `manifests/` & `probes/`; output must be fresh.
Role: Alchemist bounded transformation. F10 owns signoff. No automatic goldens or promotion.
Future `prepare` case timestamps default to recipe `createdAt`; identical inputs/seed reproduce full case hashes. `--snapshot-created-at` can pin an explicit future snapshot timestamp.
Prepared batches remain candidates, with `acceptedDenominator:false`; bound baseline recipe seeds must match requested seed. F10 independently expands reviewed config baseline profiles before accepting any denominator. Existing observational config has no protected baseline profile.
`collect`, `report` & `gate-evidence` accept repeatable `--exclude-capture-dir` for explicitly superseded case directories inside selected roots; excluded artifact refs remain archived in `supersededArchives`. New-source replacements keep identical case IDs without importing stale source runs.

```sh
factory/.venv/bin/python -m factory.pipeline prepare --output factory/pipeline/new-expansion
factory/.venv/bin/python -m factory.pipeline collect --evidence-root factory/native/macos/evidence/20261010-primary-five-r3 --output factory/pipeline/new-collection
factory/.venv/bin/python -m factory.pipeline report --evidence-root factory/native/macos/evidence/20261010-primary-five-r3 --evidence-root factory/native/macos/evidence/20261010-primary-next-five --evidence-root factory/native/macos/evidence/20261010-corrected-primary --exclude-capture-dir factory/native/macos/evidence/20261010-primary-five-r3/swiftui.custom-layout.recipe_case_b30ed0b185e8cb29 --exclude-capture-dir factory/native/macos/evidence/20261010-primary-next-five/swiftui.preference-key.recipe_case_66b6b44aaff817d6 --compile-summary factory/native/windows/primary-typecheck-summary-import-corrected-20261010.json --output factory/pipeline/new-pilot
factory/.venv/bin/python -m factory.pipeline gate --evidence-root factory/native/macos/evidence/20261010-primary-five-r3 --output factory/pipeline/new-gate
factory/.venv/bin/python -m factory.pipeline gate-evidence --plan factory/pipeline/gate-pilot/gate-results.json --evidence-root factory/native/macos/evidence/20261010-primary-five-r3 --evidence-root factory/native/macos/evidence/20261010-primary-next-five --evidence-root factory/native/macos/evidence/20261010-gate-seeded --output factory/pipeline/new-gate-evidence
factory/.venv/bin/python -m factory.pipeline queue --output factory/pipeline/new-queue
factory/.venv/bin/python -m factory.pipeline font-addendum --evidence-root factory/native/macos/evidence/20261010-tinos-pilot --output factory/pipeline/new-font-addendum
factory/.venv/bin/python -m unittest factory.pipeline.test_workflow factory.pipeline.test_windows_archive
```

F1–F3 catalogue/registry/recipes retain existing measured evidence. `prepare` binds measured tuple/config & expands recipes, then calls F4 generator. F5/F7 native runners receive generated manifests; F6 staged build evidence stays distinct from native replay. `collect` recursively loads only explicitly selected roots, validates schema, actual case hashes, exact tuples & raw PNG hashes, then rejects synthetic captures, repeated IDs & stale refs. Rejected records retain archive refs & diagnostics; missing runs never become captures.

`report` calls F8 `compare_case` & F9 `build_report` using real registry & shell demand. Fixed81case denominator stays intact; pilot summary accounts for all10primaries, native archive refs, actual Windows compile failures & diagnostics. Plain/offscreen/compositor/background images remain unqualified.

`gate` evaluates actual F10 with preserved complete recipe batches. Runtime chooses & records fresh64bitseed, emits ten distinct seed cases/probes & executable Mac20run/Windowsbuild commands. `--test-seed` exists solely for deterministic tests. Seeded cases require own new Mac20repeat qualification & Windows replay; baseline captures never satisfy seed refs. Missing trusted seeded-capture, semantic, timing, fault-control or merged-rebuild callbacks keeps receipt blocked. Gate command exits3 for held result.

`queue` uses F11–F12 `QueueStore` with real registry bootstrap/dependency rules. Tickets remain staged unit mode, contributor activation held until plan-round3exit. Dependency-held receipts stay in queue state. Commands emit no fake capture, gatepass, callback, golden or promotion.

`gate-evidence` reuses recorded runtime seed & exact frozen case artifact hashes after native capture completes. It independently verifies deterministic seed inputs, recipe/tuple refs & generated manifest hashes, then reevaluates F10 with baseline & own seeded captures. New receipt retains original seed; no duplicate seed batch is chosen. Raw Mac instrumented-source & canonical clock correlations are checked during collection. Primary compile records bind canonical case, tuple, actual source & stderr archive hashes; corrected source lineage preserves original/source-superseded refs.

Windows normalized layout: `run-NN/capture.json` with adjacent `Witness.swift`, `plan.json`, original `native-observation.json`, `native.uia.json`, `native.screen.png`, `host.stdout.txt` & every receipt-bound raw file. Collector checks actual source/plan/case, receipt run index, source/executable/renderer hashes, tuple bindings, raw receipt/clock/UIA hashes & every receipt file hash. Files cannot escape run directory or repeat. Raw qualification flags must match capture conditions. Unit Windows fixtures carry explicit synthetic markers; full collector rejects them.

`font-addendum` collects explicitly selected Tinos candidate roots separately. It binds raw font/license bytes, private DirectWrite resource identity & actual Swift API typecheck source/diagnostic bytes. These candidate captures never enlarge fixed81case manifest or grant parity.
