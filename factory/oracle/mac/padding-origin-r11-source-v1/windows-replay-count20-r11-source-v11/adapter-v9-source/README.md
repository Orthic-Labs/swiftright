# Fresh r11 Count20 adapter v9

v9 is prospective successor to frozen v8. It admits only fresh r11 tuple/case/source/host values, exact 20 capture/image IDs, provider observations, 13 Windows proof roles, & production reader results. JSON inputs are stat-checked regular non-symlink files ≤2 MiB; archive refs are stat-checked, symlink-component rejected, streamed in 1 MiB chunks, ≤64 MiB each & ≤256 MiB per reader operation. No fixture substitution, relabeling, parity promotion, or golden freeze.

Reader rechecks hash & byte count while streaming each proof-role copy with exclusive writes. Comparator reports `paired-comparison-observed` only when production comparator returns; rejected tuple/case admission is `paired-comparison-blocked`, while parity remains held.

Normalizer resolves frozen v6 by repository ancestor, never ambient working directory. All output parents reject symlink components before creation.

Commands:

```text
produce-input-map-v9.py --template <template> --template-native-root <template-native> --template-metadata-root <template-metadata> --template-overlay-root <template-overlay> --metadata-root <metadata> --native-root <native> --overlay-root <overlay> --issuer-source <issuer> --issued-metadata <issued> --output <map> --repo <repo>
produce-inputs-v9.py --input-map <map> --plan <fresh-count20-plan> --archive-root <archive> --output <inputs>
run-adapter-v9.py --inputs <inputs> --plan <fresh-count20-plan> --archive-root <archive> --proof-bundle <proof-r2> --output <normalized>
run-trusted-reader-v9.py --proof-bundle <proof-r2> --plan <fresh-count20-plan> --archive-root <reader-archive> --output <reader-report>
run-paired-mac20-v9.py --plan <fresh-count20-plan> --mac-refs <fresh-mac-refs> --mac-report <mac-report> --windows-captures <normalized> --reader-report <reader-report> --case <case> --output <paired-report>
test-adapter-v9-controls.py --input-map <inputs-map> --plan <fresh-count20-plan> --archive-root <archive> --proof-bundle <proof-r2> --control-root <control-root> --output <controls>
test-adapter-v9-fixture-controls.py --control-root <fresh-fixture-root> --output <fixture-controls>
```

Controls v2 exercise admitted baseline paths plus real producer/reader rejection paths for wrong ref bytes, wrong tuple/source binding, oversized archive refs, archive escape, absolute paths, symlinked refs, duplicate capture IDs, & missing proof roles. `--control-root` must be fresh; controls create only inside that root. Historic baseline fixtures remain historic & cannot qualify fresh r11 output.

Fixture controls generate 20 synthetic rows, 20 synthetic archive refs, & 13 synthetic proof-role names, then call production validators through baseline, wrong hash/bytes, missing run, duplicate ID, wrong case, & missing-role faults. Output is explicitly fixture-only with `nativeEvidence=false`; it cannot qualify fresh r11 output.

All outputs remain observation-only; native, lock, compiler, remote, & source-mutation effects are zero.
