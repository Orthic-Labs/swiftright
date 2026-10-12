# Pilot-next Rectangle source packet

Source-only packet for `swiftui.shapes.rectangle-fill.pilot-next`. It binds `Rectangle().fill(Color.red)` at 40x20 with light color scheme to current runtime source commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b` & tuple-11 renderer `sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`. It contains no measured host, compiler, window, or parity result.

`recipe.json`, `witness.swift`, `case-inputs.json`, `source-pins.json`, & `capture-plan.json` are prospective inputs. `case-inputs.json` is not a canonical measured case until root supplies measured tuple values; never type host hashes.

## Mac root command sequence

Root must run on internal disk with factory venv & fresh namespace. Keep repository as source/evidence checkout; do not run compiler or native capture from `/Volumes/D`.

```sh
REPO=/Volumes/D/claude/swiftright
PYTHON=$REPO/factory/.venv/bin/python
PACKET=$REPO/factory/pipeline/pilot-next-source-v1
R11=$REPO/factory/oracle/mac/padding-origin-r11-source-v1
CAPTURE=$PACKET/mac-capture-same-group-v1
MAC_ROOT=/Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/pilot-next-rectangle-<fresh>
mkdir -p "$MAC_ROOT"
cd "$REPO"
# Build source-bound Mac host before tuple materialization; this returns measured Mac host hash only.
SWIFTRIGHT_REPO_ROOT="$REPO" PYTHONPATH="$REPO" "$PYTHON" "$PACKET/build_rectangle_host.py" \
  --output "$MAC_ROOT/mac-prebuild"
MAC_HASH=$($PYTHON -c 'import json,sys; print(json.load(open(sys.argv[1]))["binary"]["sha256"])' "$MAC_ROOT/mac-prebuild/host-build-r1.json")
# Root supplies measured Windows host hash. Write both measured hashes into measured-tuple.json.
# Materialize canonical case; no placeholder tuple is accepted.
SWIFTRIGHT_REPO_ROOT="$REPO" PYTHONPATH="$REPO" "$PYTHON" "$PACKET/materialize-rectangle-case.py" \
  --tuple "$MAC_ROOT/measured-tuple.json" --output "$MAC_ROOT/generated"
CASE=$(printf '%s\n' "$MAC_ROOT/generated/cases"/*.json)
# Rebuild same source after tuple binding & require exact measured hash.
SWIFTRIGHT_REPO_ROOT="$REPO" PYTHONPATH="$REPO" "$PYTHON" "$PACKET/prepare-pilot-next-host.py" \
  --manifest "$MAC_ROOT/generated/manifest.json" --case "$CASE" --output "$MAC_ROOT/host" \
  --expected-binary-hash "$MAC_HASH"
HOST_HASH=$($PYTHON -c 'import json,sys; print(json.load(open(sys.argv[1]))["binary"]["sha256"])' "$MAC_ROOT/host/host-build-r1.json")
# same-group successor rebuilds host & refuses drift before AX/native action.
SWIFTRIGHT_REPO_ROOT="$REPO" PYTHONPATH="$REPO" "$PYTHON" "$CAPTURE/capture_origin_rectangle_r1.py" \
  --manifest "$MAC_ROOT/generated/manifest.json" \
  --case-root "$MAC_ROOT/generated/cases" --scratch "$MAC_ROOT/capture-scratch" \
  --output "$MAC_ROOT/evidence" --runs 20 --expected-host-hash "$HOST_HASH"
```

The final capture invocation must pass host receipt's measured `sha256:<64 hex>` value, not receipt path. `capture_origin_r11.py` must complete signed-recorder trust preflight, fresh AX preflight, owned-child drain, & no-prompt checks before runs. Any drift stays held with its receipt.

## Offline normalization successor

When capture completes but frozen producer normalization stops, use `normalize_rectangle_runs_r1.py` with original `summary.json`, manifest, & case. It requires exactly 20 ordered instrumented raw hashes, distinct owner PIDs, source/host/tuple joins, & explicit `channels.geometry`; it writes only fresh `derived-normalized/` captures & `derived-summary.json`, preserving raw runs, original summary, & any Windows plan.

```sh
SWIFTRIGHT_REPO_ROOT="$REPO" PYTHONPATH="$REPO" "$PYTHON" "$PACKET/normalize_rectangle_runs_r1.py" \
  --summary "$RAW_CASE/summary.json" --manifest "$MANIFEST" --case "$CASE_JSON" \
  --output "$MAC_ROOT/derived-normalized"
```

`build_rectangle_host.py` keeps compiler child in parent process group, streams stdout/stderr to sealed files, enforces timeout, & records exit, timeout, bytes, hashes, & `startNewSession:false`. Successor `mac-capture-same-group-v1/capture_origin_rectangle_r1.py` copies frozen protocol, uses local `CaptureHost.swift` with `orderBack(nil)`, keeps compiler/AX/host children in parent process group, streams command logs to bounded files, & terminates only retained child handles. Frozen r11 remains historical. Prebuild alone never admits capture.

## Windows workload memory envelope

`windows-task-memory-v1/run-workload-memory-v1.ps1` schedules `task-workload-memory-v1.ps1`. Wrapper attaches current PowerShell process to one job before invoking frozen `task-workload.ps1`; WorkloadWin & sampler inherit `JOB_OBJECT_LIMIT_JOB_MEMORY` (`0x200`, exactly 1 GiB). It rejects flags or active-process drift, records `memory-receipt.json`, & leaves `KILL_ON_JOB_CLOSE` disabled. Root invokes with explicit pinned paths:

```powershell
& .\run-workload-memory-v1.ps1 -ControlRoot $frozenControlRoot `
  -TaskWrapperPath .\task-workload-memory-v1.ps1 `
  -FrozenTaskPath "$frozenControlRoot\task-workload.ps1" `
  -MemoryHelperPath .\Sr0OwnedJobProcess.cs `
  -MemoryReceiptPath "$runRoot\memory-receipt.json"
```

## Windows source admission & replay

Root stages only explicit rows listed in `source-pins.json` into fresh ignored staging. It replaces staged witness source with this packet's `witness.swift`, recomputes every byte hash, & records actual compiler receipt. It then admits fresh Mac case/tuple/manifest against runtime receipt/tree, Windows host manifest, renderer hash, compiler bytes, worker/runtime/renderer source, & acceptance config. Existing executable reuse is allowed only if every join is byte-equal; otherwise root compiles fresh internal-disk Windows host. Count20 starts only after prelaunch admission, exact capture ID/image pairing, retained worker/renderer handles, terminal task proof, lock release, & 1GiB self-job receipt pass.

Required root-side command inputs are the generated `case.json`, manifest, tuple, compiler receipt, staged package map, runtime receipt/tree, renderer receipt, host manifest, capture issuer receipt, coordinator/dispatch/capture receipts, worker/renderer raw proofs, stdout/stderr sealed hashes, & cleanup/quiescence receipts. No path-only or template substitution satisfies admission.

## Display admission compatibility

Display envelope may consume this candidate only when stage/build metadata has exact fresh case ID/hash, recipe hash, witness hash, runtime commit/tree hash, renderer hash above, measured compiler receipt, Windows executable/source closure, host manifest, capture issuer metadata, 20 raw run joins, worker/renderer terminal proofs, & paired Mac20 source tuple. Display metadata from another case, tuple, host, or runtime stays separate. A successful compile, layout observation, or stale provider result alone does not admit capture or parity.

Current stale provider limitations remain explicit: Rectangle fill is source-bound here, while native/provider semantics still require actual runtime evidence. No native completion or paired parity claim is made by this packet.
