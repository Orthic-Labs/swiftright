# SR1 mutation calibration

Proves that every deciding gate of the SR1 lean loop rejects deliberately seeded faults and still passes near-misses inside its tolerance. This is the queue-open condition in
`docs/sr1-plan.md` ("the gate catches every seeded mutation"). Results: `factory/pipeline/mutation-calibration/results.json` and `RESULTS.md`.

## Method

- **Offline, on existing evidence.** `fixtures.py` copies run 01 of one committed or rerun evidence directory per base (PNG pair, UIA/AX dumps, list dump, host and Mac logs, clock frames) plus the case's own
  `pair.json`, unchanged, into `factory/pipeline/mutation-calibration/fixtures/<base>/` (2.2 MB, no PNG over 100 KB). Nothing is captured; no Windows, Sandbox or Dell is touched.
- **Real code path.** `core.py` stages a fixture in a scratch directory, applies one mutation to the Windows side (capture, UIA JSON or host log) and runs
  `python3 factory/tools/pair.py <case> --recompare <run>` as a subprocess: the same compare-only entry point, gate dispatch (`semantic_gate`, `semantic_decides`) and report generators the pipeline uses.
  `factory/pipeline/consolidation/run_all.py` records that exit status as the case verdict. Exit 0 = the case passes.
- **Kinds.** `catch`: the mutated run must FAIL. `near`: a near-miss placed exactly at or just inside the named tolerance; the run must PASS (otherwise the gate is over-strict). `probe`: a sensitivity sweep, reported only.
  A `catch` that passes is a MISS; if a decision or the comparator's own contract says the property is not gated, the row carries that citation (`design`) and RESULTS.md lists it separately.
- **Baseline first.** Before the summary is written every unmutated fixture must pass; otherwise the run aborts.
- **No thresholds or comparator logic are changed.** Tolerance-edge mutations are derived from each case's own `pair.json` values (for example the label-ink shift that puts the colour difference at exactly 40 and 41).
  Helpers import `pair.edge_band` and the comparators' measuring functions only to pick which pixel to edit; the verdict always comes from the subprocess.
- `s_multirun.py` repeats 20 of the mutations in run 3 of 3 only (runs 1 and 2 untouched), to show a single bad run is not averaged away.

## Run

```
python3 factory/tools/mutation-calibration/fixtures.py     # only to rebuild the fixtures from their sources (read-only on them)
python3 factory/tools/mutation-calibration/calibrate.py    # all mutations -> results.json and RESULTS.md
python3 factory/tools/mutation-calibration/calibrate.py --gate clock --only extent   # a subset (prints, writes nothing)
python3 factory/tools/mutation-calibration/make_readme.py  # regenerate this file
```
A few minutes (about 360 subprocess runs). Python with Pillow (`factory/requirements.txt`); no other dependency.

## Files

`fixtures.py` base evidence table and copier; `core.py` staging and verdict; `mutlib.py` image and JSON helpers; `s_pixel.py`, `s_text.py`, `s_control.py`, `s_semantic.py` (semantic and list),
`s_clock.py`, `s_image.py`, `s_textorigin.py`, `s_multirun.py` the mutation suites; `calibrate.py` runner; `report.py` summary and RESULTS.md.

## Gates

| Gate | Comparator | What decides |
|---|---|---|

| pixel | `factory/tools/pair.py compare() + edge_gate()` | exact, edge-aa<=32 band (decision 5), hazeTolerance 3 (D9), named exclusions (decision 2), capture size, half-pixel tie cases (blocks-6-10/pixel-ties) |
| text | `factory/tools/pair_text_report.py` | glyph-region ink bbox within 1 px, exact outside the region (decision 2, block 4) |
| text-colour | `factory/tools/pair_textcolour_report.py` | strongest ink colour within 24/255 per channel (decisions 2, 10, 11; A1; D1) |
| button | `factory/tools/pair_button_report.py` | push Button height/y, caps, flat bands, label centre and ink (decision 11; A1-A3) |
| control | `factory/tools/pair_control_report.py` | labelled Toggle control size/y/edges, label centre (1 px), row leading x, label first ink x, label-to-control gap (decisions 7, 8, 16) |
| list | `factory/tools/pair_list_report.py` | List rows, text, order, selection, frames within 1 px, label ink (A6-A9) |
| semantic | `factory/tools/pair_semantic_report.py` | UIA vs AX: role, name, value, toggle, enabled, dialogs, order, count, static default button from the host log (F3; B4-B6, D4-D7, A4; decision 17) |
| ime | `factory/tools/pair_ime_report.py` | IME marked range, selected range and composed text per step, Windows HOST_FIELD log vs Mac MAC_FACT log (decision 15) |
| clock | `factory/tools/pair_clock_report.py` | F1 manual clock: extent, leading and trailing edge position (C2 1 px; spring 2 px; decision 18), pixels outside strips, progress (C1-C10) |
| image | `factory/tools/pair_image_report.py` | Image(systemName:) frame, ink bbox, tint (decision 3) |
| text-origin | `factory/tools/pair_textorigin_report.py` | TextField first ink x and y, baseline, selection colour and start, caret (decisions 12, 13, 14) |
| multi-run | `factory/tools/pair.py --recompare over N runs` | the case verdict is every run passing: one bad run of three must fail |

## Every mutation

Base = fixture id (see `fixtures.py` for its case and run). All edits are to the Windows side of run 01 unless the description says otherwise.


