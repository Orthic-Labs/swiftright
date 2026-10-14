# Blocks 24 (swiftui.list-row-style) and 25 (swiftui.font-custom), SR1 round 4 extension for the Pulse hub

Same shape as `../blocks-21-23` and `../blocks-11-16` (`make_cases.py` stamps `package/` + `mac-source/` with a byte-identical Witness; hosts are the pinned blocks 11-16 hosts, decision C12; the Mac host also takes `--fonts`).
`python3 run_round4.py <stage> [--only substring] [--runs N]` runs every case at N=20 and records `consolidation/results.jsonl`.

## Block 24: list row style (list gate + pixels)

`sep-hidden-all`, `sep-hidden-some`, `bg-colour`, `bg-view` (a Rectangle filled with a Color), `plain-sep-hidden`, `plain-bg-colour`, `selected-bg`, `plain-selected-bg`, on an inset and a plain `List` (5 rows, 200 x 160 pt) with the lane A list gate (rows, text, order, selection, frame). Decision E10. `.listStyle(.sidebar)` is not delivered (E13).

## Block 25: custom font (text gate)

`title-32`, `sizes` (13 / 18 / 31 pt), `uppercase-string`, `colour`, `two-lines`, `text-case-uppercase` (`.textCase(.uppercase/.lowercase)`, with the semantic tree). The font is a parameter (`FONT_FILE`, `FONT_NAME` at the top of `make_cases.py`; bundled Tinos Regular until the hub's confirmed display font arrives); after changing it run `make_cases.py` then `fit_text_regions.py` (it measures each Mac capture and writes the text-gate rectangle, the named excluded region and the colour-gate region). Layout rule and what is not delivered: decisions E12, E14.
