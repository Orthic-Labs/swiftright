# SR0-B text-geometry probe: RESULT

Overall: **FAIL on 2 of 9 check groups** (word navigation count, degenerate-caret bounds). Rect agreement, measurement, physical-px commit, TextPattern presence, selection and DPI all PASS on Windows x64 at 250 % scale (DPI 240) across three widths.

## Design

- Retained tree: one `Committed`/`AxData` state owned by the probe view as plain data. Text is one paragraph (ASCII, Japanese, emoji): `Alpha beta 日本語のテキスト 🙂 gamma delta 漢字 epsilon zeta 🙂🙂 eta theta iota kappa.` (74 chars, 103 UTF-8 bytes).
- Measurement: `WindowTextSystem::shape_text` at proposed width (logical px), synchronous, inside the UI-thread update. Cache keyed by `(width bits, scale bits)`; text and font are constants in the probe. Returns the retained `WrappedLine` handle, per-char cells (line, x0, x1), line starts, line widths, baseline (ascent), size, word starts.
- Line split follows GPUI's `index_for_position` convention (a wrap boundary glyph starts the new line).
- Commit: logical to physical with `window.scale_factor()`, origin at 12 px * scale. Publishes `AxData` and pushes the AccessKit tree with `update_if_active`.
- Paint: GPUI `canvas`, `WrappedLine::paint`, selection quads, caret quad. Paint-time rects are recomputed from the painted handle with the paint-time origin and scale.
- AccessKit: `MultilineTextInput` (label "SR0-B text geometry input", actions Focus, SetValue, SetTextSelection) with one `TextRun` child per visual line: value, `character_lengths` (UTF-8 bytes), `character_positions` and `character_widths` (physical, run-relative), `word_starts`, `bounds` (physical, client-relative), and `text_direction` LeftToRight. Selection via `text_selection`. Every action request is logged, and SetTextSelection is applied and republished.
- Self-check per phase: paint rects vs committed rects vs AX rects, probe hit test vs GPUI `index_for_position`, and caret rect.
- Phases: widths 260, 180, 340, then 260 and 180 again (cache hits). Each phase waits for a UIA driver ack file.
- UIA driver: `System.Windows.Automation` on the Edit element, per-monitor-v2 DPI awareness so UIA reports physical px, client origin from `ClientToScreen`.

Sample ranges (char indices): `Alpha` [0,5), `日本語`, `🙂`, `gamma delta` (wraps at 180 and 260), `kappa.`.

Deviations from the brief: accesskit 0.25.1 names the property `word_starts`, not `word_lengths`. `text_direction` must be set, or accesskit_consumer returns no bounding boxes (found in run 1).

## Commands and request IDs

- Crate: `probes/sr0-b/text-geometry`, lockfile from `probes/sr0-d/render-composition` with only the package name changed. Pins gpui 0.2.2, accesskit 0.25.1, accesskit_windows 0.35.1, raw-window-handle 0.6.2.
- Build 1: `rightkit remote windows cargo build --release --target x86_64-pc-windows-msvc`, request `rr-1791490120626-77b087900d68f4c4`, SUCCEEDED, exit 0, 264.6 s. Text direction not yet set, so no rects.
- Build 2 (fix: `set_text_direction(LeftToRight)` on each TextRun), request `rr-1791491017734-e876cdf0d1bf0e46`, SUCCEEDED, exit 0.
- Pre-submit checks: `win "rightkit list"` before each submit. The only in-flight build was an unrelated `swiftright-render-probe` job, and none of my crate was queued.
- Desktop run: `scripts/driver.ps1` on Windows (copies exe to a new run dir, registers a one-shot task with `LogonType Interactive` for `adrds`, starts it, waits for result.json, then deletes the task). Runs `scripts/run-desktop.ps1`.
  - Run 1 (build 1): `D:\Claude\sr0b-text-geometry\run-20261009-015253`.
  - Run 2 (build 2): `D:\Claude\sr0b-text-geometry\run-20261009-020747`. Evidence copies in `evidence/`.
- Scheduled-task cleanup: run 1's task was still registered after the run because the script's self-unregister did not take effect. I deleted it explicitly. Run 2's task was removed by the driver.

## Run 2 result (verbatim, trimmed; full in `evidence/result.json`)