### pixel

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| px-exact | `shift-1px` | catch | 1 px shift of the whole picture |
| px-exact | `shift-element-1px` | catch | 1 px shift of one element layer |
| px-exact | `colour+1` | catch | colour shift of one level (the gate has no tolerance here) |
| px-exact | `missing-element` | catch | a missing element |
| px-exact | `size-1px` | catch | an element one pixel narrower |
| px-exact | `corner-radius` | catch | a wrong corner radius on a rectangle |
| px-ties | `tie-shift-1px` | catch | a tie resolved the other way: one element one pixel off |
| px-ties | `tie-shift-1px-red` | catch | a tie resolved the other way, vertical |
| px-ties | `missing-element` | catch | a missing element |
| px-edge | `shift-1px` | catch | 1 px shift |
| px-edge | `radius+10px` | catch | wrong corner radius (4 pt more) |
| px-edge | `radius-8px` | catch | wrong corner radius (3 pt less) |
| px-edge | `stroke+2.5px` | catch | wrong stroke width (3 pt instead of 2) |
| px-edge | `stroke-2.5px` | catch | wrong stroke width (1 pt instead of 2) |
| px-edge | `missing-element` | catch | a missing element |
| px-edge | `band+33` | catch | one AA-edge pixel 33 levels off (beyond edge-aa 32) |
| px-edge | `band+32` | near | one AA-edge pixel exactly 32 levels off (edge-aa<=32 must pass) |
| px-edge | `flat+1` | catch | one flat pixel 1 level off (out-of-band tolerance is 0 without hazeTolerance) |
| px-edge | `probe-radius+0.25px` | probe | sensitivity: corner radius +0.25 px |
| px-edge | `probe-radius+0.5px` | probe | sensitivity: corner radius +0.5 px |
| px-edge | `probe-radius+1.0px` | probe | sensitivity: corner radius +1.0 px |
| px-edge | `probe-radius+2.0px` | probe | sensitivity: corner radius +2.0 px |
| px-edge | `probe-stroke+0.25px` | probe | sensitivity: stroke width +0.25 px |
| px-edge | `probe-stroke+0.5px` | probe | sensitivity: stroke width +0.5 px |
| px-edge | `probe-stroke+1.0px` | probe | sensitivity: stroke width +1.0 px |
| px-fractional | `shift-1px` | catch | 1 px shift |
| px-fractional | `band+33` | catch | one AA-edge pixel 33 levels off |
| px-fractional | `band+32` | near | one AA-edge pixel exactly 32 levels off |
| px-fractional | `flat+1` | catch | one flat pixel 1 level off |
| px-haze | `haze+4` | catch | haze level 4 (above the named 3) |
| px-haze | `haze+3` | near | haze level exactly 3 (within hazeTolerance 3, must pass) |
| px-haze | `haze+2` | near | haze level 2 |
| px-haze | `haze+3-without-tolerance` | catch | level 3 in a case that does not name hazeTolerance |
| px-haze | `band+33` | catch | in-band 33 levels (haze does not widen the AA band) |
| px-haze | `band+32` | near | in-band exactly 32 levels |
| px-haze | `shift-1px` | catch | 1 px shift |
| px-excl | `shift-outside-exclusion-1px` | catch | 1 px shift of everything outside the named glyph region |
| px-excl | `glyph-removed` | catch | the '+' glyph removed from the excluded region (documented exclusion: decision 2: the named glyph region is excluded from the pixel gate (the case has no text/colour gate)) |
| px-excl | `glyph-moved-5px` | catch | the '+' glyph 5 px (2 pt) off inside the excluded region (documented exclusion: decision 2: the named glyph region is excluded from the pixel gate (the case has no text/colour gate)) |
| px-exact | `capture-size-799x600` | catch | a wrong capture size |
| px-exact | `capture-missing` | catch | a missing Windows capture |

### text

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| text-gate | `origin-offset-2pt-x` | catch | text origin 2 pt (5 px) to the right |
| text-gate | `origin-offset-2pt-y` | catch | text 2 pt (5 px) too low |
| text-gate | `centring-x-near` | near | horizontal offset right at the 1 px tolerance: must pass |
| text-gate | `centring-x-beyond` | catch | horizontal offset 1 px beyond the tolerance |
| text-gate | `centring-y-near` | near | vertical offset right at the 1 px tolerance: must pass |
| text-gate | `centring-y-beyond` | catch | vertical offset 1 px beyond the tolerance |
| text-gate | `text-missing` | catch | a missing element: the text is gone |
| text-gate | `ink-colour-light-grey` | catch | label ink colour shifted to light grey (luminance 190) |

### text-colour

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| text-gate | `ink-colour-dark-red` | catch | label ink colour shifted to dark red (the text-colour gate runs beside the text gate, decision 19) |

### text

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| text-gate | `aa-noise-inside-region` | near | anti-aliasing differences inside the glyph region (reported, never gated) |
| text-gate | `pixel-outside-region` | catch | a pixel outside the glyph region 1 level off |

