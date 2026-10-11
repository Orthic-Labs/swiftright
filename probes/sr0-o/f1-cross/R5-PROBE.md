# R5 probe: F5 at each platform's own default window size (config `F5-nosize`)

Settles R5 in CROSS-ALL.md. Not one of the 16 SR0 configs; the existing `F5` config (forced 720x560 in `initial`) is byte-identical.

## What was added (code only, nothing built or run)

- `scripts/gen-cross.py`: probe `F5-nosize` (base F5). Its `initial` step has NO resize on either side (settle 2000 ms each); `resize_narrow_release` (360x560) and `resize_wide_again` (720x560) are unchanged. `stimulus.json` carries `"keepLayoutPasses": true`.
- `Sources/F1Assemble/main.swift` + `Events.swift`: opt-in stimulus flag `keepLayoutPasses` (default off, passed to `mapEvents`). Without it the output is unchanged (only the mode a step ENDS in, as `layout-mode <m>`). With it, every non-degenerate `layout` state event (node `layout`, payload `mode`, `width`) also becomes an effect line `layout-pass mode=<m> width=<w>`, in recorded order inside its step, after the `layout-mode` line. Degenerate (width <= 0) passes stay excluded. The fixture emits a pass only when its signature changes (`emitIfChanged`), so repeated identical passes are not listed.
- No fixture or recorder source change.

## Default-size facts from the sources

- Mac fixture: `.defaultSize(width: 480, height: 560)` (`fixtures/Sources/FixtureApp/FixtureApp.swift:41`). The recorder clears saved window-frame restoration before launch (`F1MacRecord/main.swift:104`, CONTRACT C7).
- Windows FreshOnBridge: `bridge.run(title:..., width: 640, height: 480)` (`probes/sr0-s/fresh-on-bridge/Sources/FreshOnBridge/main.swift:111`); measured client 608 wide (F5 cross-evidence).
- Layout breakpoint: `wideThreshold = 560` in the fixture (`fixtures/Sources/SliceFixtures/Screens/F5Screen.swift:9`) and the Windows port (`.../FreshOnBridge/Screens.swift:141`); wide when width >= 560. `conformance/sr0-slice/CONTRACT.md` (F5 row) states NO breakpoint and NO default window sizes, only containment and the C7 frame rule. The 560 value is a fixture fact, not a contract fact.

## Commands (lead runs; scratch on the internal disk)

```sh
S=$HOME/sr0-scratch/r5; R=/Volumes/D/claude/swiftright/probes/sr0-o
python3 $R/f1-cross/scripts/gen-cross.py        # git status: only cross/F5-nosize/ and cross/configs.json may change
swift build -c release --package-path $R/fixtures --scratch-path $S/fx --product FixtureApp
swift build -c release --package-path $R/f1-cross --scratch-path $S/x
mkdir -p $S/out
for t in n1 n2 n3; do
  sh $R/f1-cross/scripts/record-mac.sh $S/rec2/F1MacRecord.app/Contents/MacOS/F1MacRecord $S/fx/release/FixtureApp $S/x/release/F1Assemble $S/out $t F5-nosize
done
```
Mac recording needs the Mac GUI free (Adrian not using it). Windows: copy `cross/configs.json`, `cross/F5-nosize/` and `scripts/*.ps1` to `D:\Claude\swiftright\.work\sr0o-f1\` (configs.json and the config dir under `cross\`, ps1 as for earlier tuples), then
```sh
FIRST=1 sh $R/f1-cross/scripts/win-cross.sh $S/win 3 F5-nosize
```
Assemble each Windows run with `F1Assemble win --rec winrec-<tag>.json --side winside-<tag>.json --events events-<tag>.txt --stimulus cross/F5-nosize/stimulus.json --out <trace>` (record-mac.sh already assembles Mac), then
```sh
sr0o-trace compare <mac-trace> <win-trace> --adapt $R/f1-cross/cross/F5-nosize/adapt-v0.json
```
Also read the `layout-pass` lines of each trace directly; the comparison will show a diff on them by design.

## Reading the result

(a) Start mode. In step `initial` take the first `layout-pass` per platform. Expected from the sources: Mac 480 -> `narrow`; Windows ~608 -> `wide` (>= 560). Judge each against the 560 breakpoint and its own width, not against the other platform. Each platform's first mode must equal "wide iff width >= 560". The contract states no default size, so a different mode at start is not a contract failure by itself.

(b) Settling. Per step, the `layout-pass` sequence must be monotone: widths move from the start width toward the step's target without reversing, with at most one mode change per resize (initial: none expected beyond the launch size; `resize_narrow_release`: wide->narrow once; `resize_wide_again`: narrow->wide once). A mode that flips back and forth, or a pass at a width that neither the start nor the target explains, is a layout defect on that platform. Windows is known to go 608 wide then 328 narrow by itself at launch; check whether that second pass falls in `initial` (settle too short, or a real post-launch resize) or later. Note: the Windows in-process script releases update-1/insert-1 when it first sees narrow, so on Windows those effects may now land in `initial`, not `resize_narrow_release`; an effects diff there is expected and is the script trigger, not a layout finding. Check `layout-mode` end modes agree with the last pass.

(c) Product defect versus platform-defined.
- Product defect: the same width gives different modes (threshold mismatch); a non-monotone settle; a width after a resize step that differs from the commanded DIP width (360/720) by more than the frame rounding; Windows default window size differing from the Mac's in DIP when the product is meant to declare one. Today the Windows host is hard-coded 640x480 outer, the Mac fixture declares 480x560 content; if SR0 intends a shared default size, that is a product-level gap (Windows host), to raise with Sage, not patch here.
- Platform-defined (record, do not fail): the exact default width/height and frame-versus-client offset; the count of intermediate passes while the window settles; a different start mode that follows from a different start width.
- Uncertain until run: whether Windows' launch-time narrow pass is a harness resize or an app behaviour; whether the 2000 ms settle on `initial` covers it.
