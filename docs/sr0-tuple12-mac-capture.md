# SR0 tuple12 Mac capture prerequisites

Mac cross capture uses signed `F1MacRecord` through external Accessibility (AX), not Screen Recording. Keep native binaries on internal scratch storage; repo JSON/source may remain on `/Volumes/D`.

## Pinned recorder

Existing signed receipt: [sign-receipt.json](../probes/sr0-o/f1-cross/out/signed/sign-receipt.json). Identity is `Developer ID Application: Adrian D'souza (6KLGD3LLKF)`, identifier `com.orthiclabs.swiftright.f1macrecord`, strict signature with timestamp. Current checked binary SHA-256 is `39ae7c9c08e0cb46129281e5f6be336438350794101398c8f6474bbf70cc16a4`; signed bundle tree receipt is `a5b8e07e5ad1f2802f2fcc2f8e9824e89e92ed7b9c260b7c9f8f3988829afeb5`; codesign CDHash is `5be97a95eac4ae045c1af4ea56db3b29f8fc83f3`.

Copy signed recorder app, FixtureApp, and F1Assemble to `$HOME/sr0-scratch/tuple12-cross/bin` while preserving signature; verify with `codesign --verify --deep --strict`. Existing signed recorder `AXIsProcessTrusted()` state must already be true for active Mac user; wrapper never prompts or changes TCC. If trust is false, capture holds/fails closed & records blocker.

## Exact capture

`qualification/tuple12-mac20.sh` invokes same recorder/assembler arguments as `scripts/record-mac.sh`, but checks recorder and assembler exit codes, output presence, signed bundle, internal paths, and all 20 tags per each 16 configs. It never deletes prior output.

```sh
S="$HOME/sr0-scratch/tuple12-cross"
REC="$HOME/Applications/SwiftRight/F1MacRecord.app/Contents/MacOS/F1MacRecord" \
FA="$S/bin/FixtureApp" \
ASM="$S/bin/F1Assemble" \
qualification/tuple12-mac20.sh "$S/out/mac-20"
```

Expected output is 320 Mac raw/event/trace triples. Run only with Mac GUI free. After capture, run offline `scripts/reassemble.sh`/comparator using retained receipts; compare each config against 20 Windows traces recorded with same tuple12 renderer/exe pins. Keep `mac-raw-*`, `mac-ev-*`, `mac-trace-*`, logs, binary hashes, AX grant receipt, and source/stimulus hashes together.

## Windows startup evidence still required

Windows `drive-fixture.ps1` has no AX/TCC dependency. Fixture launch uses fresh ready-marker namespace, preserves original process handle, logs startup & driver-close-ready `WindowMetrics`/`GetClientRect`/DPI/PID/HWND, & applies target identity guards before input, resize, or close. Default FreshOnBridge keeps historical unavailable renderer-ready telemetry; candidate12 opt-in `-NoActivate` passes `--sr0-noactivate --renderer-ready-file`, where same-thread CBT activation veto is installed before `bridge.run` & one `Bridge.onReady` JSON record binds PID, bridge handle, dimensions, scale, & active state. Driver admits input only after marker identity/positive-metrics validation, then applies `SW_SHOWNOACTIVATE`/bottom placement. Before any hidden matrix launch, root must acquire `D:\Claude\desktop.lock`, launch one target, re-read metrics through same process handle, fail if handle changes or target PID/window ownership differs, & release lock in `finally`. Targeted messages remain window-bound; native stderr stays tolerated only with explicit process exit checks.

## Mac20 semantic admission

Archived tuple12 F2 stopped before assembly because recorder raw IDs were F1 (`initial`, `focus_row5`, `type_abc`, `engine_insert_above`, `type_d`) while archived F2 stimulus requires `initial`, `focus_row3`, `type_dash_x_then_move`. Archived F2 `steps-mac.json` SHA-256 `f2dc3a1c89bf35a353cefcd589fb98f38e0ea4227dd30f93029829cd0c87edfd` & `stimulus.json` SHA-256 `73ddbbc5f08292231bd062a8648226e646de4511f11de5e5e93a091e34af94ff` equal current files & `git show 0e201571`; no input transfer drift is evidenced. Signed recorder executable & binary archive are byte-identical at SHA-256 `39ae7c9c08e0cb46129281e5f6be336438350794101398c8f6474bbf70cc16a4`. Its strings contain no `--steps` but contain old hardcoded `focus_row5`, `type_abc`, `engine_insert_above`, `type_d`, `Row 5abc`, & `Row 5abcd`; historical source at `7a91608f` has same fixed F1 sequence, while source at `0e201571` accepts `--steps`. Cause is stale signed recorder binary, not plan drift. `qualification/verify-mac-plan.py` still checks all three files immediately before each native run & records source hashes under each config. `qualification/test_mac_plan_controls.py` passes baseline plus Mac ID, Windows logical-action, & fixture-identity mutation controls. Existing raw evidence remains unchanged; recapture requires newly built, same-team signed recorder with existing AX trust evidence & fresh output namespace.