### text-colour

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| tc-red | `r0-ink-just-beyond` | catch | ink colour 1 level beyond the 24 tolerance |
| tc-red | `r0-ink-at-tolerance` | near | ink colour exactly at the 24 tolerance: must pass |
| tc-red | `r0-ink-+40` | catch | label ink colour shifted by 40 levels |
| tc-red | `r0-wrong-colour` | catch | wrong ink colour (re-tinted to the accent blue) |
| tc-red | `r0-missing-text` | catch | a missing element |
| tc-red | `r0-origin-offset-2pt` | catch | text origin 2 pt (5 px) off inside its excluded region (decision 19 gates the line's position) |
| tc-red | `r0-origin-offset-2pt-left` | catch | text origin 2 pt (5 px) off to the left inside its excluded region |
| tc-red | `r0-centring-y-2pt` | catch | text 2 pt (5 px) off vertically inside its excluded region |
| tc-red | `r0-centring-y-up-2pt` | catch | text 2 pt (5 px) too high inside its excluded region |
| tc-red | `r0-centring-y-2px` | catch | text 2 px (about 1 pt) too low (the mid-point of first ink y and baseline is gated to 0.5 px) |
| tc-red | `text-moved-out-of-exclusions` | catch | text moved out of every excluded region (the pixel gate sees it) |
| tc-fg | `r0-ink-just-beyond` | catch | ink colour 1 level beyond the 24 tolerance |
| tc-fg | `r0-ink-at-tolerance` | near | ink colour exactly at the 24 tolerance: must pass |
| tc-fg | `r0-ink-+40` | catch | label ink colour shifted by 40 levels |
| tc-fg | `r0-wrong-colour` | catch | wrong ink colour (re-tinted to the accent blue) |
| tc-fg | `r0-missing-text` | catch | a missing element |
| tc-fg | `r0-origin-offset-2pt` | catch | text origin 2 pt (5 px) off inside its excluded region (decision 19 gates the line's position) |
| tc-fg | `r0-origin-offset-2pt-left` | catch | text origin 2 pt (5 px) off to the left inside its excluded region |
| tc-fg | `r0-centring-y-2pt` | catch | text 2 pt (5 px) off vertically inside its excluded region |
| tc-fg | `r0-centring-y-up-2pt` | catch | text 2 pt (5 px) too high inside its excluded region |
| tc-fg | `r0-centring-y-2px` | catch | text 2 px (about 1 pt) too low (the mid-point of first ink y and baseline is gated to 0.5 px) |
| tc-fg | `r1-ink-just-beyond` | catch | ink colour 1 level beyond the 24 tolerance |
| tc-fg | `r1-ink-at-tolerance` | near | ink colour exactly at the 24 tolerance: must pass |
| tc-fg | `r1-ink-+40` | catch | label ink colour shifted by 40 levels |
| tc-fg | `r1-wrong-colour` | catch | wrong ink colour (re-tinted to the accent blue) |
| tc-fg | `r1-missing-text` | catch | a missing element |
| tc-fg | `r1-origin-offset-2pt` | catch | text origin 2 pt (5 px) off inside its excluded region (decision 19 gates the line's position) |
| tc-fg | `r1-origin-offset-2pt-left` | catch | text origin 2 pt (5 px) off to the left inside its excluded region |
| tc-fg | `r1-centring-y-2pt` | catch | text 2 pt (5 px) off vertically inside its excluded region |
| tc-fg | `r1-centring-y-up-2pt` | catch | text 2 pt (5 px) too high inside its excluded region |
| tc-fg | `r1-centring-y-2px` | catch | text 2 px (about 1 pt) too low (the mid-point of first ink y and baseline is gated to 0.5 px) |
| tc-fg | `text-moved-out-of-exclusions` | catch | text moved out of every excluded region (the pixel gate sees it) |
| tc-dark | `r0-ink-just-beyond` | catch | ink colour 1 level beyond the 24 tolerance |
| tc-dark | `r0-ink-at-tolerance` | near | ink colour exactly at the 24 tolerance: must pass |
| tc-dark | `r0-ink-+40` | catch | label ink colour shifted by 40 levels |
| tc-dark | `r0-wrong-colour` | catch | wrong ink colour (re-tinted to the accent blue) |
| tc-dark | `r0-missing-text` | catch | a missing element |
| tc-dark | `r0-origin-offset-2pt` | catch | text origin 2 pt (5 px) off inside its excluded region (decision 19 gates the line's position) |
| tc-dark | `r0-origin-offset-2pt-left` | catch | text origin 2 pt (5 px) off to the left inside its excluded region |
| tc-dark | `r0-centring-y-2pt` | catch | text 2 pt (5 px) off vertically inside its excluded region |
| tc-dark | `r0-centring-y-up-2pt` | catch | text 2 pt (5 px) too high inside its excluded region |
| tc-dark | `r0-centring-y-2px` | catch | text 2 px (about 1 pt) too low (the mid-point of first ink y and baseline is gated to 0.5 px) |
| tc-dark | `r3-ink-just-beyond` | catch | ink colour 1 level beyond the 24 tolerance |
| tc-dark | `r3-ink-at-tolerance` | near | ink colour exactly at the 24 tolerance: must pass |
| tc-dark | `r3-ink-+40` | catch | label ink colour shifted by 40 levels |
| tc-dark | `r3-wrong-colour` | catch | wrong ink colour (re-tinted to the accent blue) |
| tc-dark | `r3-missing-text` | catch | a missing element |
| tc-dark | `r3-origin-offset-2pt` | catch | text origin 2 pt (5 px) off inside its excluded region (decision 19 gates the line's position) |
| tc-dark | `r3-origin-offset-2pt-left` | catch | text origin 2 pt (5 px) off to the left inside its excluded region |
| tc-dark | `r3-centring-y-2pt` | catch | text 2 pt (5 px) off vertically inside its excluded region |
| tc-dark | `r3-centring-y-up-2pt` | catch | text 2 pt (5 px) too high inside its excluded region |
| tc-dark | `r3-centring-y-2px` | catch | text 2 px (about 1 pt) too low (the mid-point of first ink y and baseline is gated to 0.5 px) |
| tc-dark | `text-moved-out-of-exclusions` | catch | text moved out of every excluded region (the pixel gate sees it) |

### button

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| btn-bordered | `y-shift-1px` | catch | 1 px vertical shift of the button (y tolerance 0) |
| btn-bordered | `height+1px` | catch | button 1 px taller |
| btn-bordered | `missing-button` | catch | a missing element: the button is gone |
| btn-bordered | `label-missing` | catch | a missing element: the label is gone |
| btn-bordered | `label-ink-just-beyond` | catch | label ink colour 41 levels from the Mac (tolerance 40) |
| btn-bordered | `label-ink-at-tolerance` | near | label ink colour exactly 40 levels from the Mac: must pass |
| btn-bordered | `label-centre-x-beyond` | catch | label centring offset 1 px beyond the 3 px tolerance (x) |
| btn-bordered | `label-centre-x-near` | near | label centring offset at the 3 px tolerance (x): must pass |
| btn-bordered | `label-centre-y-beyond` | catch | label centring offset 1 px beyond the 3 px tolerance (y) |
| btn-bordered | `label-centre-y-near` | near | label centring offset at the 3 px tolerance (y): must pass |
| btn-bordered | `label-origin-2pt-x` | catch | label text origin 2 pt (5 px) off horizontally |
| btn-bordered | `label-origin-2pt-y` | catch | label text 2 pt (5 px) off vertically |
| btn-bordered | `corner-radius` | catch | wrong corner radius |
| btn-bordered | `fill+5` | catch | flat fill 5 levels off |
| btn-bordered | `cap-pixel+33` | catch | one cap edge pixel 33 levels off (edge-aa 32) |
| btn-bordered | `cap-pixel+32` | near | one cap edge pixel exactly 32 levels off: must pass |
| btn-bordered | `width+8px` | near | button 8 px wider (label advance difference is reported, never gated) |
| btn-bordered | `width-8px` | near | button 8 px narrower |
| btn-prominent | `y-shift-1px` | catch | 1 px vertical shift of the button (y tolerance 0) |
| btn-prominent | `height+1px` | catch | button 1 px taller |
| btn-prominent | `missing-button` | catch | a missing element: the button is gone |
| btn-prominent | `label-missing` | catch | a missing element: the label is gone |
| btn-prominent | `label-ink-just-beyond` | catch | label ink colour 41 levels from the Mac (tolerance 40) |
| btn-prominent | `label-ink-at-tolerance` | near | label ink colour exactly 40 levels from the Mac: must pass |
| btn-prominent | `label-centre-x-beyond` | catch | label centring offset 1 px beyond the 3 px tolerance (x) |
| btn-prominent | `label-centre-x-near` | near | label centring offset at the 3 px tolerance (x): must pass |
| btn-prominent | `label-centre-y-beyond` | catch | label centring offset 1 px beyond the 3 px tolerance (y) |
| btn-prominent | `label-centre-y-near` | near | label centring offset at the 3 px tolerance (y): must pass |
| btn-prominent | `label-origin-2pt-x` | catch | label text origin 2 pt (5 px) off horizontally |
| btn-prominent | `label-origin-2pt-y` | catch | label text 2 pt (5 px) off vertically |
| btn-prominent | `corner-radius` | catch | wrong corner radius |
| btn-prominent | `fill+5` | catch | flat fill 5 levels off |
| btn-prominent | `cap-pixel+33` | catch | one cap edge pixel 33 levels off (edge-aa 32) |
| btn-prominent | `cap-pixel+32` | near | one cap edge pixel exactly 32 levels off: must pass |
| btn-prominent | `width+8px` | near | button 8 px wider (label advance difference is reported, never gated) |
| btn-prominent | `width-8px` | near | button 8 px narrower |
| btn-disabled | `y-shift-1px` | catch | 1 px vertical shift of the button (y tolerance 0) |
| btn-disabled | `height+1px` | catch | button 1 px taller |
| btn-disabled | `missing-button` | catch | a missing element: the button is gone |
| btn-disabled | `label-missing` | catch | a missing element: the label is gone |
| btn-disabled | `label-ink-just-beyond` | catch | label ink colour 41 levels from the Mac (tolerance 40) |
| btn-disabled | `label-ink-at-tolerance` | near | label ink colour exactly 40 levels from the Mac: must pass |
| btn-disabled | `label-centre-x-beyond` | catch | label centring offset 1 px beyond the 3 px tolerance (x) |
| btn-disabled | `label-centre-x-near` | near | label centring offset at the 3 px tolerance (x): must pass |
| btn-disabled | `label-centre-y-beyond` | catch | label centring offset 1 px beyond the 3 px tolerance (y) |
| btn-disabled | `label-centre-y-near` | near | label centring offset at the 3 px tolerance (y): must pass |
| btn-disabled | `label-origin-2pt-x` | catch | label text origin 2 pt (5 px) off horizontally |
| btn-disabled | `label-origin-2pt-y` | catch | label text 2 pt (5 px) off vertically |
| btn-disabled | `corner-radius` | catch | wrong corner radius |
| btn-disabled | `fill+5` | catch | flat fill 5 levels off |
| btn-disabled | `cap-pixel+33` | catch | one cap edge pixel 33 levels off (edge-aa 32) |
| btn-disabled | `cap-pixel+32` | near | one cap edge pixel exactly 32 levels off: must pass |
| btn-disabled | `width+8px` | near | button 8 px wider (label advance difference is reported, never gated) |
| btn-disabled | `width-8px` | near | button 8 px narrower |
| btn-disabled | `enabled-look` | catch | disabled button drawn with the enabled colours |
| btn-prominent | `fill-grey` | catch | prominent (accent) fill replaced by the bordered grey |

### control

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| ctl-switch | `control-y-at-tolerance` | near | control y offset exactly at its tolerance: must pass |
| ctl-switch | `control-y-beyond` | catch | control y offset 1 px beyond its tolerance |
| ctl-switch | `control-y-2pt` | catch | control 2 pt (5 px) too low |
| ctl-switch | `control-height-1px` | catch | control one pixel shorter (wrong size) |
| ctl-switch | `missing-control` | catch | a missing element: the control is gone |
| ctl-switch | `label-missing` | catch | a missing element: the label is gone |
| ctl-switch | `label-centre-beyond` | catch | label centring offset 1 px beyond the tolerance |
| ctl-switch | `label-centre-near` | near | label centring offset at the tolerance: must pass |
| ctl-switch | `label-origin-2pt-y` | catch | label 2 pt (5 px) off vertically |
| ctl-switch | `label-origin-3px-x` | catch | label 3 px further right (the label's first ink x is gated, tolerance 0) |
| ctl-switch | `label-origin-1px-x` | catch | label 1 px further right |
| ctl-switch | `label-origin-2pt-x` | catch | label text origin 2 pt (5 px) off horizontally (label advance is reported, never gated) |
| ctl-switch | `wrong-state-colour` | catch | wrong toggle state: the on colour replaced by a grey |
| ctl-switch | `flat-colour+1` | catch | control flat colour 1 level off |
| ctl-switch | `edge-pixel+33` | catch | one control edge pixel 33 levels off |
| ctl-switch | `edge-pixel+32` | near | one control edge pixel exactly 32 levels off: must pass |
| ctl-switch | `control-x-2pt` | catch | control 2 pt (5 px) off horizontally |
| ctl-switch | `control-x-1px-left` | catch | control 1 px off in x relative to its label (switch: gap tolerance 1 px, the measured side bearing; checkbox: 0) |
| ctl-switch | `control-x-5px-away-from-label` | catch | control 5 px further from the Mac position |
| ctl-checkbox | `control-y-at-tolerance` | near | control y offset exactly at its tolerance: must pass |
| ctl-checkbox | `control-y-beyond` | catch | control y offset 1 px beyond its tolerance |
| ctl-checkbox | `control-y-2pt` | catch | control 2 pt (5 px) too low |
| ctl-checkbox | `control-height-1px` | catch | control one pixel shorter (wrong size) |
| ctl-checkbox | `missing-control` | catch | a missing element: the control is gone |
| ctl-checkbox | `label-missing` | catch | a missing element: the label is gone |
| ctl-checkbox | `label-centre-beyond` | catch | label centring offset 1 px beyond the tolerance |
| ctl-checkbox | `label-centre-near` | near | label centring offset at the tolerance: must pass |
| ctl-checkbox | `label-origin-2pt-y` | catch | label 2 pt (5 px) off vertically |
| ctl-checkbox | `label-origin-3px-x` | catch | label 3 px further right (the label's first ink x is gated, tolerance 0) |
| ctl-checkbox | `label-origin-1px-x` | catch | label 1 px further right |
| ctl-checkbox | `label-origin-2pt-x` | catch | label text origin 2 pt (5 px) off horizontally (label advance is reported, never gated) |
| ctl-checkbox | `wrong-state-colour` | catch | wrong toggle state: the on colour replaced by a grey |
| ctl-checkbox | `flat-colour+1` | catch | control flat colour 1 level off |
| ctl-checkbox | `edge-pixel+33` | catch | one control edge pixel 33 levels off |
| ctl-checkbox | `edge-pixel+32` | near | one control edge pixel exactly 32 levels off: must pass |
| ctl-checkbox | `control-x-2pt` | catch | control 2 pt (5 px) off horizontally |
| ctl-checkbox | `control-x-1px-right` | catch | control 1 px off in x relative to its label (switch: gap tolerance 1 px, the measured side bearing; checkbox: 0) |
| ctl-checkbox | `control-x-5px-away-from-label` | catch | control 5 px further from the Mac position |

### semantic

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| sem-click | `wrong-value` | catch | wrong value: the counter text |
| sem-click | `missing-node` | catch | a missing node: the Add button |
| sem-click | `wrong-role` | catch | a wrong role: the button published as text |
| sem-click | `wrong-enabled` | catch | button published disabled |
| sem-click | `extra-node` | catch | an extra button node |
| sem-click | `wrong-name` | catch | a wrong button name |
| sem-click | `order-swapped` | catch | tree order swapped |
| sem-click | `name-whitespace` | near | internal whitespace differs (the comparator collapses it) |
| sem-click | `bounds-30pt-x` | catch | button 30 pt out of place in x (its centre is gated, decision 17) |
| sem-click | `bounds-x-2pt` | catch | button published 2 pt (5 px) off in x |
| sem-click | `bounds-y-2pt` | catch | button published 2 pt (5 px) too low |
| sem-click | `bounds-y-30pt` | catch | button published 30 pt too low |
| sem-click | `bounds-text-y-2pt` | catch | the count text published 2 pt too low |
| sem-click | `focus-flag` | catch | wrong focus owner (UIA flag) (documented exclusion: docs/sr1-status.md block 14 caveat and sr1-decisions D7: UIA keyboard focus is false in the Sandbox; focus is gated through @FocusState text, not the UIA flag) |
| sem-binding | `wrong-toggle-state-c1` | catch | wrong toggle state |
| sem-binding | `wrong-toggle-state-c2` | catch | wrong toggle state |
| sem-binding | `wrong-toggle-state-final` | catch | wrong toggle state |
| sem-binding | `toggle-mixed-c1` | catch | toggle published as mixed |
| sem-binding | `toggle-lost-c1` | catch | toggle state not published (a plain button) |
| sem-binding | `wrong-counter-c2` | catch | wrong value: the derived count text |
| sem-alert-three | `button-renamed` | catch | wrong button set: a button renamed |
| sem-alert-three | `button-missing` | catch | wrong button set: Cancel missing |
| sem-alert-three | `button-extra` | catch | wrong button set: an extra OK button |
| sem-alert-three | `button-order` | catch | wrong button order (default/first button last) |
| sem-alert-three | `button-disabled` | catch | a dialog button disabled |
| sem-alert-three | `dialog-title` | catch | wrong dialog title |
| sem-alert-three | `dialog-message` | catch | wrong message text |
| sem-alert-three | `dialog-missing` | catch | no dialog shown |
| sem-alert-three | `dialog-double` | catch | two dialogs shown |
| sem-alert-three | `default-button-wrong` | catch | wrong default button: the Windows TaskDialog is asked to default to Third (Mac default is First); host log HOST_DIALOG_REQUEST default=2 |
| sem-alert-three | `default-button-wrong-cancel` | catch | wrong default button: Cancel |
| sem-alert-three | `default-button-none` | catch | no default button requested |
| sem-alert-three | `default-index-out-of-range` | catch | default index beyond the buttons |
| sem-alert-three | `default-request-missing` | catch | the host log records no dialog request |
| sem-alert-three | `default-button-uia-focus` | catch | wrong default button: UIA keyboard focus on Third (documented exclusion: docs/sr1-status.md block 14 caveat and sr1-decisions D7: UIA keyboard focus is false in the Sandbox; focus is gated through @FocusState text, not the UIA flag) |
| sem-alert-default | `enter-ran-wrong-button` | catch | wrong default button: Enter ran 'Don't save' (nothing happened) instead of 'Save' |
| sem-alert-default | `enter-ignored` | catch | wrong default button: Enter did not dismiss the dialog |
| sem-alert-default | `button-set-wrong` | catch | wrong button set |
| sem-alert-default | `default-button-wrong` | catch | wrong default button: the Windows TaskDialog defaults to Cancel (Mac default is Save) |
| sem-alert-confirm | `destructive-default` | catch | the destructive Delete button is the Windows default (the Mac has none and Cancel is the Escape button) |
| sem-alert-confirm | `default-button-none` | catch | no default button requested |
| sem-focus-tab | `wrong-focus-owner-text` | catch | wrong focus owner: the @FocusState text names the other field |
| sem-focus-tab | `wrong-focus-owner-t5` | catch | wrong focus owner after the last Tab |
| sem-focus-tab | `wrong-value` | catch | wrong field value |
| sem-focus-tab | `missing-field` | catch | a missing node: the second field |
| sem-focus-tab | `wrong-role` | catch | wrong role: a field published as text |
| sem-focus-tab | `focus-flag-wrong-field` | catch | wrong focus owner (UIA flag on the other field) (documented exclusion: docs/sr1-status.md block 14 caveat and sr1-decisions D7: UIA keyboard focus is false in the Sandbox; focus is gated through @FocusState text, not the UIA flag) |
| sem-ime | `wrong-value` | catch | wrong value: composition text differs |
| sem-ime | `value-uncommitted` | catch | wrong value: composition not shown |
| sem-ime | `missing-field` | catch | a missing node |

### ime

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| sem-ime | `marked-range-windows` | catch | wrong marked-text range on Windows (host HOST_FIELD log: marked=0+2, Mac marks 2+2) |
| sem-ime | `marked-range-mac` | catch | wrong marked-text range on the Mac reference (MAC_FACT log) |
| sem-ime | `marked-lost-windows` | catch | marked range lost on Windows (composition committed early) |
| sem-ime | `marked-appears-on-mac-click` | catch | marked text present on the Mac before any composition |
| sem-ime | `marked-length-windows` | catch | marked range one unit short on Windows |
| sem-ime | `selection-windows` | catch | selected range wrong on Windows (caret inside the marked text) |
| sem-ime | `selection-mac` | catch | selected range wrong on the Mac reference |
| sem-ime | `text-windows` | catch | composed string differs on Windows |
| sem-ime | `text-mac` | catch | composed string differs on the Mac reference |
| sem-ime | `step-missing-windows` | catch | the Windows host logged no scripted steps |
| sem-ime | `mac-log-missing` | catch | the Mac run log is missing |
| sem-ime | `marked-none-spelling` | near | an empty marked range at another location on the Mac after the click is still 'no marked text': must pass |

### semantic

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| sem-tf-placeholder | `field-x-2pt` | catch | text field published 2 pt (5 px) too far right |
| sem-tf-placeholder | `field-y-2pt` | catch | text field published 2 pt (5 px) too low |
| sem-tf-placeholder | `field-x-0.04pt` | near | text field published 0.04 pt off in x: inside the 0.05 pt rounding tolerance, must pass |
| sem-tf-placeholder | `wrong-name` | catch | wrong placeholder/name |
| sem-tf-placeholder | `wrong-value` | catch | wrong value |
| sem-tf-placeholder | `wrong-role` | catch | wrong role |
| sem-tf-placeholder | `missing-node` | catch | a missing node |

### list

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| list-arrow | `row-order` | catch | row order: two rows swapped |
| list-arrow | `selection-moved` | catch | wrong selection: another row selected |
| list-arrow | `selection-none` | catch | wrong selection: none selected |
| list-arrow | `selection-two` | catch | wrong selection: two rows selected |
| list-arrow | `row-missing` | catch | a missing row |
| list-arrow | `row-extra` | catch | an extra row |
| list-arrow | `row-text` | catch | wrong row text |
| list-arrow | `row-frame-y-beyond` | catch | row frame y 1 px beyond rowTolerancePx |
| list-arrow | `row-frame-y-at-tolerance` | near | row frame y at rowTolerancePx: must pass |
| list-arrow | `row-frame-x-2px` | catch | row 2 frame x 2 px off |
| list-arrow | `row-height+2` | catch | row height 2 px off |
| list-arrow | `label-ink-just-beyond` | catch | row 0 label ink colour 41 levels from the Mac (tolerance 40) |
| list-arrow | `label-ink-at-tolerance` | near | row 0 label ink colour exactly 40 levels off: must pass |
| list-arrow | `label-missing` | catch | a missing element: row 0 label gone |
| list-arrow | `highlight-grey` | catch | selection highlight in the wrong colour (grey instead of accent) |
| list-arrow | `highlight-colour+1` | catch | selection highlight 1 level off |
| list-arrow | `highlight-missing` | catch | selection highlight not drawn |
| list-arrow | `highlight-wrong-row` | catch | selection highlight on the wrong row |
| list-arrow | `pixels-shift-1px` | catch | 1 px shift of the list pixels |
| list-var | `row-order-pixels` | catch | row order: the rows (colour swatches, empty text) in reverse order |
| list-var | `selection-moved` | catch | wrong selection: another row selected |
| list-var | `selection-none` | catch | wrong selection: none selected |
| list-var | `selection-two` | catch | wrong selection: two rows selected |
| list-var | `row-missing` | catch | a missing row |
| list-var | `row-extra` | catch | an extra row |
| list-var | `row-text` | catch | wrong row text |
| list-var | `row-frame-y-beyond` | catch | row frame y 1 px beyond rowTolerancePx |
| list-var | `row-frame-y-at-tolerance` | near | row frame y at rowTolerancePx: must pass |
| list-var | `row-frame-x-2px` | catch | row 2 frame x 2 px off |
| list-var | `row-height+2` | catch | row height 2 px off |
| list-var | `label-ink-just-beyond` | catch | row 0 label ink colour 41 levels from the Mac (tolerance 40) |
| list-var | `label-missing` | catch | a missing element: row 0 label gone |
| list-var | `highlight-grey` | catch | selection highlight in the wrong colour (grey instead of accent) |
| list-var | `highlight-colour+1` | catch | selection highlight 1 level off |
| list-var | `highlight-missing` | catch | selection highlight not drawn |
| list-var | `highlight-wrong-row` | catch | selection highlight on the wrong row |
| list-var | `pixels-shift-1px` | catch | 1 px shift of the list pixels |

### clock

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| clk-linear | `frame-out-of-sequence` | catch | a frame out of sequence (frames 1 and 2 swapped, logs too) |
| clk-linear | `frame-out-of-sequence-images` | catch | a frame out of sequence (pictures only; host log says the right time) |
| clk-linear | `extent+beyond` | catch | extent 0.15 px beyond the C2 tolerance (1 px), wider |
| clk-linear | `extent-beyond` | catch | extent 0.15 px beyond the C2 tolerance, narrower |
| clk-linear | `extent+near` | near | extent 0.08 px inside the C2 tolerance: must pass |
| clk-linear | `extent-near` | near | extent 0.08 px inside the tolerance, narrower: must pass |
| clk-linear | `extent+1.5px` | catch | extent 1.5 px wider |
| clk-linear | `extent+5px` | catch | extent 5 px (2 pt) wider |
| clk-linear | `timing-progress-beyond` | catch | wrong timing: runtime progress 0.0006 beyond progressTolerance 0.004 (images untouched) |
| clk-linear | `timing-progress-near` | near | runtime progress 0.0004 inside progressTolerance: must pass |
| clk-linear | `timing-progress-0.05` | catch | wrong timing: runtime 5 percent ahead |
| clk-linear | `timing-progress-neg` | catch | wrong timing: runtime 2 percent behind |
| clk-linear | `missing-element` | catch | a missing element: the bar is not drawn |
| clk-linear | `stray-pixel` | catch | one background pixel 1 level off outside the strips |
| clk-linear | `whole-frame-shift-x-1px` | near | the whole frame 1 px off in x (a 1 px edge translation is inside the C2 snap: must pass) |
| clk-linear | `whole-frame-shift-y-1px` | catch | the whole frame 1 px off in y |
| clk-linear | `bar-translate-y-1px` | catch | the bar 1 px too low |
| clk-linear | `bar-translate-x-2` | catch | the bar 2 px right (left edge moves, width the same) |
| clk-linear | `bar-translate-x-5` | catch | the bar 2 pt (5 px) right |
| clk-linear | `frame-missing` | catch | a missing capture |
| clk-spring | `extent+beyond` | catch | extent 0.15 px beyond the named 2 px spring tolerance |
| clk-spring | `extent-beyond` | catch | extent 0.15 px beyond the 2 px tolerance, narrower |
| clk-spring | `extent+near` | near | extent 0.08 px inside the 2 px tolerance: must pass |
| clk-spring | `extent-near` | near | extent 0.08 px inside the 2 px tolerance, narrower: must pass |
| clk-spring | `extent-1.2px-passes` | near | extent 1.2 px (beyond a 1 px gate, inside the spring's 2 px) |
| clk-spring | `bar-translate-x-3px` | catch | frame 1: the bar 3 px right (edges 3 px off, beyond the spring's named 2 px) |
| clk-spring | `bar-translate-x-2px-at-tolerance` | near | frame 1: the bar 2 px right: exactly the spring's named 2 px edge tolerance (the same tolerance as its extent): must pass |
| clk-spring | `bar-translate-x-5px` | catch | frame 1: the bar 2 pt (5 px) right |
| clk-spring | `frame-out-of-sequence` | catch | a frame out of sequence |
| clk-spring | `timing-progress-beyond` | catch | runtime progress just beyond progressTolerance 0.005 |
| clk-spring | `timing-progress-near` | near | runtime progress just inside progressTolerance: must pass |
| clk-spring | `missing-element` | catch | a missing element |
| clk-move | `frame-out-of-sequence` | catch | a frame out of sequence |
| clk-move | `extent+beyond` | catch | extent just beyond the 1 px tolerance |
| clk-move | `extent+near` | near | extent just inside the tolerance: must pass |
| clk-move | `translate-x-1px` | near | the moving bar 1 px off in x (inside the C2 snap) |
| clk-move | `translate-x-2px` | catch | the moving bar 2 px off in x |
| clk-move | `translate-x-3px` | catch | the moving bar 3 px off in x |
| clk-move | `translate-x-5px` | catch | the moving bar 2 pt (5 px) off in x |
| clk-move | `translate-y-1px` | catch | the moving bar 1 px too low |
| clk-move | `missing-element` | catch | a missing element |
| clk-fade | `frame-out-of-sequence` | catch | a frame out of sequence |
| clk-fade | `opacity-1-level` | catch | opacity 1 level off |
| clk-fade | `missing-element` | catch | a missing element |
| clk-fade | `shift-1px` | catch | 1 px shift |

### image

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| img-star | `frame-logged-x+1` | catch | the Image view frame logged 1 px off in x |
| img-star | `frame-logged-y+1` | catch | the Image view frame logged 1 px off in y |
| img-star | `frame-logged-width+1` | catch | the Image view frame logged 1 px wider |
| img-star | `glyph-shift-x+1` | catch | 1 px shift of the symbol |
| img-star | `glyph-shift-y+1` | catch | 1 px shift of the symbol (vertical) |
| img-star | `glyph-shift-2pt` | catch | the symbol 2 pt (5 px) off |
| img-star | `tint+1` | catch | tint one level off (just beyond: the tint gate has no tolerance) |
| img-star | `tint-wrong` | catch | wrong tint colour |
| img-star | `missing-element` | catch | a missing element |
| img-star | `wrong-size` | catch | wrong size: the symbol 10 percent smaller |
| img-star | `pixel-outside-frame` | catch | one pixel outside the frame 1 level off |
| img-star | `aa-noise-in-glyph` | near | glyph anti-aliasing differs (shape reported only): must pass |
| img-star | `interior-hole` | near | the glyph shape differs inside the frame while bbox and tint hold (decision 3: shape reported only) |

### text-origin

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| to-filled | `origin-2pt-left` | catch | text origin 2 pt (5 px) too far left (the original defect) |
| to-filled | `origin-2pt-right` | catch | text origin 2 pt (5 px) too far right |
| to-filled | `origin-1px` | catch | text origin 1 px off (tolerance is 0) |
| to-filled | `origin--1px` | catch | text origin 1 px left |
| to-filled | `centring-y-2pt` | catch | text 2 pt (5 px) too low (centring) |
| to-filled | `centring-y-up-2pt` | catch | text 2 pt (5 px) too high |
| to-filled | `centring-y-1px` | catch | text 1 px too low (the mid-point of first ink y and baseline is gated to 0.5 px) |
| to-filled | `centring-y-1pt` | catch | text 2 px (about 1 pt) too low |
| to-filled | `origin-2pt-down-right` | catch | text 2 pt (5 px) off in both x and y |
| to-filled | `text-missing` | catch | a missing element: the text is gone |
| to-filled | `right-clip-differs` | near | text clipped/truncated differently on the right (first ink unchanged) |
| to-selected | `selection-colour+1` | catch | selection colour one level off (179,215,254) |
| to-selected | `selection-colour-grey` | catch | selection in the inactive grey (220) |
| to-selected | `selection-colour-accent` | catch | selection in the list accent colour instead of (179,215,255) |
| to-selected | `selection-missing` | catch | a missing element: the selection is not drawn |
| to-selected | `selection-start+1` | catch | selection start 1 px right |
| to-selected | `selection-start-1` | catch | selection start 1 px left |
| to-selected | `selection-start+5` | catch | selection start 2 pt (5 px) right |
| to-selected | `origin-2pt-left` | catch | text origin 2 pt (5 px) left inside a selected field |
| to-selected | `selection-end-5px` | near | selection end 5 px shorter (glyph advances, Segoe vs SF: reported only) |
| to-selected | `selection-height-2px` | near | selection 2 rows shorter (line height, reported only) |
| to-selected | `unselected-field-origin-2pt` | catch | the second (unselected) field's text 2 pt left |
| to-caret | `y-up-1px-inside-measured-envelope` | near | text 1 px higher: first ink y delta 1, baseline delta -2: inside the measured envelope of the other bezeled cases, must pass |
| to-caret | `centring-y-2pt` | catch | text 2 pt (5 px) too low in an empty focused field |
| to-caret | `caret+1px` | catch | caret 1 px right of the Mac insertion point |
| to-caret | `caret-1px` | catch | caret 1 px left |
| to-caret | `caret+5px` | catch | caret 2 pt (5 px) right (text origin offset) |
| to-caret | `caret-missing` | catch | a missing element: no caret |

### multi-run

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| px-exact | `pixel/shift-1px@run3of3` | catch | 1 px shift of the whole picture in 1 of 3 runs |
| px-edge | `pixel/band+32@run3of3` | near | one AA-edge pixel exactly 32 levels off (edge-aa<=32 must pass) in 1 of 3 runs |
| px-edge | `pixel/band+33@run3of3` | catch | one AA-edge pixel 33 levels off (beyond edge-aa 32) in 1 of 3 runs |
| btn-bordered | `button/y-shift-1px@run3of3` | catch | 1 px vertical shift of the button (y tolerance 0) in 1 of 3 runs |
| btn-bordered | `button/label-ink-at-tolerance@run3of3` | near | label ink colour exactly 40 levels from the Mac: must pass in 1 of 3 runs |
| btn-bordered | `button/label-ink-just-beyond@run3of3` | catch | label ink colour 41 levels from the Mac (tolerance 40) in 1 of 3 runs |
| ctl-switch | `control/label-centre-near@run3of3` | near | label centring offset at the tolerance: must pass in 1 of 3 runs |
| ctl-switch | `control/label-centre-beyond@run3of3` | catch | label centring offset 1 px beyond the tolerance in 1 of 3 runs |
| list-arrow | `list/row-order@run3of3` | catch | row order: two rows swapped in 1 of 3 runs |
| list-arrow | `list/row-frame-y-at-tolerance@run3of3` | near | row frame y at rowTolerancePx: must pass in 1 of 3 runs |
| list-arrow | `list/selection-moved@run3of3` | catch | wrong selection: another row selected in 1 of 3 runs |
| sem-click | `semantic/wrong-value@run3of3` | catch | wrong value: the counter text in 1 of 3 runs |
| sem-click | `semantic/name-whitespace@run3of3` | near | internal whitespace differs (the comparator collapses it) in 1 of 3 runs |
| clk-linear | `clock/extent+beyond@run3of3` | catch | extent 0.15 px beyond the C2 tolerance (1 px), wider in 1 of 3 runs |
| clk-linear | `clock/extent+near@run3of3` | near | extent 0.08 px inside the C2 tolerance: must pass in 1 of 3 runs |
| clk-linear | `clock/timing-progress-beyond@run3of3` | catch | wrong timing: runtime progress 0.0006 beyond progressTolerance 0.004 (images untouched) in 1 of 3 runs |
| to-filled | `text-origin/origin-1px@run3of3` | catch | text origin 1 px off (tolerance is 0) in 1 of 3 runs |
| to-filled | `text-origin/right-clip-differs@run3of3` | near | text clipped/truncated differently on the right (first ink unchanged) in 1 of 3 runs |
| tc-red | `text-colour/r0-ink-just-beyond@run3of3` | catch | ink colour 1 level beyond the 24 tolerance in 1 of 3 runs |
| tc-red | `text-colour/r0-ink-at-tolerance@run3of3` | near | ink colour exactly at the 24 tolerance: must pass in 1 of 3 runs |

### text-colour

| Base | Mutation | Kind | What it seeds |
|---|---|---|---|
| rowtol-serif | `r0-dy-beyond` | catch | first ink y one px beyond the row's own tolerance |
| rowtol-serif | `r0-dy-at-tol` | near | first ink y exactly at the row's own tolerance: must pass |
| rowtol-serif | `r0-dx-beyond` | catch | first ink x one px beyond the row's own tolerance |
| rowtol-serif | `r0-2pt-natural` | catch | row 2 pt (5 px) further in the direction of its natural offset |
| rowtol-serif | `r0-2pt-counter` | catch | row 2 pt (5 px) against its natural offset: first ink y may land inside its tolerance, but the baseline (tolerance 0 on these rows) moves with it and fails |
| rowtol-grid13 | `r0-dy-beyond` | catch | first ink y one px beyond the row's own tolerance |
| rowtol-grid13 | `r0-dy-at-tol` | near | first ink y exactly at the row's own tolerance: must pass |
| rowtol-grid13 | `r0-dx-beyond` | catch | first ink x one px beyond the row's own tolerance |
| rowtol-grid13 | `r0-2pt-natural` | catch | row 2 pt (5 px) further in the direction of its natural offset |
| rowtol-grid13 | `r0-2pt-counter` | catch | row 2 pt (5 px) against its natural offset: first ink y may land inside its tolerance, but the baseline (tolerance 0 on these rows) moves with it and fails |

421 mutations in total.