```
info: dpi=240 scaleFromDpi=2.5 clientOrigin=928,508 windowVisible=True
EXPECT chars=74 words=22 firstword=Alpha
COMMIT phase=Some(0) version=1 width=260 scale=2.5 dpi=240.0 line0_w_phys=549.707 expect_phys=549.707 lines=3 ...
COMMITTED phase=0 r=0 label=Alpha rects=30.00,30.00,101.99,60.00
CARET phase=0 idx=6 commit_rect=142.95,30.00,2.50,60.00 ax_rect=142.95,30.00,0.00,60.00
SELFCHECK phase=0 ... paint_vs_commit_max=0.0000 ax_vs_commit_max=0.0000 hit_mismatch=0 gpui_hit_mismatch=0 pass=true
ACTION Select { anchor: (100, 0), focus: (100, 5) } target=#2
APPLY select anchor=0 focus=5
CACHE hits=2 misses=3 measure_calls=5
DONE
UIA phase0 r=0 Alpha: uia=30.00,30.00,101.00,60.00  paint=30.00,30.00,101.99,60.00  ax=30.00,30.00,101.99,60.00
UIA caret phase0: uia_selection_count=1 uia_text='' uia_rect=∞,∞,-∞,-∞ (empty)
```

## PASS/FAIL table

| Check | Result | Evidence |
|---|---|---|
| Measurement is synchronous | PASS | 5 MEASURE lines, all `sync=true`, all before COMMIT |
| Measurement is cached | PASS | `CACHE hits=2 misses=3`, phases 3 and 4 hit |
| Physical-px commit (logical x scale_factor 2.5) | PASS | line0 phys 549.707 / 445.273 / 832.852 equal logical x 2.5 at each width |
| DPI recorded | PASS | `GetDpiForWindow`=240 = app scale 2.5 x 96 |
| TextPattern present | PASS | Edit supports `TextPatternIdentifiers.Pattern` (and ValuePattern) |
| Document text equals TEXT | PASS | 77 UTF-16 units both sides, exact match |
| Character navigation | PASS | 74 char moves = 74 expected; first char `A` (all phases) |
| Word navigation | **FAIL** | UIA 23 moves vs 22 expected; first word `Alpha ` matches (all phases) |
| Selection via `TextPatternRange.Select` | PASS | ACTION SetTextSelection logged, applied (0..5), UIA text `Alpha` |
| Selection persists across width change | PASS | phases 1 to 4 read `Alpha` |
| Caret bounds (degenerate selection) | **FAIL** | UIA caret selection exists (count 1), `GetBoundingRectangles` empty; app caret 142.95,30.00 |
| Rect agreement, UIA vs paint, width 260 | PASS | max err 0.99 px (UIA rounds 101.99 to 101.00) |
| Rect agreement, UIA vs paint, width 180 | PASS | max err 0.99 px |
| Rect agreement, UIA vs paint, width 340 | PASS | max err 0.99 px |
| Rect agreement, UIA vs AX (all widths) | PASS | max err 0.99 px |
| App self-check: paint vs commit, AX vs commit, hit tests | PASS | max err 0.0000; probe hit and GPUI hit both 100% at each width |

## Open items and caveats

- **Word count.** The probe expected `word_starts > 0` (22) moves. UIA gives 23. My inference is that the last move lands at end-of-document. Not verified. Character moves give exactly N, which fits a move to end. The check formula needs confirming before the word-navigation FAIL counts against the contract.
- **Caret rect.** For a degenerate range, accesskit_windows `GetBoundingRectangles` returned no rect. The degenerate range's bounding-box path in accesskit_consumer 0.39.1 is the likely cause, but I did not read the rest of `bounding_boxes` to confirm it. The contract's "caret bounds" need another mechanism (for example a one-character range) or a SetTextSelection-based caret check. The app's own caret rect is recorded.
- **Paint is not pixel-captured.** Paint rects are the GPUI-shaped cell geometry, mapped with the paint-time origin and scale, read back from the same painted handle. They are not screenshot pixels. The optical endpoint (CONTRACT §5) remains open.
- **Self-unregister failure.** The runner's `finally` did not remove its own task in run 1. Remove this task by name on each run until fixed.
- **Single host.** One Windows x64 Dell at 250 % DPI. No 100 %/150 % comparison, no arm64 host, no Narrator or NVDA. No IME.
- **Probe-only.** Not frozen ABI. Measurement cache keys are (width, scale) only, because text and font are constant in the probe.

## 2026-10-09 follow-up: caret and word-navigation FAILs resolved (run 3)

Run 3 used the build-2 exe unchanged (no Rust edits, so no build 3). Only `scripts/run-desktop.ps1` changed. Result: **PASS, 0 of 9 check groups failing** (`evidence/result-run3.json`, `evidence/app-run3.log`, run dir `D:\Claude\sr0b-text-geometry\run-20261009-023606`). The scheduled task was removed (`task_still_registered=False`).

### (2) Word navigation: 23 moves vs 22. Expectation error, not our word data.

- Word starts from our rule (same as `src/main.rs:83-97`, `word_starts_of`), including index 0: 23 stops. Excluding index 0: 22 interior starts. Recounted independently in Python.
- The extra UIA move is the end-of-document stop. `accesskit_consumer` 0.39.1 `src/text.rs` `forward_to_word_start` falls through to `self.document_end()` after the last word start (text.rs, end of fn, the `for node in pos.node.following_text_runs` loop then `self.document_end()`).
- Consistency: the character-unit check already counts 74 moves for 74 characters, which also lands at document end. The Microsoft `ITextRangeProvider::Move` page describes moving by boundaries but does not state the end-of-document stop explicitly. So the expectation change rests on AccessKit's implemented boundary model, not on a quoted spec sentence. Treat it as provisional.
- Changed check: moves must equal 23 AND each stop must be the expected code point (or '' at end). The run shows `sequence_mismatches=[]` in all five phases. This confirms the `word_starts` data is consumed correctly in order.

