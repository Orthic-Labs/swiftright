# Mutation calibration results

Generated 2026-10-14 by `factory/tools/mutation-calibration/calibrate.py` (see its README for every mutation). Offline: no capture, no Windows, no Sandbox. All 32 unmutated base fixtures pass their gates before any mutation is applied. The verdict of every row is the exit status of `pair.py <case> --recompare <run>`.

**256 of 285 seeded faults caught; 66 of 66 near-misses inside a tolerance passed; 0 over-strict gates.** 29 faults were not caught: 6 with no documented reason (findings A below), 23 that a decision or the gate's own contract says is not gated (B below).

| Gate | Comparator | Caught / seeded | Missed (undocumented / documented exclusion) | Near-misses passed | Over-strict | Probes |
|---|---|---|---|---|---|---|
| pixel | `pair.py` | 27 / 29 | 2 (0 / 2) | 5 / 5 | 0 | 7 |
| text | `pair_text_report.py` | 7 / 8 | 1 (0 / 1) | 3 / 3 | 0 | 0 |
| text-colour | `pair_textcolour_report.py` | 23 / 33 (2 by the case's pixel gate) | 10 (0 / 10) | 5 / 5 | 0 | 0 |
| button | `pair_button_report.py` | 38 / 38 | 0 (0 / 0) | 18 / 18 | 0 | 0 |
| control | `pair_control_report.py` | 20 / 24 | 4 (0 / 4) | 8 / 8 | 0 | 0 |
| list | `pair_list_report.py` | 34 / 34 (6 by the case's pixel gate) | 0 (0 / 0) | 3 / 3 | 0 | 0 |
| semantic | `pair_semantic_report.py` | 37 / 45 | 8 (3 / 5) | 1 / 1 | 0 | 0 |
| clock | `pair_clock_report.py` | 29 / 32 (1 by a comparator crash) | 3 (3 / 0) | 10 / 10 | 0 | 0 |
| image | `pair_image_report.py` | 11 / 11 | 0 (0 / 0) | 2 / 2 | 0 | 0 |
| text-origin | `pair_textorigin_report.py` | 18 / 19 | 1 (0 / 1) | 3 / 3 | 0 | 0 |
| multi-run | `pair.py` | 12 / 12 | 0 (0 / 0) | 8 / 8 | 0 | 0 |

`text-origin` is the TextField text-origin and selection-colour gate (decisions 12 and 13, commits ddff82031, 09e184945 and d07df2581, on master when this ran); it is included.

## A. Findings: seeded faults no gate caught, with no documented reason

- **semantic / sem-ime / marked-range-windows** (miss): wrong marked-text range on Windows (host HOST_FIELD log: marked=0+2, Mac marks 2+2). Applied: windows/host-01.stdout.txt: 'marked=2+2' -> 'marked=0+2'.
- **semantic / sem-ime / marked-range-mac** (miss): wrong marked-text range on the Mac reference (MAC_FACT log). Applied: mac-run-01.log: 'marked=2+2' -> 'marked=3+1'.
- **semantic / sem-ime / marked-lost-windows** (miss): marked range lost on Windows (composition committed early). Applied: windows/host-01.stdout.txt: 'marked=2+2' -> 'marked=none'.
- **clock / clk-linear / bar-translate-x-2** (miss): the bar 2 px right (left edge moves, width the same). Applied: frame 2: the whole bar translated (2,0) px (extent unchanged).
- **clock / clk-move / translate-x-2px** (miss): the moving bar 2 px off in x. Applied: frame 2: the whole bar translated (2,0) px (extent unchanged).
- **clock / clk-move / translate-x-3px** (miss): the moving bar 3 px off in x. Applied: frame 2: the whole bar translated (3,0) px (extent unchanged).

## B. Faults not caught that a decision or the gate's contract says are not gated

Listed so the gaps are visible; nothing here was changed.

- **pixel / px-excl / glyph-removed**: the '+' glyph removed from the excluded region. Reason: decision 2: the named glyph region is excluded from the pixel gate (the case has no text/colour gate).
- **pixel / px-excl / glyph-moved-5px**: the '+' glyph 5 px (2 pt) off inside the excluded region. Reason: decision 2: the named glyph region is excluded from the pixel gate (the case has no text/colour gate).
- **text / text-gate / ink-colour-dark-red**: label ink colour shifted to dark red. Reason: text gate claims ink bbox and positions only; colour is gated by pair_textcolour_report.py in other cases (docs/sr1-decisions.md items 2 and 11).
- **text-colour / tc-red / r0-origin-offset-2pt**: text origin 2 pt (5 px) off inside its excluded region. Reason: decision 2: glyph pixels excluded from the pixel gate; the colour gate reads only the strongest ink pixel.
- **text-colour / tc-red / r0-centring-y-2pt**: text 2 pt (5 px) off vertically inside its excluded region. Reason: decision 2: glyph pixels excluded from the pixel gate; the colour gate reads only the strongest ink pixel.
- **text-colour / tc-fg / r0-origin-offset-2pt**: text origin 2 pt (5 px) off inside its excluded region. Reason: decision 2: glyph pixels excluded from the pixel gate; the colour gate reads only the strongest ink pixel.
- **text-colour / tc-fg / r0-centring-y-2pt**: text 2 pt (5 px) off vertically inside its excluded region. Reason: decision 2: glyph pixels excluded from the pixel gate; the colour gate reads only the strongest ink pixel.
- **text-colour / tc-fg / r1-origin-offset-2pt**: text origin 2 pt (5 px) off inside its excluded region. Reason: decision 2: glyph pixels excluded from the pixel gate; the colour gate reads only the strongest ink pixel.
- **text-colour / tc-fg / r1-centring-y-2pt**: text 2 pt (5 px) off vertically inside its excluded region. Reason: decision 2: glyph pixels excluded from the pixel gate; the colour gate reads only the strongest ink pixel.
- **text-colour / tc-dark / r0-origin-offset-2pt**: text origin 2 pt (5 px) off inside its excluded region. Reason: decision 2: glyph pixels excluded from the pixel gate; the colour gate reads only the strongest ink pixel.
- **text-colour / tc-dark / r0-centring-y-2pt**: text 2 pt (5 px) off vertically inside its excluded region. Reason: decision 2: glyph pixels excluded from the pixel gate; the colour gate reads only the strongest ink pixel.
- **text-colour / tc-dark / r3-origin-offset-2pt**: text origin 2 pt (5 px) off inside its excluded region. Reason: decision 2: glyph pixels excluded from the pixel gate; the colour gate reads only the strongest ink pixel.
- **text-colour / tc-dark / r3-centring-y-2pt**: text 2 pt (5 px) off vertically inside its excluded region. Reason: decision 2: glyph pixels excluded from the pixel gate; the colour gate reads only the strongest ink pixel.
- **control / ctl-switch / label-origin-2pt-x**: label text origin 2 pt (5 px) off horizontally (label advance is reported, never gated). Reason: docs/sr1-decisions.md item 2 and pair_control_report.py: dx and the label pixels are reported only.
- **control / ctl-switch / control-x-2pt**: control 2 pt (5 px) off horizontally. Reason: docs/sr1-decisions.md item 2 and pair_control_report.py: the control is compared after translating by the measured dx (the label-advance difference); dx is reported only.
- **control / ctl-checkbox / label-origin-2pt-x**: label text origin 2 pt (5 px) off horizontally (label advance is reported, never gated). Reason: docs/sr1-decisions.md item 2 and pair_control_report.py: dx and the label pixels are reported only.
- **control / ctl-checkbox / control-x-2pt**: control 2 pt (5 px) off horizontally. Reason: docs/sr1-decisions.md item 2 and pair_control_report.py: the control is compared after translating by the measured dx (the label-advance difference); dx is reported only.
- **semantic / sem-click / bounds-30pt**: button 30 pt out of place. Reason: the case's semanticGate.fields omits bounds (boundsTolerancePt is implemented but no shipped case lists bounds).
- **semantic / sem-click / focus-flag**: wrong focus owner (UIA flag). Reason: docs/sr1-status.md block 14 caveat and sr1-decisions D7: UIA keyboard focus is false in the Sandbox; focus is gated through @FocusState text, not the UIA flag.
- **semantic / sem-alert-three / default-button-wrong**: wrong default button: keyboard focus on Third (Mac default is First). Reason: docs/sr1-decisions.md D6: the default button cannot be read from UIA focus in the Sandbox; it is gated by behaviour (Enter runs the Mac default), so the static 'default' field is not listed in any alert case.
- **semantic / sem-alert-default / default-button-wrong**: wrong default button: focus on Cancel. Reason: docs/sr1-decisions.md D6: gated by behaviour (the Enter case above), not by a static flag.
- **semantic / sem-focus-tab / focus-flag-wrong-field**: wrong focus owner (UIA flag on the other field). Reason: docs/sr1-status.md block 14 caveat and sr1-decisions D7: UIA keyboard focus is false in the Sandbox; focus is gated through @FocusState text, not the UIA flag.
- **text-origin / to-filled / centring-y-2pt**: text 2 pt (5 px) too low (centring). Reason: decision 12 gates x (first ink, selection start, caret); the text rect stays excluded from the pixel gate (decision 2) and no gate reads the text's y.

## C. Near-misses that failed (over-strict gates)

None. Every near-miss placed exactly at or just inside a tolerance (edge-aa 32, hazeTolerance 3, C2 1 px and the spring's 2 px, progress 0.004/0.005, text bbox 1 px, button/list label ink 40, label centring 3 px, row frames 1 px, text-colour 24) passed.


## D. Sensitivity probes (px-edge, rounded stroke, edge-aa<=32, hazeTolerance 0)

| Probe | Gate verdict |
|---|---|
| probe-radius+0.25px | pass |
| probe-radius+0.5px | fail |
| probe-radius+1.0px | fail |
| probe-radius+2.0px | fail |
| probe-stroke+0.25px | fail |
| probe-stroke+0.5px | fail |
| probe-stroke+1.0px | fail |

## E. Gates and properties not calibrated offline

- **Real IME / TSF / Narrator behaviour**: needs Windows hardware; the Sandbox drives IME in-process (decisions B6, D8). Only the comparators on those dumps are calibrated.
- **UIA keyboard focus and OS-level focus restore**: UIA reports no keyboard focus in the Sandbox (decision D7), so the gates never read it; nothing to calibrate offline.
- **The capture hosts themselves (Windows renderer paint, Mac NSHostingView / AXDump / AlertHooks / MAC_FACT writers)**: they produce the evidence the comparators read; checking them needs new captures, which this pass excludes. Mutations assume the recorded Mac side is the truth.
- **Case-level tolerances outside the shipped cases (bounds in the semantic gate, a non-zero firstInkTolerancePx, the dark/pressed/focused button states, scales 1.25 and 1.5)**: no shipped case exercises them, so there is no real run evidence to mutate; unit tests in factory/tools/test_pair_*.py cover bounds, default button and tolerance on synthetic dumps only.
- **Runtime unit suites (Swift: runtime 333, host 121, bridge 51) and the consolidation driver (factory/pipeline/consolidation/run_all.py)**: they are not run-evidence comparators; the driver records pair.py's exit status, which the harness does exercise.
- **Provenance gates (stage identity in build.json, renderer sha256, receipts)**: the lean loop (decision 4) records them but no comparator reads them; earlier provenance fault controls live in factory/pipeline/paired-five-seeded-observations-actual-v4/fault-controls.json.

## F. Earlier coverage this pass builds on

- `factory/VERIFICATION.md`: F8 timing selftest, 15 fault controls on synthetic timing (predates SR1; does not touch the pair.py comparators).
- `factory/pipeline/paired-five-seeded-observations-actual-v4/fault-controls.json`: 10 provenance-receipt faults rejected (receipt gate, not pixels or semantics).
- `factory/tools/test_pair_control_report.py`, `test_pair_semantic_report.py`, `test_pair_textorigin_report.py`: unit tests on synthetic inputs (they pass at this commit); none uses real run evidence, and no test existed for the pixel, text, text-colour, button, list, clock or image gates.

## Evidence the fixtures come from

| Fixture | Case | Run |
|---|---|---|
| btn-bordered | `blocks-11-16/swiftui.button/bordered-v1` | 20261014-053055 |
| btn-disabled | `blocks-6-10/swiftui.disabled/button-disabled-v1` | 20261014-181921 |
| btn-prominent | `blocks-11-16/swiftui.button/prominent-v1` | 20261014-061108 |
| clk-fade | `blocks-6-10/swiftui.opacity-transition/insertion-fade-v1` | 20261014-002352 |
| clk-linear | `blocks-6-10/swiftui.animation/linear-width-v1` | 20261013-224725 |
| clk-move | `blocks-6-10/swiftui.opacity-transition/move-leading-v1` | 20261014-003055 |
| clk-spring | `blocks-6-10/swiftui.animation/default-spring-v1` | 20261013-232853 |
| ctl-checkbox | `blocks-6-10/swiftui.toggle/checkbox-labelled-on-v1` | 20261014-180300 |
| ctl-switch | `blocks-6-10/swiftui.toggle/switch-labelled-on-v1` | 20261014-175720 |
| img-star | `pilot-delivery-five-v1/text-shape-image/image-system-star-fill-v10` | 20261013-221400 |
| list-arrow | `blocks-11-16/swiftui.list/arrow-keys-v1` | 20261013-224316 |
| list-var | `blocks-11-16/swiftui.list/variable-rows-selected-v1` | 20261014-025727 |
| px-edge | `pilot-delivery-five-v1/text-shape-image/rounded-stroke-host-v1/continuous-geometry-delivery-v2` | 20261014-163619 |
| px-exact | `blocks-6-10/padding-frame/frame-alignment-v1` | 20261014-171910 |
| px-excl | `pilot-delivery-five-v1/stack-layout/stack-overlay-centered-execution-v9` | 20261014-165602 |
| px-fractional | `blocks-6-10/padding-frame/nested-fractional-v1` | 20261014-173407 |
| px-haze | `blocks-17-20/swiftui.color-scheme/switch-on-dark-v1` | 20261014-162645 |
| px-ties | `blocks-6-10/pixel-ties/layout-v1` | 20261014-182749 |
| sem-alert-default | `blocks-17-20/swiftui.alert/default-enter-v1` | 20261014-224807 |
| sem-alert-three | `blocks-17-20/swiftui.alert/three-buttons-v1` | 20261014-225724 |
| sem-binding | `blocks-6-10/swiftui.binding/derived-click-v1` | 20261014-195505 |
| sem-click | `blocks-11-16/swiftui.button/click-increments-v1` | 20261014-214203 |
| sem-focus-tab | `blocks-6-10/swiftui.focus-state/tab-order-v1` | 20261014-203430 |
| sem-ime | `blocks-6-10/swiftui.ime-marked-text/ime-composing-v1` | 20261014-204651 |
| sem-tf-placeholder | `blocks-6-10/swiftui.textfield/placeholder-v1` | 20261014-201102 |
| tc-dark | `blocks-17-20/swiftui.color-scheme/text-dark-v1` | 20261014-162943 |
| tc-fg | `blocks-6-10/swiftui.text/foreground-colour-v1` | 20261014-182126 |
| tc-red | `blocks-11-16/swiftui.button/borderless-red-v1` | 20261014-053614 |
| text-gate | `pilot-delivery-five-v1/text-shape-image/bundled-font-readiness-v6-line-limit-host` | 20261014-165825 |
| to-caret | `blocks-6-10/swiftui.textfield/caret-empty-v1` | 20261014-200431 |
| to-filled | `blocks-6-10/swiftui.textfield/filled-truncated-v1` | 20261014-200812 |
| to-selected | `blocks-6-10/swiftui.focus-state/programmatic-v1` | 20261014-202647 |
