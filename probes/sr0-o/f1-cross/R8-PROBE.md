# R8 probe: F9 late engine results after the window closes (config `F9-keepalive`)

Settles R8 in CROSS-ALL.md. Not one of the 16 SR0 configs; the existing `F9` config (with its `ignoreEffectsInSteps` and P6) is unchanged.

## What was added (code only, nothing built or run)

- `fixtures/Sources/SliceFixtures/Session/FixtureConfig.swift`: new opt-in flag `--variant keepalive` (`keepAliveAfterClose`, default false; any other `--variant` value exits 2).
- `fixtures/Sources/FixtureApp/FixtureApp.swift`: `applicationShouldTerminateAfterLastWindowClosed` also returns false under `--variant keepalive`. Without the flag the expression is identical to before, so the 16 baselines cannot move.
- `scripts/gen-cross.py`: probe `F9-keepalive` (base F9). Mac launch args `--fixture F9 --variant keepalive`; Windows args stay `--fixture F9` (the exe's in-process script already releases late results after the close). Mac step `close_window` = stdin `close-window` then stdin `release-all` (same step on both sides). Its `stimulus.json` has NO `ignoreEffectsInSteps`, and `adapt-v0.json` has only N1 (no P6).
- No change to F1MacRecord: the step ops are existing stdin ops. After the close the recorder sees no window and records `closed`, as for F9.

## Commands (lead runs; scratch on the internal disk)

```sh
S=$HOME/sr0-scratch/r8; R=/Volumes/D/claude/swiftright/probes/sr0-o
python3 $R/f1-cross/scripts/gen-cross.py          # then git status: only cross/F9-keepalive/ and cross/configs.json may change
swift build -c release --package-path $R/fixtures --scratch-path $S/fx --product FixtureApp
swift build -c release --package-path $R/f1-cross --scratch-path $S/x
(sign F1MacRecord as for earlier tuples, then run only the binaries under $S)
mkdir -p $S/out
sh $R/f1-cross/scripts/record-mac.sh $S/<signed F1MacRecord> $S/fx/release/FixtureApp $S/x/release/F1Assemble $S/out n1 F9-keepalive
```
Repeat with tags n2, n3. Do this when Adrian is not using the Mac GUI.

Windows (tuple 11 FreshOnBridge at `D:\Claude\swiftright\.work\sr0-r11\src`): copy `cross/configs.json` and `cross/F9-keepalive/` to `D:\Claude\swiftright\.work\sr0o-f1\cross\`, then
```sh
FIRST=1 sh $R/f1-cross/scripts/win-cross.sh $S/win 3 F9-keepalive      # default BIN is the tuple 11 path; aborts on another exe
```
Assemble Windows (`F1Assemble win --rec winrec-<tag>.json --side winside-<tag>.json --events events-<tag>.txt --stimulus cross/F9-keepalive/stimulus.json --out ...`) and Mac (record-mac.sh already does) and compare:
```sh
sr0o-trace compare <mac-trace> <win-trace> --adapt $R/f1-cross/cross/F9-keepalive/adapt-v0.json
```

## Reading the result

- Mac also rejects: the Mac events in `close_window` contain `rejected` lines for the late results (the self-test expects 11) and the compare shows no diff in effects/commits for that step. R8 is settled; `ignoreEffectsInSteps` for F9 can be dropped.
- Mac differs: commits or no `rejected` after close, a different rejected count, or other effect lines than Windows. Then Windows does not match the Mac on late results (a product difference to record), or the Mac variant behaves differently from self-test (check against `SelfTest.swift` F9: 11 rejected, 0 commits).
- Expected separate diff: `treeReleased` (P6). The Mac window object may stay retained, so the Mac count can stay 0 while Windows is 1. That is the P6 contract difference, not an R8 result; judge R8 on effects and commits only. P6 is deliberately not allowed here.
- Uncertain until run: whether the stdin driver delivers `release-all` after the window is closed (it should, same task as self-test), and the recorder's post-close focus read on a live process.