## F1-only candidate packet

Existing trusted recorder can support fresh F1×20 only: packet `qualification/tuple12-mac-f1-packet.json` pins approved product source `4b1ca6d0fb89963ee20cd5bd7adf8b7c8b9b24e2`, FixtureApp `0c9f380119c780e049c398e993c23dc74a150a43a3c049f0d5aa4154b5b0a904`, F1 plans, recorder identity, bundle, CDHash, & binary. It cannot qualify F2–F9 because signed binary is historical F1-only. Generalized 16-config capture stays held until same-team signing, existing AX trust, & process-level no-prompt proof are sealed.

Root-run command, using fresh internal output:

```sh
REC="$HOME/Applications/SwiftRight/F1MacRecord.app/Contents/MacOS/F1MacRecord" \
FA="$HOME/sr0-scratch/tuple12-f1/bin/FixtureApp" \
ASM="$HOME/sr0-scratch/tuple12-f1/bin/F1Assemble" \
qualification/tuple12-mac-f1-run.sh "$HOME/sr0-scratch/tuple12-f1-$(uuidgen)"
```

After root archives native output, assemble with no native actions:

```sh
python3 qualification/assemble-tuple12-mac-f1.py \
  --repo "$PWD" \
  --root "$HOME/sr0-scratch/<fresh>/runs/F1" \
  --capture-receipt "$HOME/sr0-scratch/<fresh>/capture-start.json" \
  --out "$HOME/sr0-scratch/<fresh>/f1-report.json"
```

Assembler requires exactly 20 fresh raw/events/trace/log sets, joins each F1 step/action/source hash, checks expected row identity/focus/text transitions, verifies FixtureApp & signed-recorder receipts, & emits `qualified` only for F1. Pure controls are `qualification/test_tuple12_mac_f1_controls.py`.

Archived F1 evidence reassembled `qualified` with exactly 20/20 runs. Current assembler SHA-256 `6ec39041689aa2298bdd56cf00d160bbc180837c087fe585500a6a790de49bef`; packet SHA-256 `6bb925f6b626562791e5458c7248eb0af8c46613f5fb4fd5725c93ef38202ea2`; capture-start receipt SHA-256 `5f33f225a8d5581660fe5e06a73fca361b0bac09d6b5a5b3280759779bc13f45`. Add `--packet qualification/tuple12-mac-f1-packet.json` when binding packet explicitly.

## F1 Mac handoff

Ready archived packet is `qualification/tuple12-mac-f1-packet.json` (SHA-256 `6bb925f6b626562791e5458c7248eb0af8c46613f5fb4fd5725c93ef38202ea2`). Complete retained output is `probes/sr0-s/fresh-on-bridge/out/tuple12-mac-preflight-takeover-v1/actual-mac20/F1`; assembler reports `qualified`, exactly 20/20. Product source is commit `0e201571e4320a3b6ccce14313fd2ad67e523904`; FixtureApp is `0c9f380119c780e049c398e993c23dc74a150a43a3c049f0d5aa4154b5b0a904` (1,068,136 bytes); signed F1MacRecord is `39ae7c9c08e0cb46129281e5f6be336438350794101398c8f6474bbf70cc16a4` (146,992 bytes), bundle `a5b8e07e5ad1f2802f2fcc2f8e9824e89e92ed7b9c260b7c9f8f3988829afeb5`, CDHash `5be97a95eac4ae045c1af4ea56db3b29f8fc83f3`; F1Assemble is `ffa92f848386e8d143b42ad7305ca18f8d62f2722b70cce25f10be43d37a96aa` (350,632 bytes). Capture-start receipt is `5f33f225a8d5581660fe5e06a73fca361b0bac09d6b5a5b3280759779bc13f45`; assembler is `6ec39041689aa2298bdd56cf00d160bbc180837c087fe585500a6a790de49bef`.

This packet supports F1 comparison only. F2–F9 require generalized recorder signed by Team `6KLGD3LLKF`, existing AX trust, & sealed process-level no-prompt proof; no capture starts until those joins exist.
