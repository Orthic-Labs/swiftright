# F-path P0 spike: host PathRasterizer vs SwiftUI ImageRenderer (20 Oct 2026, Mac, scale 2.5)

Tool: `probes/sr0-s/fresh-runtime/Tools/PathParitySpike` (each case in its own process: ImageRenderer returns the previous image when a view renders nothing, which made a batch run report `ring-trim-zero` wrong).

| Case | outside 1 px band | band max | band sd | verdict vs 32-level gate |
|---|---|---|---|---|
| ring-trim-round | exact | 65 | 19.5 | over |
| ring-trim-dashed-butt | exact | 255 (a few dash ends off by up to 1 px) | | over |
| ring-track-dashed | exact | 179 (same) | | over |
| ring-trim-tiny | exact | 41 | 12.6 | over |
| ring-trim-zero | exact (SwiftUI draws nothing; so does the runtime) | 0 | | PASS |
| path-fill-nonzero | exact | 42 (2 star-tip px) | 3.5 | over (2 px) |
| path-fill-evenodd | exact | 82 (2 star-tip px) | 5.1 | over (2 px) |
| path-joins | exact | 140 (inner join apex, 4 px) | 9.4 | over |
| path-curves | exact | 81 | 12.1 | over |
| stroke-hairline | exact | 24 | | PASS |
| dash-phase | exact | 1 | | PASS |

Findings
- Geometry matches SwiftUI in every case (0 differing pixels outside the edge band): arc direction, ellipse start, trim by arc length, trim(0,0) empty, dash phase, fill rules, joins, curves.
- Fills: edge coverage within a few levels except single pixels at sharp star tips.
- Strokes: the 16x16-supersample + smoothstep coverage leaves edge error sd 10-20 (max 65-140). Tighter flattening (0.02 px) made it worse, so CoreGraphics strokes do flatten near 0.2 px (as the existing ContinuousRoundedRasterizer fit found).
- Dashes: positions match to 0.1 deg at 32 of 36 dash edges; four ends sit up to 1 px apart. Laying dashes out by true arc length, and cutting stroke ends square to the exact curve tangent, did not move them.
- Next: either fit CoreGraphics' stroke coverage further, or gate strokes with named measured tolerances (edge band) plus a dash-geometry check (dash count and edge angles within 1.5 deg) instead of exact pixels at dash ends; decision to record in docs/sr1-decisions.md before P3.
