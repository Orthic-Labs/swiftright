# Owned AX projection v1

This is new source successor for observational AX comparison.  Frozen v6/v12
normalizers, raw captures, reader, & protected production gate stay unchanged.

Projection rule is explicit per witness.  Windows root `Window` is dropped only
when its identity is listed in `witness.windows.dropIdentities`; every other
node must be listed or admission holds.  Listed child `Text` is mapped to
canonical `AXStaticText`; all Windows bounds are divided by measured scale
`2.5` using decimal values.  Mac witness stays raw.  Identity, label, value,
actions, role changes, global x/y, size, source, root-child relation, & reader
refs remain observed data.  Raw node identity, role, label, value, actions,
bounds, source, root-child relation, & reader refs remain bound in
`axProjection.before`, `axProjection.after`, & `rawReference`.  Output always
stays `observational-only`, `qualified:false`.

Do not use generic root stripping, role inference, DPI guessing, or dimensions
rounding.  Mac `23x16` versus Windows `26x24` after conversion remains an
observed host-font difference; this source does not normalize it away.

Input schema is `factory-native-count20-r17-ax-projection-input-v1` with
explicit `witness`, `observations`, & optional `proofController`.  Compiler
hash equality is outside semantic projection.  If receipt has equal old/fresh
hashes or `noOpFreshCompile:true`, output records
`proofController.status=external-admission-only`; separate first-proof/native
admission must hold.  Metadata helper alone cannot promote first proof.

Root-only source control commands:

```sh
repo=/Volumes/D/claude/swiftright
py="$repo/factory/.venv/bin/python"
src="$repo/factory/pipeline/paired-padding-r11-v12/ax-projection-v1"
out="$repo/.factory-work/sr1-adapter-v12-r17/ax-projection-v1"
mkdir -p "$out"
"$py" "$src/normalize-ax-projection-v1.py" \
  --input "$out/ax-projection-input-v1.json" \
  --output "$out/ax-projected-v1.json"
"$py" "$src/test-ax-projection-controls-v1.py" \
  --output "$out/ax-projection-controls-v1.json"
```

Before root runs command, materialize input by joining actual Mac witness
capture(s), actual Windows normalized capture(s), explicit root/child identities,
raw Windows value/actions, observed `2.5` scale, & first-proof controller
receipt.  Use repository-relative immutable refs.  No raw-plan relabel is
permitted.  Existing actual fresh first-proof remains blocked while compile
hash is unchanged; fresh source compile + capture are required before any
semantic qualification claim.

Controls preserve changed label, raw value, action, role, size, global bounds,
& identity as observable mismatches.  They reject wrong DPI & unlisted chrome,
verify raw before/after refs, & prove no-op compiler receipt does not gate
semantic projection.  No native, lock, compiler, GUI, or process action occurs.
