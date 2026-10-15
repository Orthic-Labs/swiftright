# Blocks 26-36, SR1 round 5: closing the Pulse hub's Windows gaps

Requested by the Pulse hub track (`docs/pulse-hub-windows-port.md`). Same shape as `../blocks-24-25` and `../blocks-21-23`: `make_cases.py` stamps `package/` + `mac-source/` (byte-identical Witness) and `pair.json` for every case (`new-case.py`); hosts are the pinned blocks 11-16 / 17-20 hosts (`shared-windows-host`, `shared-mac-host`, `shared-mac-host-dark`; ScalePin, decision C12); `python3 run_round5.py <stage> [--only substring] [--recompare]` runs every case at N=20 through the Sandbox and appends one record per case to `../consolidation/results.jsonl` (`--recompare` re-evaluates changed gates on the captures of the latest run, no new capture). `python3 summarise_round5.py` merges the passing records into `../consolidation/consolidation-table.json`. Decisions: F1-F4, F9-F13 (this round), F5-F8 and F14-F16 (block 29), F17-F22 (block 35) in `docs/sr1-decisions.md`.

| Block | Directory | Cases | Gate |
| --- | --- | --- | --- |
| 26 text-views | `swiftui.text-views` | text-verbatim, anyview, view-id, view-modifier, state-initial, builder-single, color-clear, color-opacity | pixels (exact or glyph regions named) + semantic tree after every event |
| 27 layout-priority | `swiftui.layout-priority` | two-views, three-levels, fits, through-wrappers, vertical, with-spacer | pixels, exact |
| 28 system-font | `swiftui.system-font` | sizes, sizes-large, weights, fractional, styles-large, styles-small, style-weight, truncate, line-limit | text position gate per row (first glyph, baseline, mid-point, first ink column), line bands, ink stays in frame, colour, semantic tree |
| 29 system-symbols | `swiftui.system-symbols` (`make_cases_symbols.py`) | body-all, frame16, frame20, size28, size28-b, sizes, text-styles, sizes-interpolated, weights | symbol gate (frame, ink box within 1 px, tint, exact outside the cells) |
| 30 continuous-shape-large | `swiftui.continuous-shape-large` | pill, radius-range, stroke-large-radius, zero-size | pixels, edge band with a named `edgeAATolerance` (F4) |
| 31 paint-states | `swiftui.paint-states` | transparent-fills, transparent-fills-dark, divider-light, divider-dark | pixels, exact |
| 32 accessibility | `swiftui.accessibility` | value, hidden, element, traits, hint | UIA tree vs Mac AX dump (role, name, value, enabled, count, order) |
| 33 baseline-alignment | `swiftui.baseline-alignment` | first-baseline, padding, frame, nested, last-baseline | baseline relation equal to the Mac's within 1 px (pixels report only) + colour |
| 34 textfield-axis | `swiftui.textfield-axis` | rounded, plain | text-field gates of decisions 12 and 14 |
| 35 image-data | `swiftui.image-data` (`make_cases_imagedata.py`) | exact-opaque, alpha-blend, scaled-down | semantic tree (image bounds) + pixels (exact; scaled-down with a named tolerance) |
| 36 button-dark | `swiftui.button-dark` | states, states-disabled | button gate on a dark ground (several buttons per capture) + text-colour gate |

Witnesses whose layout would depend on a font's line height use frames (`font_rows`, `baseline_case`); the dark cases use the full-viewport dark host (`--dark-host`, `case(..., dark=("darkAqua", "dark"))`).
