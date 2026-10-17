# Mutation calibration results

Generated 2026-10-17 by `factory/tools/mutation-calibration/calibrate.py` (see its README for every mutation). Offline: no capture, no Windows, no Sandbox. All 40 unmutated base fixtures pass their gates before any mutation is applied. The verdict of every row is the exit status of `pair.py <case> --recompare <run>`.

**371 of 376 seeded faults caught; 74 of 74 near-misses inside a tolerance passed; 0 over-strict gates.** 5 faults were not caught: 0 with no documented reason (findings A below), 5 that a decision or the gate's own contract says is not gated (B below).

| Gate | Comparator | Caught / seeded | Missed (undocumented / documented exclusion) | Near-misses passed | Over-strict | Probes |
|---|---|---|---|---|---|---|
| pixel | `pair.py` | 27 / 29 | 2 (0 / 2) | 5 / 5 | 0 | 7 |
| text | `pair_text_report.py` | 7 / 7 | 0 (0 / 0) | 3 / 3 | 0 | 0 |
| text-colour | `pair_textcolour_report.py` | 68 / 68 | 0 (0 / 0) | 8 / 8 | 0 | 1 |
| button | `pair_button_report.py` | 38 / 38 | 0 (0 / 0) | 18 / 18 | 0 | 0 |
| control | `pair_control_report.py` | 39 / 39 | 0 (0 / 0) | 7 / 7 | 0 | 0 |
| list | `pair_list_report.py` | 34 / 34 (6 by the case's pixel gate) | 0 (0 / 0) | 3 / 3 | 0 | 0 |
| semantic | `pair_semantic_report.py` | 52 / 55 | 3 (0 / 3) | 2 / 2 | 0 | 0 |
| ime | `pair_ime_report.py` | 11 / 11 | 0 (0 / 0) | 1 / 1 | 0 | 0 |
| clock | `pair_clock_report.py` | 34 / 34 | 0 (0 / 0) | 11 / 11 | 0 | 0 |
| image | `pair_image_report.py` | 11 / 11 | 0 (0 / 0) | 2 / 2 | 0 | 0 |
| text-origin | `pair_textorigin_report.py` | 38 / 38 | 0 (0 / 0) | 6 / 6 | 0 | 0 |
| multi-run | `pair.py` | 12 / 12 | 0 (0 / 0) | 8 / 8 | 0 | 0 |

`text-origin` is the TextField text-origin and selection-colour gate (decisions 12, 13 and 14, commits ddff82031, 09e184945 and d07df2581 and the y gate of 15 October); it is included. `ime` is the IME range gate of decision 15, new on 15 October; the findings that opened this pass (marked-text range, 2-3 px clock translation, text-origin y, control x, alert default button, text position and colour) are all gated now (decisions 14 to 19).

## A. Findings: seeded faults no gate caught, with no documented reason

None.


## B. Faults not caught that a decision or the gate's contract says are not gated

Listed so the gaps are visible; nothing here was changed.

- **pixel / px-excl / glyph-removed**: the '+' glyph removed from the excluded region. Reason: decision 2: the named glyph region is excluded from the pixel gate (the case has no text/colour gate).
- **pixel / px-excl / glyph-moved-5px**: the '+' glyph 5 px (2 pt) off inside the excluded region. Reason: decision 2: the named glyph region is excluded from the pixel gate (the case has no text/colour gate).
- **semantic / sem-click / focus-flag**: wrong focus owner (UIA flag). Reason: docs/sr1-status.md block 14 caveat and sr1-decisions D7: UIA keyboard focus is false in the Sandbox; focus is gated through @FocusState text, not the UIA flag.
- **semantic / sem-alert-three / default-button-uia-focus**: wrong default button: UIA keyboard focus on Third. Reason: docs/sr1-status.md block 14 caveat and sr1-decisions D7: UIA keyboard focus is false in the Sandbox; focus is gated through @FocusState text, not the UIA flag.
- **semantic / sem-focus-tab / focus-flag-wrong-field**: wrong focus owner (UIA flag on the other field). Reason: docs/sr1-status.md block 14 caveat and sr1-decisions D7: UIA keyboard focus is false in the Sandbox; focus is gated through @FocusState text, not the UIA flag.

## C. Near-misses that failed (over-strict gates)

None. Every near-miss placed exactly at or just inside a tolerance (edge-aa 32, hazeTolerance 3, C2 1 px and the spring's 2 px for extent and edges, progress 0.004/0.005, text bbox 1 px, button/list label ink 40, button label centring 3 px, toggle label centring 1 px, row frames 1 px, text-colour 24, text-origin y envelope, semantic bounds 0.05 pt) passed.


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
| line2-down-2px | fail |

## E. Gates and properties not calibrated offline

- **Real IME / TSF / Narrator behaviour**: needs Windows hardware; the Sandbox drives IME in-process (decisions B6, D8). Only the comparators on those dumps are calibrated.
- **UIA keyboard focus and OS-level focus restore**: UIA reports no keyboard focus in the Sandbox (decision D7), so the gates never read it; nothing to calibrate offline.
- **The capture hosts themselves (Windows renderer paint, Mac NSHostingView / AXDump / AlertHooks / MAC_FACT writers)**: they produce the evidence the comparators read; checking them needs new captures, which this pass excludes. Mutations assume the recorded Mac side is the truth.
- **Case-level options no shipped case exercises (the full "bounds" semantic field with boundsTolerancePt, a non-zero firstInkTolerancePx or selectionStartTolerancePx, the dark/pressed/focused button states, scales 1.25 and 1.5)**: there is no real run evidence to mutate; unit tests in factory/tools/test_pair_*.py cover bounds, default button and tolerance on synthetic dumps only.
- **Runtime unit suites (Swift: runtime 333, host 121, bridge 51) and the consolidation driver (factory/pipeline/consolidation/run_all.py)**: they are not run-evidence comparators; the driver records pair.py's exit status, which the harness does exercise.
- **What the default-button gate reads (decision 17)**: the Windows host's request to the TaskDialog (HOST_DIALOG_REQUEST default=N in the host log), not an observation of the dialog: UIA cannot show it (D7). That the TaskDialog honours the request is the Enter case's behaviour check (default-enter-v1), and a host log that lies about its own request is not mutated beyond the edits listed.
- **Non-ASCII composed text in the IME gate (decision 15)**: the Windows host log is written in the console code page, so only the ASCII prefix and the presence of a continuation are compared from the logs; the exact characters are compared on the final frame by the semantic gate from UIA values, and the intermediate non-ASCII steps are not compared character by character.
- **Leading-edge tolerance of the clock gate (decision 18)**: the leading edge measured 0.000 px on every committed clock run but is gated at the named 1 px (springs 2 px), so a 1 px translation of a 1 px case and a 2 px translation of a spring case pass by design.
- **Provenance gates (stage identity in build.json, renderer sha256, receipts)**: the lean loop (decision 4) records them but no comparator reads them; earlier provenance fault controls live in factory/pipeline/paired-five-seeded-observations-actual-v4/fault-controls.json.

## F. Earlier coverage this pass builds on

- `factory/VERIFICATION.md`: F8 timing selftest, 15 fault controls on synthetic timing (predates SR1; does not touch the pair.py comparators).
- `factory/pipeline/paired-five-seeded-observations-actual-v4/fault-controls.json`: 10 provenance-receipt faults rejected (receipt gate, not pixels or semantics).
- `factory/tools/test_pair_control_report.py`, `test_pair_semantic_report.py`, `test_pair_textorigin_report.py`: unit tests on synthetic inputs (they passed at 668bab00e; not re-run on 15 October: the workspace hook forbids local test execution); none uses real run evidence, and no test existed for the pixel, text, text-colour, button, list, clock, image or ime gates.

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
| h34-switch | `blocks-6-10/swiftui.toggle/switch-labelled-on-v1` | 20261017-000201 |
| h34-textdark | `blocks-17-20/swiftui.color-scheme/text-dark-v1` | 20261017-000201 |
| h34-textfield-auto | `blocks-6-10/swiftui.textfield/automatic-style-v1` | 20261017-000201 |
| h34-textfield-plain | `blocks-6-10/swiftui.textfield/plain-v1` | 20261017-000201 |
| img-star | `pilot-delivery-five-v1/text-shape-image/image-system-star-fill-v10` | 20261013-221400 |
| line-limit-ml | `blocks-26-34/swiftui.system-font/line-limit-v1` | 20261017-014524 |
| list-arrow | `blocks-11-16/swiftui.list/arrow-keys-v1` | 20261013-224316 |
| list-var | `blocks-11-16/swiftui.list/variable-rows-selected-v1` | 20261014-025727 |
| px-edge | `pilot-delivery-five-v1/text-shape-image/rounded-stroke-host-v1/continuous-geometry-delivery-v2` | 20261014-163619 |
| px-exact | `blocks-6-10/padding-frame/frame-alignment-v1` | 20261014-171910 |
| px-excl | `pilot-delivery-five-v1/stack-layout/stack-overlay-centered-execution-v9` | 20261014-165602 |
| px-fractional | `blocks-6-10/padding-frame/nested-fractional-v1` | 20261014-173407 |
| px-haze | `blocks-17-20/swiftui.color-scheme/switch-on-dark-v1` | 20261014-162645 |
| px-ties | `blocks-6-10/pixel-ties/layout-v1` | 20261014-182749 |
| rowtol-grid13 | `blocks-w1-f2/swiftui.system-font-f2/grid-13-v1` | 20261015-152228 |
| rowtol-serif | `blocks-w1-f2/swiftui.system-font-f2/design-serif-v1` | 20261015-151417 |
| sem-alert-confirm | `blocks-17-20/swiftui.alert/confirm-delete-v1` | 20261014-224327 |
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
