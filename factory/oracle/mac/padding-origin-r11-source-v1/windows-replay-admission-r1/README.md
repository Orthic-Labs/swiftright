# Windows replay admission r1

`admit-windows-replay.py` & its output remain historical v1 candidate-only evidence. Its compiler reference is self-authored & cannot admit reuse.

`admit-windows-replay-v2.py` is source-only strict admission. It requires fresh case/manifest/tuple joins, exact Windows executable/source bytes, actual producer `observation.json`, actual plan/binding, proof archive mandatory roles, runtime receipt/tree, compiler bytes, & trusted-reader rows. It performs no compiler, native, lock, remote, or metadata action.

Use exact actual producer closure:

```sh
PYTHONPATH="$REPO" SWIFTRIGHT_REPO_ROOT="$REPO" "$REPO/factory/.venv/bin/python" \
  "$REPO/factory/oracle/mac/padding-origin-r11-source-v1/windows-replay-admission-r1/admit-windows-replay-v2.py" \
  --case "$FRESH_CASE" --manifest "$FRESH_MANIFEST" --tuple "$FRESH_TUPLE" \
  --donor-tuple "$REPO/factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native20-r7/actual-repeat-r1/candidate-tuple.json" \
  --windows-executable "$WINDOWS_EXE" --witness-manifest "$WINDOWS_WITNESS_MANIFEST" \
  --witness-source "$WINDOWS_WITNESS_SOURCE" --actual-receipt "$ACTUAL_RECEIPT" \
  --actual-plan "$ACTUAL_PLAN" --actual-binding "$ACTUAL_BINDING" \
  --actual-proof-bundle "$ACTUAL_PROOF_BUNDLE" --actual-reader "$ACTUAL_READER" \
  --actual-compiler "$ACTUAL_COMPILER" --actual-runtime-receipt "$ACTUAL_RUNTIME_RECEIPT" \
  --actual-runtime-tree "$ACTUAL_RUNTIME_TREE" --output "$REPLAY_ADMISSION_V2"
```

Exit `0` means exact source/compiler/proof joins permit candidate reuse. Exit `2` writes `fresh-windows-compile-required`; root must compile fresh source-bound Windows host before Count20. Existing r7 records remain immutable.

Current fresh case is `swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9`, canonical hash `sha256:037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de`. v2 against r7 returns exit `2` because actual plan & proof bind old witness manifest/source bytes. This is expected: fresh Windows compilation is required.

`test-admit-windows-replay-v2.py` runs source-only rejects for empty/self-authored receipt, wrong source, changed inputs, executable hash spoof, & missing proof roles.
