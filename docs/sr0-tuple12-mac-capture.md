# SR0 tuple12 Mac capture prerequisites

Mac cross capture uses signed `F1MacRecord` through external Accessibility (AX), not Screen Recording. Keep native binaries on internal scratch storage; repo JSON/source may remain on `/Volumes/D`.

## Pinned recorder

Existing signed receipt: [sign-receipt.json](../probes/sr0-o/f1-cross/out/signed/sign-receipt.json). Identity is `Developer ID Application: Adrian D'souza (6KLGD3LLKF)`, identifier `com.orthiclabs.swiftright.f1macrecord`, strict signature with timestamp. Current checked binary SHA-256 is `39ae7c9c08e0cb46129281e5f6be336438350794101398c8f6474bbf70cc16a4`; signed bundle tree receipt is `a5b8e07e5ad1f2802f2fcc2f8e9824e89e92ed7b9c260b7c9f8f3988829afeb5`.

Copy signed recorder app, FixtureApp, and F1Assemble to `$HOME/sr0-scratch/tuple12-cross/bin` while preserving signature; verify with `codesign --verify --deep --strict`. Existing signed recorder `AXIsProcessTrusted()` state must already be true for active Mac user; wrapper never prompts or changes TCC. If trust is false, capture holds/fails closed & records blocker.

## Exact capture

`qualification/tuple12-mac20.sh` invokes same recorder/assembler arguments as `scripts/record-mac.sh`, but checks recorder and assembler exit codes, output presence, signed bundle, internal paths, and all 20 tags per each 16 configs. It never deletes prior output.

```sh
S="$HOME/sr0-scratch/tuple12-cross"
REC="$S/bin/F1MacRecord.app/Contents/MacOS/F1MacRecord" \
FA="$S/bin/FixtureApp" \
ASM="$S/bin/F1Assemble" \
qualification/tuple12-mac20.sh "$S/out/mac-20"
```

Expected output is 320 Mac raw/event/trace triples. Run only with Mac GUI free. After capture, run offline `scripts/reassemble.sh`/comparator using retained receipts; compare each config against 20 Windows traces recorded with same tuple12 renderer/exe pins. Keep `mac-raw-*`, `mac-ev-*`, `mac-trace-*`, logs, binary hashes, AX grant receipt, and source/stimulus hashes together.

## Windows startup evidence still required

Windows `drive-fixture.ps1` has no AX/TCC dependency. Fixture launch uses fresh ready-marker namespace, preserves original process handle, logs startup & driver-close-ready `WindowMetrics`/`GetClientRect`/DPI/PID/HWND, & applies target identity guards before input, resize, or close. FreshOnBridge currently has no renderer-ready stdout/marker; logs label that event unavailable. Launch requests hidden/no-window creation then applies `SW_SHOWNOACTIVATE`/bottom placement when HWND appears; this is host protection, not proof that pre-HWND activation never occurred. Before any hidden matrix launch, root must acquire `D:\Claude\desktop.lock`, launch one target, re-read metrics through same process handle, fail if handle changes or target PID/window ownership differs, & release lock in `finally`. Targeted messages remain window-bound; native stderr stays tolerated only with explicit process exit checks.

## Mac20 semantic admission

Archived tuple12 F2 stopped before assembly because recorder raw IDs were F1 (`initial`, `focus_row5`, `type_abc`, `engine_insert_above`, `type_d`) while F2 stimulus requires `initial`, `focus_row3`, `type_dash_x_then_move`. Current repository plans for all 16 configs match stimulus IDs, logical actions, & fixture launch identity; this identifies stale or wrong transferred `steps-mac.json` as input drift, not an assembler defect. `qualification/verify-mac-plan.py` now checks all three files immediately before each native run & records source hashes under each config. `qualification/test_mac_plan_controls.py` passes baseline plus Mac ID, Windows logical-action, & fixture-identity mutation controls. Existing raw evidence remains unchanged; re-capture requires fresh output namespace after semantic admission.
