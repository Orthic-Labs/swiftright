# swiftui.system-font (block 28) facts

Issue #7. Source: diagnostic CI run 38984400470, N=3 at 6c69c61fb, run dir `20261017-000201` of each case (`text-colour-report.json`, `position` block of every region). Method: Windows minus Mac, capture px (scale 2.5), exactly as `blocks-w1-f2/position_stats.py` `observations()`: dx = firstInkX, dy = firstInkY, db = baselineY, dc = (dy+db)/2. Row keys come from `witness_keys()` (the `.font(...)` expressions in source order). All three runs of every case gave identical numbers (zero run-to-run variance), so the table has one line per row.

## Per-row signed deltas (px; w - m)

| case | row | key | dx | dy | db | dc | inkHeight d | tolerance in pair.json (dy,db,dc,dx) | verdict |
|---|---|---|---|---|---|---|---|---|---|
| fractional | 0 | 11.5 regular | 0 | +1 | 0 | +0.5 | +1 | 1,0,0.5,0 | ok |
| fractional | 1 | 12.5 regular | 0 | +1 | 0 | +0.5 | +1 | none (unfitted) | fail dy, dc |
| fractional | 2 | 11.5 semibold | 0 | +1 | 0 | +0.5 | 0 | none (unfitted) | fail dy, dc |
| fractional | 3 | 13 medium | 0 | +1 | 0 | +0.5 | +2 | 1,0,0.5,0 | ok |
| line-limit | 0 | 12 regular, lineLimit(2), text wraps to 3, truncated | 0 | -2 | -2 | -2 | +1 | 1,0,0.5,0 | fail dy, db, dc |
| line-limit | 1 | 12 regular, lineLimit(3), 3 lines | 0 | -1 | +1 | 0 | +2 | 1,0,0.5,0 | fail db |
| line-limit | 2 | 12 regular, lineLimit(3), 2 lines | 0 | -1 | -1 | -1 | +1 | 1,0,0.5,0 | fail db, dc |
| sizes-large | 0 | 24 regular | +1 | +1 | 0 | +0.5 | +3 | 1,0,0.5,1 | ok |
| sizes-large | 1 | 28 regular | +2 | 0 | -1 | -0.5 | +4 | none (unfitted) | fail db, dc, dx |
| sizes-large | 2 | 32 regular | +2 | +1 | 0 | +0.5 | +5 | 1,0,0.5,2 | ok |
| sizes | 0 | 11 regular | 0 | 0 | 0 | 0 | +2 | 0,0,0,0 | ok |
| sizes | 1 | 12 regular | 0 | +1 | 0 | +0.5 | +1 | 1,0,0.5,0 | ok |
| sizes | 2 | 13 regular | +1 | +1 | 0 | +0.5 | +2 | 1,1,0.5,1 | ok |
| sizes | 3 | 15 regular | 0 | 0 | 0 | 0 | +2 | none (unfitted) | ok (zero delta) |
| sizes | 4 | 18 regular | +1 | +1 | 0 | +0.5 | 0 | none (unfitted) | fail dy, dc, dx |
| style-weight | 0 | body.bold() | 0 | +1 | 0 | +0.5 | +1 | 1,0,0.5,0 | ok |
| style-weight | 1 | headline.weight(.regular) | +1 | +1 | 0 | +0.5 | +2 | none (unfitted) | fail dy, dc, dx |
| style-weight | 2 | title3.weight(.semibold) | 0 | 0 | 0 | 0 | +2 | none (unfitted) | ok (zero delta) |
| styles-small | 0 | subheadline | 0 | 0 | 0 | 0 | +2 | 0,0,0,0 | ok |
| styles-small | 1 | body | +1 | +1 | 0 | +0.5 | +2 | 1,0,0.5,1 | ok |
| styles-small | 2 | callout | 0 | +1 | 0 | +0.5 | +1 | 1,0,0.5,0 | ok |
| styles-small | 3 | footnote | 0 | 0 | 0 | 0 | +1 | 0,0,0,0 | ok |
| styles-small | 4 | caption | 0 | 0 | 0 | 0 | +1 | 0,0,0,0 | ok |
| styles-small | 5 | caption2 | 0 | +1 | +1 | +1 | 0 | 0,0,0,0 | fail dy, db, dc |
| truncate | 0 | 12 regular, 1 line in 240x40 frame | 0 | +1 | -1 | 0 | +1 | 1,0,0.5,0 | fail db |
| truncate | 1 | 11.5 regular, same frame | 0 | +1 | -1 | 0 | +1 | 1,0,0.5,0 | fail db |
| truncate | 2 | 13 semibold, same frame | 0 | +1 | -1 | 0 | +1 | 1,0,0.5,0 | fail db |
| truncate | 3 | 18 regular, same frame | 0 | 0 | 0 | 0 | 0 | none (unfitted) | ok (zero delta) |
| truncate | 4 | 12 regular "Short", same frame | 0 | +1 | -1 | 0 | -2 | 1,0,0.5,0 | fail db |
| weights | 0-5 | 18 ultraLight, thin, light, regular, medium, semibold | +1 | +1 | 0 | +0.5 | +2,+2,0,0,0,0 | none (unfitted) | fail dy, dc, dx |
| weights | 6-8 | 18 bold, heavy, black | 0 | +1 | 0 | +0.5 | -1,-3,-3 | none (unfitted) | fail dy, dc |

