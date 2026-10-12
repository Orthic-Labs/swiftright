**1. Verdict: at-risk.** None of the original five is qualified. Rectangle fill has a real 20/20 paired observation; the other four have no completed Windows capture, two have no artifacts at the listed paths, and ZStack/overlay is absent from the pipeline entirely.

**2. Findings**

- **Rectangle evidence is observed.** All 20 rows are true, every RGBA is 255,56,60,255, every bbox is 40×20 DIP, and qualified:false is hard-coded, `comparison-count20-r1.json:1865-1871`. But it is only an observation: the comparator pins the Mac oracle by relative path and the source hash by literal, `compare-rectangle-color-v1.py:8,36`, so no source, case or tuple join exists.
- **Geometry channel is asymmetric.** Mac plain.png is a 40×20 crop, so its bbox is always origin-relative while the Windows bbox is viewport-relative, `compare-rectangle-color-v1.py:24,32`. A Mac-side placement shift would pass. Top-leading is evidenced on Windows only; the ledger overstates the Mac side.
- **Capture scales differ.** Mac is 1x, hard-coded at line 32 and confirmed by 40×20 pixels; Windows is 2.5x. Solid fill is scale-invariant, so Rectangle passed. Rounded stroke, Image and Text will show edge differences that are capture artefacts, not defects. This blocks every remaining paired20.
- **Generated final remote entry cannot run.** `Test-Path -LiteralPath $a -or Test-Path ...` hands `-or` to Test-Path as a parameter and throws under Stop, `prepare-pilot-final-build-v1.py:362`. It fails closed, but every Image, Rounded and Layout final build through it stops before copying inputs.
- **Native-capture prep is Rectangle's donor graph with text substitution.** Pin replacement covers ps1, cs, py and md only, `prepare-pilot-native-capture-v1.py:139-143`; the JSON-side source-hash literal at lines 104 and 108 is truncated and never matches. Unrebuilt donor JSON would keep Rectangle pins. Grep the generated `sources/` for the Rectangle case id and exe hash before staging.
- **Recipes are synthesised by the finalizer** with reviewer root, empty stimuli and a literal acceptanceConfigHash, `prepare-pilot-final-build-v1.py:98,125-153`. Observation grade, not the reviewed recipe of `sr1-plan.md:128-132`.
- **Two listed sources do not exist**: `sf-symbol-ticket.md` and the bundled-font `main.swift`. Host choices at `prepare-pilot-five-compile-v1.py:4` have no ZStack/overlay or bundled-font packet, and the ledger never mentions ZStack/overlay.
- **Tuple drift.** SR1 pins renderer e280f4a9 while SR0's candidate is 7578cd5d, `docs/sr0-status.md:9`. Under `sr1-plan.md:98`, closure on tuple 12 invalidates every current SR1 verdict. All of it is spike evidence.
- **ABI 0.7.** `sr1-plan.md:15`, `docs/sr0-sr1-running-holds.md:17-18` and `docs/sr0-status.md:52` all say proposals only until a recorded freeze. Relayed peer text does not override Adrian's accepted plan; root is right to refuse. In scope now: write the append-only 0.7 proposal, and test whether Layout proposal records can be exported from the Swift runtime, which is additive and authorised at `sr1-plan.md:8-9`.

Qualified original blocks: zero. Rectangle fill is an observed half of block one.

**3. Next three actions**

1. **Fix the capture join first.** Render the Mac offscreen witness at the Windows scale, capture the full Mac viewport instead of the crop, read Mac scale from compositor.raw.json, then rerun Rectangle Count1 on both hosts plus one Mac-side shift mutation the comparator must reject, `sr1-plan.md:196-198`. This gate work is necessary; otherwise no remaining comparison can separate defects from capture artefacts.
2. **Finish block one.** Fresh Rounded-stroke packet with the exact argv contract and the Test-Path fix, then final build, Count1, Count20, paired against a matched-scale Mac20. Push ZStack/overlay through the same path next; it is the cheapest missing block.
3. **Prove bundled-font selection by paint.** Process-register a canary font with an unmistakable glyph, capture Count1 on both hosts through the 37429120 runtime's Font.custom, then repeat with Tinos. No renderer change needed.

**4. Safety, cleanup, holds**

- `prepare-pilot-five-compile-v1.py:37,96` runs scp pull and push while reporting nativeActions 0. Bounded, but it is a transport action; run it under supervise-job.
- Zips land in `~/Library/Caches/SwiftRightFactory`, outside the checkout, against `factory/AGENTS.md:3,11`. Add to cleanup.
- Compile prep pulls its helper from the live Dell rectangle stage at line 37. Archive that hash-pinned file into the repo before retiring Rectangle stages, or the next prebuild breaks.
- `supervise-job-v2.py` signals only its own group and fails closed on inventory loss, lines 101-109 and 176-178. No issue.
- Genuine holds: SR0 freeze, ABI 0.7, W08, Narrator, Mac recorder signing. SF Symbol needs an Adrian decision, not a hold: Apple's SF Symbols terms likely bar shipping the glyphs on Windows; if verified, the block is `unsupported` under AD5, `sr1-plan.md:72-73`, and the pilot needs a stated replacement. Unverified here: session terminality, Image and Rounded prebuild receipts, fresh Mac observations.

Next action: repair the capture-scale and full-viewport join, then rerun Rectangle Count1 on both hosts with one Mac-side shift mutation.