### (1) Degenerate caret rect: test-side fault plus a spec fact.

- Microsoft `ITextRangeProvider::GetBoundingRectangles` (learn.microsoft.com/en-us/windows/win32/api/uiautomationcore/nf-uiautomationcore-itextrangeprovider-getboundingrectangles), pRetVal description: "An empty array for a degenerate range." So an empty result for the degenerate caret is spec-conformant. The old expectation (a rect from a degenerate range) was wrong.
- The old FAIL value `uia_rect=∞,∞,-∞,-∞` is System.Windows.Rect.Empty. The probe's `Uia-Rects` treated it as a real rect. That was a harness bug, now fixed with `if ($rc.IsEmpty) { continue }`.
- accesskit_windows 0.35.1 `src/text.rs:494-503` returns a null SAFEARRAY when `bounding_boxes()` is empty. The observed empty result therefore means the consumer returned no box for our degenerate caret. That contradicts the consumer's own comment at `accesskit_consumer` `src/text.rs:740-745` ("there will always be at least one box, even if it's zero-width, as it is for a degenerate range"). I did not find which precondition fails by source reading. Our tree sets bounds, positions, widths, and text_direction on every TextRun (`src/main.rs:418-424`). Record as an upstream gap: consumer comment vs observed empty, not reproduced in a unit test.
- Caret location workaround, passed in run 3: the one-character range [6,7) returns rect x=142.00 vs app caret x=142.95, y=30, h=60 (within 1 px). Its text is 'b'. This uses only spec-defined non-degenerate ranges.
- Upstream gap: accesskit_windows 0.35.1 implements no `ITextProvider2` (TextPattern2, `GetCaretRange`). Grep of `src/` finds nothing, and the pattern table in `src/node.rs:1432` lists only `ITextProvider`. So the UIA caret-range route is unavailable in this version.

### Checks changed (scripts/run-desktop.ps1 only)

- `Uia-Rects` skips `Rect.Empty`.
- Word check: stop count plus per-stop character sequence. Code points split with `Get-Cps` (UIA counts 74 code points, not 77 UTF-16 units). The rule is replicated in `Word-Stops`.
- Caret: (a) degenerate range returns empty rects (spec); (b) one-character range matches app caret within 1 px.

### Remaining caveats

- Narrator and NVDA were not run. Whether Narrator uses the one-character range or the TextPattern2 caret is unverified.
- The end-of-document word stop is supported by AccessKit's boundary model and consistent with the char check, but not by an explicit UIA spec sentence I could find.
- Single host, unchanged from the earlier run.
- Build iterations: 0 of 3 used. No Rust change was needed.

## Primary verification (2026-10-09)

Fetched Microsoft docs confirm the degenerate-range expectation was wrong: Win32 `ITextRangeProvider::GetBoundingRectangles` returns "An empty array for a degenerate range"; .NET `TextPatternRange.GetBoundingRectangles` says the same. Caret geometry therefore comes from a one-character range on both platforms (matches the Mac AX rule in CONTRACT §5). No Microsoft page fetched states end-of-document behaviour for word moves; the 23-stop result stays provisional, cross-checked stop by stop against our word starts. Narrator/NVDA caret tracking remains untested and is required by the Windows accessibility gate.

## Degenerate caret range: check restored (run pending)

Source reading of `accesskit_consumer` 0.39.1 and `accesskit_windows` 0.35.1 (`GetBoundingRectangles`) shows the provider returns one zero-width box for a degenerate range (the consumer's own test at `text.rs` ~2195 asserts `x0 == x1`, full line height). The earlier FAIL value `∞,∞,-∞,-∞` is a single `Rect.Empty`: a returned element, not an empty array. My inference is that the managed `TextPatternRange` wrapper maps a zero-width rect to `Rect.Empty`; not verified. If so, the provider already satisfies the requirement and the run-3 "empty array" reading above was wrong. No renderer change was made, because there is nothing in the tree data that would change this behaviour.

`scripts/run-desktop.ps1` now checks the degenerate range (and the selection range) through `UiaCoreApi.RawTextRange_GetBoundingRectangles`, which returns the provider's raw `double[]`: at least one rect, x/y/height within 1 px of the app caret, width from 0 to the caret thickness. The one-character-range check is kept. If the raw array is empty, the check fails and the detail line shows `raw_degenerate=none`, which would point at accesskit_windows or UIA core instead. Not run yet (needs desktop).
