# Prospective Windows replay for fresh Mac r11 case

Existing Windows r7 observations remain immutable. Their typed records, raw files, case hash, candidate tuple, and capture IDs must not be relabeled to new Mac case.

Reference donor is `factory/native/windows/padding-capture-lease-capture-v3/root-actual-prefixed-v1/observed-native20-r7/coordinator-repeat-r1/candidate-tuple.json`; its Windows host hash is `sha256:3d3171b6d6be0447d4c34cd7f8ee5f74332bd1e9eeb24f62f9b1057332d8d10`. This path is evidence input only. Its old case/tuple refs remain bound to r7.

After `prepare-r11-host.py` reports actual compiler output, `materialize-r11-case.py` creates fresh case, manifest, and tuple IDs. Count20 Windows replay may reuse existing Windows executable only when prelaunch source admission joins all of following to that fresh tuple without rewriting any historical record:

- executable bytes and compiler receipt;
- witness source and source manifest bytes;
- renderer, runtime, SDK, toolchain, and acceptance hashes;
- Windows host/witness manifest and producer source closure;
- fresh case ID/hash and tuple ID/hash.

Source admission must use fresh materialized manifest/case paths plus donor candidate tuple as explicit input, then emit an exact source map showing every accepted path and byte hash. A missing row, stale old case hash, or path-only match rejects replay.

Current fresh binding is `swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258.r11.h13bfe5b8fbd9` with canonical case hash `sha256:037c8e81cdc19fa488812bea6ed618aaa4ff8960a9b485fc60fc8c61dcc338de` & tuple `sr1-source-bound-r11-mac20-host-13bfe5b8fbd9-20261011`. Source-only v2 admission against existing r7 executable/compiler/witness bytes returned `fresh-windows-compile-required` in `windows-replay-admission-r1/fresh-windows-source-r11-h13bfe5b8fbd9/replay-admission-v2.json`; actual plan & proof bind old witness manifest/source bytes, so fresh Windows compilation remains required. Historical v1 output remains rejected candidate-only evidence.

Admission must compare exact bytes/hashes, verify fresh metadata references, and emit new capture IDs. A mismatch fails before lock or native window action.

If any executable, witness manifest, compiler envelope, or source closure differs, root must compile a new source-bound Windows host from fresh tuple inputs before Count20. New host, metadata, raw capture, proof, and adapter outputs receive fresh namespace and IDs. Historical r7 files remain separate evidence and remain held for old tuple only.

Mac host hash is unknown until internal-disk host build. The measured `13bfe5...` value in historical inputs is template context only. If capture rebuild reports `HOST_HASH_DRIFT`, stop before AX/native launch, preserve drift receipt, materialize a new prospective case from actual host receipt, then restart with fresh IDs.

Required command order is documented in `COMMANDS.md`. Source-only strict admission is implemented in `windows-replay-admission-r1/admit-windows-replay-v2.py`; controls are in `test-admit-windows-replay-v2.py`; all native execution is root-owned.