Raw extraction: `position_stats.py` logic over `runs/20261017-000201/text-colour-report.json` (script not committed; numbers reproducible with `observations()` on those files).

## Cause per failing row

1. Unfitted key, delta is ordinary: 12.5 regular, 11.5 semibold, 28 regular, 18 regular, 18 at every weight, headline regular. Deltas are the same size as fitted neighbours (dy +1, dc +0.5, dx 0..+2; 28 pt db -1 is the only baseline miss among these). Cause as G71 (a): no fitted tolerance, gated at 0.
2. Fitted key but wrong key set for it: caption2 (dy +1, db +1). Consistent with G71 (b), one text and one placement per font in F2; the value is also a +1 baseline, which F2 never saw on any key except 13 regular (db fitted 1).
3. NOT a key problem, placement context: truncate rows 0, 1, 2, 4 and line-limit rows 0-2. Same fonts as fitted keys (12, 11.5 regular, 13 semibold), but db -1 (truncate) and -2/+1/-1 (line-limit). Evidence: within truncate, the 18 pt row in the same 240x40 frame has db 0 while the 11.5, 12 and 13 pt rows all have -1; in `sizes` the plain 12 pt row has db 0, in truncate the same key has db -1. 11.5 regular has db 0 in fractional and db -1 in truncate. A per-key tolerance cannot represent this: one key reads different deltas by case. The rows sit in fixed-height frames (40 and 60 DIP) with vertical centring (truncate) or a multi-line block (line-limit). line-limit rows 0 and 2 both measure 2 bands but give -2 and -1, so the block height of a truncated (ellipsis) 2-line text differs from a natural 2-line text. These are hypotheses about the cause; the data fixes only that the delta depends on the context and not on the key.
4. Not a measurement gap either: sizes-large 28 pt dx +2 and the 18 pt dx +1: width/left bearing of Segoe vs SF at the key; consistent with 24 and 32 pt (dx +1, +2).

## Fit status

- No mapping table needs these values. The Windows side takes Mac line height and first baseline from the generated F1 table (`FontMetricTableData.swift`, header "do not edit"; Mac-measured; `SystemFontMapping.swift` `dip()`); baselines in the new data agree with the Mac to 0 px on 29 of 38 rows (the nine others are the truncate, line-limit, 28 pt and caption2 rows above). The only per-key values the gate reads are the tolerances in `pair.json` (fitted by `position_stats.py --write` from the F2 FIT set).
- Fitting the unfitted keys from these 3 runs would mean writing tolerances from the GATE set (the method in `position_stats.py` and G71 forbids tuning on GATE, and a tolerance written after a failing gate is a widening). Not done. No tolerance, pair.json, row-tolerances.json or runtime file was changed.
- What a fit needs (G71, caveat 1): an N=20 FIT capture on the F2 witness (varied texts and placements, not more runs of these cases) for 12.5 regular, 11.5 semibold, 18 (nine weights), 28 regular, headline regular, title3 semibold, 15 regular; plus caption2 and 12 pt in more than one text and one placement. Caveat on this: a per-key fit cannot cover the truncate/line-limit rows until the context dependence (item 3) is resolved in the text layout (owned by another lane) or the gate is keyed by context.
