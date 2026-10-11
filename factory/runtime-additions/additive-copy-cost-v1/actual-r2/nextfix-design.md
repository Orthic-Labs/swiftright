# Additive copy cost: next fix design

`runtime-candidate-sources/SwiftRightRuntime/Graph.swift` remains scratch-only. Current & candidate were compiled from exact source trees & exercised by one bounded headless pair recorded in `run-receipt.json`.

## Verified contract surface

Both processes returned identical values for:

- mutable copied metadata detachment;
- copied `ResolvedNode` equality;
- default font metadata absence;
- custom font family & foreground color;
- Color node;
- filled Circle shape;
- default image sizing absence & resized image sizing presence;
- `SwitchToggleStyle` metadata;
- `.labelsHidden()` on Toggle.

## Candidate change

Keep additive `ResolvedNode` values behind one optional immutable `ResolvedNodeAdditions` reference. Keep `ResolvedStyle` behind one optional immutable `ResolvedStyleStorage` reference. Construct either reference only when at least one value is present. Preserve computed read-only properties, synthesized equality through storage equality, & `Sendable` constraints.

## Next independent review experiment

1. Rebuild current & candidate from pinned trees with same argv, cwd, Swift tool hash, & raw stream capture.
2. Add MemoryLayout output beside parity output for `ResolvedNode`, `ResolvedStyle`, & `Font`.
3. Use matched process order with one fresh current process & one fresh candidate process; retain PIDs, UTC start/end, exit codes, binary hashes, source tree manifests, & raw stdout/stderr.
4. Run existing API workload only for the performance comparison. Keep existing 25-flush profile=nil result unchanged & do not infer causality from one pair.
5. Review API parity plus Equatable behavior before considering integration into runtime source.
