#!/usr/bin/env python3
"""Build docs/proven-controls.json from the SR1 consolidation sources.

Sources (read-only): factory/pipeline/consolidation/consolidation-table.json,
factory/registry/manifest.json, docs/sr1-status.md, the Witness.swift of each case, and
factory/pipeline/consolidation/results.jsonl (stage id).

  python3 factory/tools/proven-controls/generate.py          # write docs/proven-controls.json
  python3 factory/tools/proven-controls/generate.py --check  # exit 1 if the file drifted

Only the OVERRIDES below are hand-set (status the sources do not yet say); everything else is derived.
Output is deterministic (no clock, sorted keys), so --check is a byte comparison.
Use --check as the CI/pre-commit hook: it needs only python3 and the checkout.
"""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "docs" / "proven-controls.json"
TABLE = ROOT / "factory/pipeline/consolidation/consolidation-table.json"      # rounds 4 and 5 (blocks 21 and up)
RESULTS = ROOT / "factory/pipeline/consolidation/results.jsonl"
CLOSURE_TABLE = ROOT / "factory/pipeline/closure/closure-table.json"          # the final closure run of blocks 1-20 and the pixel-ties (one stage)
CLOSURE_RESULTS = ROOT / "factory/pipeline/closure/results.jsonl"
MANIFEST = ROOT / "factory/registry/manifest.json"
STATUS = ROOT / "docs/sr1-status.md"

# status-doc block number -> manifest block id (pixel-ties has no manifest block)
NUM2ID = {1: "swiftui.shapes.fill-stroke", 2: "swiftui.image", 3: "swiftui.stack-overlay",
          4: "swiftui.text.bundled-font", 5: "swiftui.custom-layout", 6: "swiftui.scroll-view",
          7: "swiftui.toggle", 8: "swiftui.disabled", 9: "swiftui.padding-frame",
          10: "swiftui.preference-key", 11: "swiftui.button", 12: "swiftui.binding",
          13: "swiftui.textfield", 14: "swiftui.focus-state", 15: "swiftui.ime-marked-text",
          16: "swiftui.list", 17: "swiftui.alert", 18: "swiftui.animation",
          19: "swiftui.opacity-transition", 20: "swiftui.color-scheme",
          21: "swiftui.observation", 22: "swiftui.task-asyncstream", 23: "swiftui.spacer-divider",
          24: "swiftui.list-row-style", 25: "swiftui.font-custom",
          26: "swiftui.text-views", 27: "swiftui.layout-priority", 28: "swiftui.system-font", 29: "swiftui.system-symbols",
          30: "swiftui.continuous-shape-large", 31: "swiftui.paint-states", 32: "swiftui.accessibility", 33: "swiftui.baseline-alignment",
          34: "swiftui.textfield-axis", 35: "swiftui.image-data", 36: "swiftui.button-dark",
          37: "swiftui.slider", 38: "swiftui.on-hover", 39: "swiftui.uia-walk", 40: "swiftui.ime-traps", 41: "swiftui.compat"}

# Round-4 blocks (requested by the Pulse hub track): passed at N=20 on their stage, no independent review yet. Provisional use only; remove a block from this set
# when its review lands and docs/sr1-status.md records it.
ROUND4_CAVEATS = {
    "swiftui.observation": ["No `.environment(model)` / `@Environment(Model.self)`; a `@Bindable` binding is proven through a Button, not a click on a Toggle.",
                            "A view whose inputs and environment did not change keeps its body (SwiftUI rule); the comparison is conservative: a closure or Binding field always re-runs the body."],
    "swiftui.task-asyncstream": ["Events are pumped by clicks, not timers: no `Task.sleep` timing is gated.", "A cancelled task's code after its loop still runs (as in SwiftUI)."],
    "swiftui.spacer-divider": ["Divider is proven in the light appearance only (the dark Divider throws); Spacer/Divider not proven inside List, ScrollView or LazyVStack.",
                               "Spacer(minLength: nil) is 8 pt and a default stack spacing is 0 beside a Spacer (measured)."],
    "swiftui.list-row-style": ["`.listStyle(.sidebar)` is not delivered; `.listRowBackground` draws a Color or a Rectangle filled with a Color only (another view fails visibly).",
                               "`listRowSeparator(edges:)` is accepted; top and bottom are not told apart. A row background replaces the selection highlight."],
    "swiftui.font-custom": ["Proven on bundled Tinos Regular only; the hub's real display font (Tanker, licence unconfirmed) is not bundled or gated.", "`.tracking`/`.kerning`, other weights and a 28 pt title are not delivered; text frames must be the line height plus a multiple of 4 pt (Windows text-run matching on half-pixel ties).",
                             "Glyph pixels are gated by the text gate (ink box within 1 px), not exact (DirectWrite vs CoreText)."],
}
# Round-5 blocks (closing the Pulse hub's Windows gaps, factory/pipeline/blocks-26-34): passed at N=20 on their stage, no independent review yet.
ROUND5_CAVEATS = {
    "swiftui.text-views": ["`AnyView` is transparent: a bare AnyView cannot be a graph root (wrap it in a user view).", "`Text(verbatim:)` has no localisation lookup (the runtime has none)."],
    "swiftui.layout-priority": ["A priority set beneath `padding` or a frame modifier does not forward (measured); only HStack/VStack distribution is proven, not Layout protocol containers."],
    "swiftui.system-font": ["Segoe UI at the requested size: Windows lines are 1-3 pt taller from 15 pt up and glyphs a little larger; the text position gate carries per-row tolerances (decisions G71, G74-G77).",
                            "`Font.width` is carried, not drawn; serif, rounded and monospaced designs are refused; `lineLimit(n)` truncation falls back to the ellipsis alone when nothing fits (macOS clips instead)."],
    "swiftui.system-symbols": ["Shapes are Segoe Fluent Icons, never gated (12 weak mappings); regular, semibold and bold font-sized symbols only; only star.fill keeps a resizable layout.", "Sizes between the measured ones are interpolated."],
    "swiftui.continuous-shape-large": ["The anti-aliasing differs from Apple's on large-radius shoulders: named edge-AA tolerances 130-220 (decision F4); a stroked pill is NOT delivered (SwiftUI's stroker draws ticks)."],
    "swiftui.paint-states": ["Light and dark Divider and transparent fills only; a bordered Button under `.opacity` is still refused."],
    "swiftui.accessibility": ["`accessibilityHint` is accepted but not published (no ABI field); `accessibilityValue` on a Text, and the header and link traits, are NOT delivered (decision F10)."],
    "swiftui.baseline-alignment": ["Pixels are report-only: the baseline relation to the Mac decides (Segoe UI and SF baselines differ in absolute position); HStack only."],
    "swiftui.textfield-axis": ["`axis: .vertical` is the single-line field: no growth over several lines and no wrapping (decision F9)."],
    "swiftui.image-data": ["PNG and ICO only through the Swift decoder (the wave-0 WIC/ImageIO service exists behind `ImageDecoder.backend = .system`); no Adam7; the scaled-down box filter differs from CoreGraphics by a named tolerance.", "Windows-vs-Mac decode is exact for sRGB-untagged 8-bit data only."],
    "swiftui.button-dark": ["Bordered Button under `.opacity` and a foreground style on a bordered Button are not modelled; the dark corner outline is the light one."],
}
# Round-6 blocks (factory/pipeline/blocks-37-38, decisions H1-H9): passed at N=20 on their stage, no independent review yet.
ROUND6_CAVEATS = {
    "swiftui.slider": ["The thumb is drawn from artwork fitted to the Mac's macOS 27 slider at scale 2.5 (H4); a thumb on an exact half device pixel rounds up here, where the Mac rounds half of those down (H2), so the cases use values that avoid the ties.",
                       "The Mac applies clicks, drags and keys through the accessibility value and increment (a stand-in, H5); Windows receives real posted pointer and key messages. Home, End, PageUp and PageDown are specified, not measured on the Mac."],
    "swiftui.on-hover": ["Hover and tap are specified (H6), and the Mac side is a witness stand-in (H5): the offscreen Mac window never receives pointer events, so the Mac counts come from the witness.",
                         "A view with a tap gesture publishes one pressable node named by its text (H7); the Mac tree shows its Text as static text, so the trees are not compared for these cases."],
    "swiftui.uia-walk": ["Controls-a pixels are report-only. Controls-b pixels decide only inside its list rect (H20); the semantic tree is gated for every control kind listed in the case.",
                         "Controls-b passes N=20 in CI run 38872207896 (stage f81244b4f-9ce7a09e, commit f81244b4f, renderer 0.10 at scale 2.5): the semantic tree, the list gate and the list-rect pixels, after the H21 gutter. Controls-a passes N=20 in run 38854967920.",
                         "H16 rows are covered by the list-rect region pixel gate plus listGate (H20, H21), and the offscreen Mac harness exposes no row content, so the rows are not compared semantically.",
                         "H21: the scroller gutter applies only when the list overflows with legacy scrollers; the CI Mac is pinned to legacy (`factory/tools/mac-accessibility.sh`). An overflowing List clips on Windows with no scroll bar drawn (a known gap). Unproven: that overlay scrollers take no gutter. Every runner logged `ax.scrollerStyle=overlay` before the pin, yet the pre-pin run 38854967920 drew an AXScrollBar and the 16.8 pt gutter.",
                         "The semantic comparator folds a toggle's nested label into the Mac AX shape (H14): a switch's label is a sibling before an unnamed switch, a checkbox's duplicate label child is dropped; role, name, toggle, enabled, value, count and order are gated. Bounds are reported, not gated, and controls-a pixels are report-only, so no geometry of controls-a is gated.",
                         "Controls-b list rows are gated by pair_list_report.py (count, text, order, selected, frame within 1 px, label ink) and the list-rect pixels (H20), not by the semantic comparator (H16): the offscreen Mac harness's AX tree exposes its rows as AXUnknown with no content; a normal macOS List exposes AXRow/AXCell, which was not measured here.",
                         "An unlabelled `Image(systemName: \"star.fill\")` is named `Favorite`; the name comes from a measured SF-symbol description table that holds measured symbols only (one entry so far: star.fill, English, macOS 27). Other symbols fall back to the symbol name, which will not match the Mac."],
    "swiftui.ime-traps": ["Hardware IME is deferred: the cases drive the in-process TextStore script and the NSTextInputClient path, not a real IME (H9(b)).",
                          "Pixels are report-only on every block 40 case (`pixels: report-only`, H28, issue #3). Only the semantic gate decides: role, name, value and enabled of the two fields and the value line, in the end state. No text-origin or IME marked-range gate is declared, so intermediate composition state is not gated.",
                          "Extra CI evidence: `imet-badregion-v1` passes N=20 in run 38870003524 (stage 168328082-0766196a, commit 168328082) after the harness lease fix (H22); its mapped run stays 38860483220."],
    "swiftui.compat": ["Ported from OpenSwiftUI's MIT tests as view bodies and expectations only (H9a); EquatableView and animation completion are not ported and not delivered.",
                       "Runtime change (commit ce47755c3): `withAnimation` and `withTransaction` settle pending changes before their body (state-nested-update is the case that measured it). The onChange transaction handling was revised in 7796b0b81: each write commits under the innermost open transaction (inner wins; measured on the Mac in run 38913665384). Independently reviewed 16 October (PASS); block 41 has six measured cases (onchange-animation-v1 added).",
                       "Runtime transaction fixes (commit 5713ea1fe, H23; the onChange part was revised in 7796b0b81, see above): the transaction boundary is per graph (a weak graph registry, not the last-flushed graph); `onChange` writes inherit the triggering transaction with no mid-flush commit; a boundary settle outside a flush schedules a flush; `isErasedEmpty` stays single-modifier and is documented. Unit tests 434/434 at that commit. CI run 38865487951 (N=3): 38 of 39 cases pass; `ime-composing-v1` was lost to the fixed 10 s host lease, not to the change (it passes N=20 in run 38870003524 after H22)."],
}
ROUND4_CAVEATS.update(ROUND5_CAVEATS)
ROUND4_CAVEATS.update(ROUND6_CAVEATS)
# The 21 List cases (block 16's 13 and block 24's 8) re-pass at N=3 on f81244b4f (run 38872220871). Notes only: the status is unchanged.
LIST_NOTES = {bid: ["The 21 List cases re-pass at N=3 on stage f81244b4f-9ce7a09e (commit f81244b4f, run 38872220871), and the H21 gutter rule now applies to them: an inset List reserves the legacy scroller gutter only when it overflows. N=3 only; this note does not change the status.",
                     "H21 premise unproven: every runner logged `ax.scrollerStyle=overlay` before the pin, yet run 38854967920 drew a scroll bar and a 16.8 pt gutter. The gutter in the Mac capture is blank (no scroller drawn). An exact fit (document = viewport) and an overflowing plain list were not measured."]
              for bid in ("swiftui.list", "swiftui.list-row-style")}
PENDING_REVIEW = {"swiftui.observation", "swiftui.task-asyncstream", "swiftui.spacer-divider", "swiftui.list-row-style", "swiftui.font-custom"} | set(ROUND5_CAVEATS)

# Round 6 (blocks 37-41, the Pulse hub's Slider, onHover/onTapGesture and the prior-art items, factory/pipeline/blocks-37-38): a block is
# delivered-pending-review only when every one of its cases passes its gate at N=20 on the round's stage; the others stay not-delivered.
PENDING_REVIEW |= {NUM2ID[n] for n in range(37, 42)}

# Blocks 1-20 (final closure run, docs/sr1-status.md): every case passed its deciding gate on one stage; none is independently reviewed yet.
PENDING_REVIEW |= {NUM2ID[n] for n in range(1, 21)}

# Independent Oracle review of 15 October 2026 (docs/sr1-status.md, "Independent review, 15 October"). Blocks listed here leave
# PENDING_REVIEW: no caveats -> "delivered"; caveats (kept, merged with the round caveats above) -> "delivered-with-caveats".
# An optional "status" overrides the derived status (block 27 is narrowed and stays pending).
REVIEW = "oracle 2026-10-15"
REVIEWED = {bid: {"review": REVIEW, "caveats": []} for bid in
            [NUM2ID[n] for n in range(1, 21)] + ["cross-cutting.pixel-ties"] + [NUM2ID[n] for n in list(range(21, 27)) + list(range(28, 37))]}
REVIEWED["swiftui.text-views"]["caveats"] = ["Text position is ungated (the pixels and the semantic tree are)."]
# Re-delivery 17 October (issue #7, H37): Oracle PASS-WITH-CAVEATS on CI runs 38994003228, 38994825461 and 38995241565 (CI_RUNS, CI_CASE_RUN). The two frame-centring probes are not table rows, so they are not counted.
REVIEW_28 = "oracle 2026-10-17 (PASS-WITH-CAVEATS, G74-G77 re-delivery)"
REVIEWED["swiftui.system-font"] = {"review": REVIEW_28, "status": "delivered-with-caveats", "caveats": [
    "Proven at N=20 on staged tree f2322127 (stages d4267ce69, 1d309081d and 49680e32d; renderer-0.10-c13b62a4, sha 4afe19d0...); CI runs 38994003228, 38994825461 and 38995241565; 9/9 cases, every row, zero run-to-run variance.",
    "Every row passes on its fitted tolerance edge in at least one metric (typically first ink y +1 against 1 and mid-point +0.5 against 0.5); the tolerances equal the measured deltas, so the gate tests stability of a constant offset.",
    "The baseline tolerances of 12, 12.5 and 11.5 semibold (and 13 regular, G71) are 1 px, fitted on digit text that leads with a round glyph (overshoot, G75(a)); on fractional rows 1-2, sizes rows 1-2 and truncate rows 0 and 4 a 1 px (0.4 pt) upward shift passes.",
    "Multi-line rows (G77): the first line, the line count and every line's bottom within 1 px are gated; the observed line-bottom deltas are +/-1 (descender length and anti-aliasing), at that edge; a later line moved up by 2 px or moved right is not caught.",
    "Text width (SF vs Segoe advances) is reported, not gated: up to 12 px (4.8 pt) per row; truncation points follow it.",
    "Text that starts with a descender letter is not gated (the first-glyph metric reads glyph adjacency, G74); all block 28 rows start with H.",
    "The G74 fit's own gate is not independent (zero variance); block 28's captures are the independent check.",
]}
# Re-delivery under H34 (17 October, issues #4, #5, #6, #8): Oracle PASS-WITH-CAVEATS on CI run 38987638974 (N=20, commit 93c6fe320, decision H35).
REVIEW_H34 = "oracle 2026-10-17 (PASS-WITH-CAVEATS, H34 re-delivery)"
REVIEWED["swiftui.toggle"] = {"review": REVIEW_H34, "caveats": ["Label first ink x and leading x are gated at [0, +1] px (Windows minus Mac, H34 side bearing; measured +1 in 20/20 runs); the checkbox label-to-box gap at [0, +1] px. The text origin is not read directly in this block, so a +1 px origin drift would pass. The checkbox gap range has no seeded-mutation proof (s_h34 covers the switch only)."]}
REVIEWED["swiftui.textfield"] = {"review": REVIEW_H34, "caveats": ["Body-text first ink x is gated at [0, +1] px (H34 side bearing; +1 in 20/20 runs on six cases, 0 on submit-v1). The text origin is gated at 0 px only by the caret (caret-empty-v1, 40 = 40.00) and the selection start (submit-v1, 40 = 40); in the other five cases a +1 px origin drift would pass."]}
REVIEWED["swiftui.color-scheme"] = {"review": REVIEW_H34, "caveats": ["text-dark-v1 first ink x is gated at [0, +1] px (H34 side bearing; 22 against 23 in 20/20 runs). The other eleven cases draw no text, are untouched by H34 and stand on their N=20 pass at 58df259c5 and the post-F2 N=3 pass at fc4a39a89; they have no N=20 on the current stage."]}
REVIEWED["swiftui.textfield-axis"] = {"review": REVIEW_H34, "caveats": ["plain-v1 first ink x is gated at [0, +1] px (H34 side bearing; 252 against 253 in 20/20 runs) and scanned from the frame edge (scanInteriorPx 0); the origin is not read by caret or selection in this block. rounded-v1 stays at 0 px."]}
# Block 27 Text cases (16 October block gate, Oracle lift reviewed 17 October, H33): the eight Text cases pass the block gate 8/8 at N=20 on stage
# 3d3c6f5c2-0a0d1f39 (strict recompare; block-gate.json in each run dir). They are not rows of the consolidation table: TEXT_CASE_RUNS_27 below adds them to block 27.
# The Oracle narrowing of 15 October is lifted on those verdicts (Oracle 17 October: PASS-WITH-CAVEATS, issue #12).
REVIEWED["swiftui.layout-priority"] = {"review": "oracle 2026-10-17 (block 27 Text narrowing lift: PASS-WITH-CAVEATS)", "caveats": [
    "Text coverage is Tinos-only (`.custom(\"Tinos-Regular\")`); system fonts in priority groups are not covered.",
    "Three of the eight Text cases (text-labels, text-zero-proposal, line-limit-two) contain no layoutPriority.",
    "The block gate ignores blocks under 8 px (about 3.2 pt) (pair_blocks_report.py:50).",
    "The text-priority row-6 Windows capture shows a 1 px red hairline that the gate drops.",
    "A cut Text gets a 9 pt width tolerance and the x allowance accumulates (pair_blocks_report.py:93, :97, :100), so equal and priority splits of all-cut rows can pass.",
    "hub-rows is gated at the cut tolerance throughout; its row 2 blue block differs by about 7 px and passes.",
    "The eight Text verdicts ran on renderer 0.7 (`renderer-0.7-baseline`, sha 82513ae0…) and are not yet confirmed on renderer 0.8.",
    "text-line-limit-two (system-font) measures an 8.4 pt width difference on row 1, a cut Text, against the 9 pt cut tolerance: 0.6 pt of slack, and the tolerance was set from that same 8.4 pt measurement; the case has no layoutPriority.",
    "The eight Text cases fail the pixel gate in 20/20 runs each (report.json); the deciding gate is the block gate, which compares only overlay block geometry (colour order, x and width) and does not compare glyph rendering.",
    "No committed block-gate verdict on a pre-fix capture; detection of the L1/L3 inversion is shown by the pre-fix pixel captures (text-priority runs/20261015-154852), not by the gate's own output.",
    "The fix db29b0c5e is not cleared of the unattributed N=3 verdict changes in other blocks (factory/pipeline/layout-rules-regression/README.md)."]}
# Block 27 Text cases: the block gate passes at N=20 on stage 3d3c6f5c2-0a0d1f39; each entry is the run dir that holds its passing block-gate.json (pass true, 20 runs, pixel report fail 20).
TEXT_CASE_RUNS_27 = {
    "blocks-26-34/swiftui.layout-priority/text-priority-v1": "20261015-214710",
    "blocks-26-34/swiftui.layout-priority/text-labels-v1": "20261015-213922",
    "blocks-26-34/swiftui.layout-priority/text-three-groups-v1": "20261015-220452",
    "blocks-26-34/swiftui.layout-priority/text-spacer-v1": "20261015-221021",
    "blocks-26-34/swiftui.layout-priority/hub-rows-v1": "20261015-222758",
    "blocks-26-34/swiftui.text-views/text-zero-proposal-v1": "20261015-230257",
    "blocks-26-34/swiftui.text-views/text-fixed-size-v1": "20261015-231839",
    "blocks-26-34/swiftui.system-font/text-line-limit-two-v1": "20261015-232623",
}
TEXT_STAGE_27 = "3d3c6f5c2-0a0d1f39"
# Block 27 (hand-set): both stages named; the count string states the two gates separately.
STAGE_27 = ["3d58196a3-3dc0ffc8", TEXT_STAGE_27]
CASES_GATE_27 = "6/6 pixel-exact on 3d58196a3-3dc0ffc8 + 8/8 block gate at N=20 on 3d3c6f5c2-0a0d1f39"
# Block 37 slider (Oracle, 16 October 2026: PASS-WITH-CAVEATS). Delivered with caveats; the caveats below are the review's, not a re-run.
REVIEWED["swiftui.slider"] = {"review": "oracle 2026-10-16 (block 37: PASS-WITH-CAVEATS)", "caveats": [
    "Labels and value labels are checked semantically only (role, name, value, enabled, range, count, order); they have no position gate of their own.",
    "The value-label buttons' vertical position is not gated: Windows y 61.2 h 14.0 against the Mac's y 62.4 h 13.2, a 1.2 pt gap, so the boundsY check was dropped (decision H15).",
    "Dark cases gate at hazeTolerance 2 (values-dark, disabled-dark); the light cases at 1 (decision H4, which says within 1 level).",
    "Negative controls exist (negative-fill-colour-v1, negative-thumb-offset-v1): they fail at N=3 on the local dirty stage and mutate the Mac witness, so they are not CI paired evidence."],
    "windowsDifferences": ["Stepped-slider tick marks are not drawn on Windows (decision H4 records the Mac's tick marks under a stepped slider)."]}
# Round 6 review (16 October 2026, Oracle, PASS). Block 38 on-hover: delivered-with-caveats (H26). Block 41 compat: delivered-with-caveats after the
# transaction rework of 7796b0b81 (H27). The caveats below are the review's, not a re-run.
REVIEWED["swiftui.on-hover"] = {"review": "oracle 2026-10-16 (block 38: PASS, delivered-with-caveats)", "caveats": [
    "Topmost placement (HWND_TOPMOST with NOACTIVATE) is CI-only (`GITHUB_ACTIONS`), so the host's placement differs between CI and the Dell (H25).",
    "The HWND_BOTTOM cause of the failed runs is inferred: the z order was not logged before the topmost placement, so no covering window is named (H25).",
    "The N=20 pass (run 38916701641) ran on d9423e953, before 7796b0b81. Hover does not touch transactions, so the pass is not re-run on 7796b0b81.",
    "Leave is a genuine WM_MOUSELEAVE from TrackMouseEvent (view.rs:1308)."]}
# Blocks 39 and 40 (Oracle, 17 October 2026: PASS-WITH-CAVEATS; issues #9 and #10). delivered-with-caveats; the caveats are the review's, not a re-run.
REVIEWED["swiftui.uia-walk"] = {"review": "oracle 2026-10-17 (PASS-WITH-CAVEATS)", "status": "delivered-with-caveats", "caveats": [
    "The N=20 list gate in run 38872207896 sampled the label-ink background in the list gutter (fixed in 943f64db4); the gutter is white on both platforms in that run, so the result stands; the fixed sampler is proven at N=3 only (run 38916920414).",
    "H16 accepted: rows are gated by the list gate and the list-rect pixels. H21 accepted for legacy scrollers; the overlay-scroller gutter stays unknown."]}
REVIEWED["swiftui.ime-traps"] = {"review": "oracle 2026-10-17 (PASS-WITH-CAVEATS)", "status": "delivered-with-caveats", "caveats": [
    "imet-badregion-v1 exercises the invalid and inverted composing regions on Windows only (AppKit raises on them); the Mac reference is the unchanged field after compose and cancel, so the case proves Windows refuses the region without a crash or a value change, not parity of bad-region handling."]}
REVIEWED["swiftui.compat"] = {"review": "oracle 2026-10-16 (block 41, transaction rework 7796b0b81: PASS)", "caveats": [
    "Open edges A and B (Oracle findings 16 October: a completion could run while an outer withAnimation was still open, and an outer completion could fire early when a segment commit changed no layout) are coded against in the working tree (H29, issue #2: frameOpen, gated deferred completions, settlesOnly) with six unit tests and the new case `completion-timing-v1`, read-only reviewed PASS-WITH-CAVEATS twice. Evidence 17 October: runtime unit suite 452/452 on the internal disk; CI run 38984220953 at N=20 on 6c69c61fb: all seven block 41 cases exit 0, `completion-timing-v1` 80/80 pairs exact outside the button-label exclusion (maxdiff 0), so real SwiftUI and the runtime agree: the outer completion mark is red on both hosts, so the outer transaction animated nothing and the nested completion's write is plain (the mid frame is a settled frame, not a 350 ms sample). Oracle sign-off 17 October PASS-WITH-CAVEATS (three rounds); follow-ups in issue #29; known edge: a completion settling at a tick with no frame open while an unrelated transaction is queued still takes that transaction's animation.",
    "The test-comment gap at the former TransactionBoundaryScopeTests.swift:272 is corrected in the same working-tree change."]}
# Blocks 14, 15, 19 (16 October): the N=3 layout-rules regression on stage 3d3c6f5c2 with renderer 0.7 failed them. The CI N=20 confirmation (renderer 0.10,
# explicit scale 2.5, CI_CASE_RUN below) passes every case of each block, so the status on current code is no longer unknown.
REVIEWED["swiftui.focus-state"]["caveats"].append("CI N=20 pass on renderer 0.10 (stage 06a3a0a85-5dfe7cc2 for bool-form-v1 and tab-order-v1; c4e83a68a-5dfe7cc2 for programmatic-v1 and shift-tab-v1), replacing the 16 October N=3 regression on renderer 0.7 (stage 3d3c6f5c2).")
REVIEWED["swiftui.ime-marked-text"]["caveats"].append("CI N=20 pass on renderer 0.10 (stage 06a3a0a85-5dfe7cc2 for ime-cancel, ime-commit and ime-composing-v1; c4e83a68a-5dfe7cc2 for ime-recompose-v1), replacing the 16 October N=3 regression on renderer 0.7 (stage 3d3c6f5c2).")
REVIEWED["swiftui.ime-marked-text"]["caveats"].append("Extra CI evidence: `ime-composing-v1` passes N=20 in run 38870003524 (stage 168328082-0766196a, commit 168328082), after the harness lease fix (H22); it had been lost to the fixed 10 s host lease in run 38865487951 (H23).")
REVIEWED["swiftui.ime-marked-text"]["caveats"].append("Pixels are report-only on every block 15 case (`pair.json` `pixels: report-only`, H28, issue #3): the semantic, text-origin and IME gates decide; the marked-text look (yellow on the Mac, underline on Windows), the candidate window and the value-line glyphs are reported, not gated, with no named exclusion rectangles.")
REVIEWED["swiftui.opacity-transition"]["caveats"].append("CI N=20 pass on renderer 0.10 for all 7 cases (stage 06a3a0a85-5dfe7cc2), replacing the 16 October N=3 regression on renderer 0.7 (stage 3d3c6f5c2, opacity-text-v1). The clock job's own ok flag reads False in the CI result.json although all 20 runs report ok; the gate is clock-report.json (120 of 120 pairs, 0 fail).")

# CI N=20 confirmation (16 October 2026; docs/sr1-status.md, "CI N=20 confirmation"). Each case below passed its deciding gate at N=20 in the CI run
# named here, on renderer 0.10 with the explicit render scale 2.5 (ABI 0.10, decision H17). The stage and commit are those recorded in each run's build.json.
# The run directories are committed under the pipeline tree, but the mapping is hand-set here; each case was checked against its run directory's deciding gate
# (pixel, semantic, text-origin or clock report) when it was mapped.
CI_RUNS = {
    "38854967920": {"runDirs": "runs/20261016-051729", "stage": "06a3a0a85-5dfe7cc2", "commit": "06a3a0a85fc737df1ea7e24cc137636e6889bf2d"},
    "38860483220": {"runDirs": "runs/20261016-061908", "stage": "c4e83a68a-5dfe7cc2", "commit": "c4e83a68a06f2672766f3c83426b980d78d4c659"},
    "38872207896": {"runDirs": "runs/20261016-081325", "stage": "f81244b4f-9ce7a09e", "commit": "f81244b4f3b0995188439bd6dae4e15f34a13a04"},
    "38916701641": {"runDirs": "runs/20261016-143349", "stage": "d9423e953-7ede36bc", "commit": "d9423e953ecae07e250e86fb765a0a252357705a"},
    "38987638974": {"runDirs": "runs/20261017-004328", "stage": "93c6fe320-82e12842", "commit": "93c6fe320a443bf86224ac34c3455105a4c399ac"},
    "38994003228": {"runDirs": "runs/20261017-021255", "stage": "d4267ce69-f2322127", "commit": "d4267ce696967d31b1f10d8d16532a327f68a8a7", "renderer": "renderer-0.10-c13b62a4"},
    "38994825461": {"runDirs": "runs/20261017-022522", "stage": "1d309081d-f2322127", "commit": "1d309081dfef42a5212aef18c9c389031baa6bb6", "renderer": "renderer-0.10-c13b62a4"},
    "38995241565": {"runDirs": "runs/20261017-023141", "stage": "49680e32d-f2322127", "commit": "49680e32dc10d2eac59bdf948e2cc1b907ec1fce", "renderer": "renderer-0.10-c13b62a4"},
}

_CI_RUN_1 = [  # 27 cases that pass on the current gate, run 38854967920 (controls-b-v1 is in _CI_RUN_3: it failed its list gate there, H20)
    "blocks-37-38/swiftui.slider/disabled-dark-v1", "blocks-37-38/swiftui.slider/disabled-input-v1", "blocks-37-38/swiftui.slider/labels-v1",
    "blocks-37-38/swiftui.slider/over-colour-v1", "blocks-37-38/swiftui.slider/values-dark-v1", "blocks-37-38/swiftui.slider/values-light-v1",
    "blocks-37-38/swiftui.slider/widths-v1", "blocks-37-38/swiftui.uia-walk/controls-a-v1",
    "blocks-6-10/swiftui.focus-state/bool-form-v1", "blocks-6-10/swiftui.focus-state/tab-order-v1",
    "blocks-6-10/swiftui.ime-marked-text/ime-cancel-v1", "blocks-6-10/swiftui.ime-marked-text/ime-commit-v1", "blocks-6-10/swiftui.ime-marked-text/ime-composing-v1",
    "blocks-6-10/swiftui.opacity-transition/insertion-fade-v1", "blocks-6-10/swiftui.opacity-transition/move-leading-v1",
    "blocks-6-10/swiftui.opacity-transition/opacity-animated-v1", "blocks-6-10/swiftui.opacity-transition/opacity-static-v1",
    "blocks-6-10/swiftui.opacity-transition/opacity-text-v1", "blocks-6-10/swiftui.opacity-transition/removal-fade-v1",
    "blocks-6-10/swiftui.opacity-transition/removal-move-v1", "blocks-6-10/swiftui.ime-traps/imet-focuschange-v1", "blocks-6-10/swiftui.ime-traps/imet-hangul-v1",
    "blocks-6-10/swiftui.ime-traps/imet-reconvert-v1", "blocks-37-38/swiftui.compat/environment-key-v1", "blocks-37-38/swiftui.compat/id-modifier-order-v1",
    "blocks-37-38/swiftui.compat/state-nested-update-v1", "blocks-37-38/swiftui.compat/task-id-v1",
]
_CI_RUN_2 = [  # 11 cases, run 38860483220: the 9 cases that hit the capture artifact in run 38854967920, plus shift-tab-v1 (job crash) and imet-badregion-v1 (GetClientRect failure) there
    "blocks-37-38/swiftui.slider/click-track-v1", "blocks-37-38/swiftui.slider/disabled-light-v1", "blocks-37-38/swiftui.slider/drag-v1",
    "blocks-37-38/swiftui.slider/keys-v1", "blocks-37-38/swiftui.slider/range-v1", "blocks-37-38/swiftui.slider/value-labels-v1",
    "blocks-6-10/swiftui.focus-state/programmatic-v1", "blocks-6-10/swiftui.focus-state/shift-tab-v1", "blocks-6-10/swiftui.ime-marked-text/ime-recompose-v1",
    "blocks-6-10/swiftui.ime-traps/imet-badregion-v1", "blocks-37-38/swiftui.compat/any-view-v1",
]
_CI_RUN_3 = [  # 1 case, run 38872207896 (commit f81244b4f, H20 list gate with the H21 overflow-only gutter): controls-b passes its semantic, list and list-rect gates at N=20
    "blocks-37-38/swiftui.uia-walk/controls-b-v1",
]
_CI_RUN_4 = [  # 2 cases, run 38916701641 (commit d9423e953, H25, CI-only topmost placement): block 38 on-hover at N=20; both failed locally on 3d3c6f5c2
    "blocks-37-38/swiftui.on-hover/adjacent-v1", "blocks-37-38/swiftui.on-hover/rows-v1",
]
_CI_RUN_5 = [  # 16 cases, run 38987638974 (commit 93c6fe320, H34 re-delivery, 17 October): block 7 toggle (6), block 13 textfield (7), block 20 text-dark-v1 (1 of 12), block 34 textfield-axis (2)
    "blocks-6-10/swiftui.toggle/checkbox-labelled-on-v1", "blocks-6-10/swiftui.toggle/checkbox-off-v1", "blocks-6-10/swiftui.toggle/checkbox-on-v1",
    "blocks-6-10/swiftui.toggle/switch-labelled-on-v1", "blocks-6-10/swiftui.toggle/switch-off-v1", "blocks-6-10/swiftui.toggle/switch-on-v1",
    "blocks-6-10/swiftui.textfield/automatic-style-v1", "blocks-6-10/swiftui.textfield/caret-empty-v1", "blocks-6-10/swiftui.textfield/filled-truncated-v1",
    "blocks-6-10/swiftui.textfield/placeholder-v1", "blocks-6-10/swiftui.textfield/plain-v1", "blocks-6-10/swiftui.textfield/prompt-v1", "blocks-6-10/swiftui.textfield/submit-v1",
    "blocks-17-20/swiftui.color-scheme/text-dark-v1",
    "blocks-26-34/swiftui.textfield-axis/plain-v1", "blocks-26-34/swiftui.textfield-axis/rounded-v1",
]
_CI_RUN_6 = [  # 7 block 28 cases, run 38994003228 (re-delivery, 17 October, issue #7; stage d4267ce69)
    "blocks-26-34/swiftui.system-font/fractional-v1", "blocks-26-34/swiftui.system-font/sizes-large-v1", "blocks-26-34/swiftui.system-font/style-weight-v1",
    "blocks-26-34/swiftui.system-font/styles-large-v1", "blocks-26-34/swiftui.system-font/styles-small-v1", "blocks-26-34/swiftui.system-font/truncate-v1",
    "blocks-26-34/swiftui.system-font/weights-v1",
]
_CI_RUN_7 = ["blocks-26-34/swiftui.system-font/line-limit-v1"]  # run 38994825461 (stage 1d309081d)
_CI_RUN_8 = ["blocks-26-34/swiftui.system-font/sizes-v1"]       # run 38995241565 (stage 49680e32d)
CI_CASE_RUN = {**{c: "38854967920" for c in _CI_RUN_1}, **{c: "38860483220" for c in _CI_RUN_2}, **{c: "38872207896" for c in _CI_RUN_3},
               **{c: "38916701641" for c in _CI_RUN_4}, **{c: "38987638974" for c in _CI_RUN_5},
               **{c: "38994003228" for c in _CI_RUN_6}, **{c: "38994825461" for c in _CI_RUN_7}, **{c: "38995241565" for c in _CI_RUN_8}}
CI_CAVEAT = ("CI confirmation (16 October): the CI runners use the Windows WARP adapter at an explicit render scale of 2.5 (H17), not native 240 dpi. "
             "The Dell 240-dpi sandbox stays the reference; the CI and Dell captures were pixel-identical on click-track and labels.")
PENDING_REVIEW -= set(REVIEWED)

# No hand-set status: every block is derived from its cases and REVIEWED (block 28 re-delivered 17 October, H37). Blocks 7, 13, 20 and 34 were reopened on the F2
# rebaseline (G70, 16 October) and re-delivered under H34 on CI run 38987638974 (17 October; the G70 reasons are in docs/sr1-status.md).
OVERRIDES = {}
WIN_KEYS = re.compile(r"Windows|Segoe|Sandbox|hardware|narrower|focus ring|TSF|\bIME\b|UIA|Mac side|Mac's|\bSF\b|scale 2\.5|light only|measured in light", re.I)
NOT_SWIFTUI = set("""Int Int8 Int16 Int32 Int64 UInt Double Float CGFloat CGSize CGPoint CGRect String Bool Array Dictionary Set
Optional Character Void Any AnyObject Self Date Data URL UUID Never Result Error Task DispatchQueue Foundation TimeInterval
View Swift SwiftUI NSColor NSApplication NSView NSWindow NSImage NSHostingView NSScreen NSAppearance NSEvent
NSApp ProcessInfo Thread RunLoop Bundle""".split())


def decode_usr(usr):
    s = usr.split(":", 2)[-1]
    s = s[2:] if s.startswith("s:") else s
    out, i, n = [], 0, len(s)
    while i < n:
        j = i
        while j < n and s[j].isdigit():
            j += 1
        if j > i and j < n and (s[j].isalpha() or s[j] == "_") and j + int(s[i:j]) <= n:
            ln = int(s[i:j]); out.append(s[j:j + ln]); i = j + ln
        else:
            i += 1
    return [x for x in out if x not in ("SwiftUI", "SwiftUICore")]


def manifest_apis(block):
    names = set()
    for u in block["symbols"]:
        t = decode_usr(u)
        if t:
            names.add(t[0] if len(t) == 1 else f"{t[0]}.{t[1]}")
    return sorted(names)


def strip_code(src):
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    src = re.sub(r"//[^\n]*", " ", src)
    return re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)


def witness_apis(path):
    src = strip_code(path.read_text(errors="replace"))
    declared = set(re.findall(r"\b(?:struct|class|enum|protocol|func|var|let|case|typealias)\s+([A-Za-z_]\w*)", src))
    types = set(re.findall(r"\b([A-Z]\w*)\s*[({.<]", src))
    mods = set(re.findall(r"\.([a-z]\w*)\s*[({]", src)) | set(re.findall(r"\.([a-z]\w*)\s*$", src, flags=re.M))
    types = {t for t in types if t not in declared and t not in NOT_SWIFTUI and not t.startswith(("Witness", "Mac"))}
    mods = {m for m in mods if m not in declared}
    return types, mods


def witness_files(case):
    d = ROOT / "factory/pipeline" / case
    return sorted(p for p in d.rglob("Witness.swift") if "/runs/" not in str(p)) if d.is_dir() else []


def parse_status():
    text = STATUS.read_text()
    head = re.search(r"^# SR1 status: (\d+) (\w+) (\d{4})", text, re.M)
    months = {m: i for i, m in enumerate("January February March April May June July August September October November December".split(), 1)}
    date = f"{head.group(3)}-{months[head.group(2)]:02d}-{int(head.group(1)):02d}"
    rows = {}
    for line in text.split("\n---\n")[0].splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        m = re.match(r"(\d+|pixel-ties)\b", cells[0])
        if m and len(cells) >= 4:
            key = int(m.group(1)) if m.group(1).isdigit() else "pixel-ties"
            rows[key] = {"verdict": cells[3], "caveats": cells[4] if len(cells) > 4 else ""}
    gaps = re.search(r"^Known gaps: (.*)$", text, re.M)
    return date, rows, gaps.group(1).strip() if gaps else ""


def split_caveats(cell):
    parts = [p.strip().rstrip(".") for p in re.split(r";|\. (?=[A-Z])", cell) if p.strip()]
    gen, win = [], []
    for p in parts:
        (win if WIN_KEYS.search(p) else gen).append(p)
    return gen, win


STATUS_VALUES = ["delivered", "delivered-with-caveats", "delivered-pending-review", "not-delivered", "in-progress"]
HAND_REQUIRED = ("block", "statusDocBlock", "status", "cases", "verdict", "caveats")


def status_doc_rows(text):
    """The first cell of each docs/sr1-status.md table row ("I2", "7", "pixel-ties") -> the whole row, before the verdict/status separator."""
    rows = {}
    for line in text.split("\n---\n")[0].splitlines():
        if line.startswith("|"):
            m = re.match(r"([A-Za-z0-9][\w.-]*)\s", line.strip().strip("|").split("|")[0].strip() + " ")
            if m:
                rows.setdefault(m.group(1), line)
    return rows


def status_doc_ids(text):
    return set(status_doc_rows(text))


def row_status(line):
    """The bold status word of a docs/sr1-status.md row: the first bold token that is a status value, or None."""
    for tok in re.findall(r"\*\*([a-z-]+)\*\*", line):
        if tok in STATUS_VALUES:
            return tok
    return None


def validate_hand_entries(entries, generated_ids, status_text, root=ROOT):
    """Hand entries are verbatim, so each one is checked: required keys, an allowed status, cases and evidence paths that exist,
    a row in docs/sr1-status.md, and no block id that the generator already emits. Returns a list of violations (empty = valid)."""
    errors, seen, rows = [], set(), status_doc_rows(status_text)
    for i, e in enumerate(entries):
        name = e.get("block", f"entry {i}")
        for k in HAND_REQUIRED:
            if k not in e:
                errors.append(f"{name}: missing {k}")
        bid = e.get("block")
        if bid in generated_ids:
            errors.append(f"{name}: duplicates a generated block id")
        if bid in seen:
            errors.append(f"{name}: duplicate hand entry")
        seen.add(bid)
        if e.get("status") not in STATUS_VALUES:
            errors.append(f"{name}: status {e.get('status')!r} is not one of {STATUS_VALUES}")
        row = rows.get(e.get("statusDocBlock"))
        if row is None:
            errors.append(f"{name}: no row {e.get('statusDocBlock')!r} in docs/sr1-status.md")
        elif e.get("status") != row_status(row):
            errors.append(f"{name}: status {e.get('status')!r} differs from the bold status {row_status(row)!r} in its docs/sr1-status.md row")
        if "cases" in e and not e["cases"]:
            errors.append(f"{name}: cases is empty")
        if "caveats" in e and not isinstance(e["caveats"], list):
            errors.append(f"{name}: caveats is not a list")
        source = (e.get("verdict") or {}).get("source", "")
        if "verdict" in e and not re.search(r"(?:docs|factory)/\S+", source):
            errors.append(f"{name}: verdict.source names no path")
        for c in e.get("cases", []):
            if not (root / "factory/pipeline" / c).exists():
                errors.append(f"{name}: case path does not exist: {c}")
        for tok in re.findall(r"(?:docs|factory)/\S+", source):
            tok = tok.rstrip(".,;)")
            if not (root / tok).exists():
                errors.append(f"{name}: evidence path does not exist: {tok}")
    return errors


def case_passes(row):
    """A case passes on its local table row (exit 0) or on its CI N=20 run (CI_CASE_RUN)."""
    return row["exit"] == 0 or row["case"] in CI_CASE_RUN


def _renderers(ci_runs):
    """One renderer label per entry; runs before 17 October carry the default (renderer-0.10-a15ebc5d)."""
    labels = sorted({CI_RUNS[r].get("renderer", "renderer-0.10-a15ebc5d") for r in ci_runs})
    return labels[0] if len(labels) == 1 else labels


def build():
    def top(r):
        n = r["block"].split()[0]
        return int(n) if n.isdigit() else n
    table = [r for r in json.loads(CLOSURE_TABLE.read_text())["rows"] if not (isinstance(top(r), int) and top(r) > 20)] + \
            [r for r in json.loads(TABLE.read_text()) if isinstance(top(r), int) and top(r) > 20]
    table += [{"block": "27 layout-priority", "case": c, "exit": 0, "stage": TEXT_STAGE_27, "out": str(ROOT / "factory/pipeline" / c / "runs" / run)}
              for c, run in TEXT_CASE_RUNS_27.items()]     # block 27 Text cases (block gate, H33)
    manifest = json.loads(MANIFEST.read_text())
    mblocks = {b["id"]: b for b in manifest["blocks"]}
    sdate, rows, gaps = parse_status()
    stages = {}
    cstage = json.loads(CLOSURE_TABLE.read_text())["stage"]
    for line in RESULTS.read_text().splitlines():            # every stage a case PASSED on (exit 0), blocks 11-16, 21 and up
        r = json.loads(line)
        if r.get("done") and r["exit"] == 0:
            stages.setdefault(r["case"], set()).add(r["stage"])
    for line in CLOSURE_RESULTS.read_text().splitlines():    # blocks 1-20: the closure stage, where the case passed
        r = json.loads(line)
        if r.get("done") and r["exit"] == 0 and r["stage"] == cstage:
            stages.setdefault(r["case"], set()).add(cstage)
    failing_local = {r["case"] for r in table if r["exit"] != 0}
    for case, run in CI_CASE_RUN.items():                   # a case's stages are where it passed: the CI stage, plus local stages only if the local row passed
        if case in failing_local:
            stages[case] = set()
        stages.setdefault(case, set()).add(CI_RUNS[run]["stage"])
    bycase = {}
    for r in table:
        num = r["block"].split()[0]
        bycase.setdefault(int(num) if num.isdigit() else num, []).append(r)
    entries = []
    for num in sorted(bycase, key=lambda k: (isinstance(k, str), k if isinstance(k, int) else 0)):
        cases = bycase[num]
        bid = NUM2ID.get(num, "cross-cutting.pixel-ties")
        row = rows.get(num, {"verdict": "", "caveats": ""})
        gen, win = split_caveats(row["caveats"])
        ci_runs = sorted({CI_CASE_RUN[c["case"]] for c in cases if c["case"] in CI_CASE_RUN})
        if ci_runs:
            gen = gen + [CI_CAVEAT]
        types, mods = set(), set()
        for c in cases:
            for p in witness_files(c["case"]):
                t, m = witness_apis(p); types |= t; mods |= m
        stg = sorted({s for c in cases for s in stages.get(c["case"], set())})
        rundates = sorted({f"{d[:4]}-{d[4:6]}-{d[6:]}" for d in
                           (re.search(r"/runs/(\d{8})-", c["out"]).group(1) for c in cases if c.get("out"))})
        passed = sum(1 for c in cases if case_passes(c))
        status = "not-delivered" if passed != len(cases) else ("delivered-with-caveats" if gen or win else "delivered")
        review = None
        if bid in REVIEWED and passed == len(cases):
            rv = REVIEWED[bid]
            review = rv["review"]
            gen = gen + ROUND4_CAVEATS.get(bid, []) + rv["caveats"]
            win = win + rv.get("windowsDifferences", [])
            status = rv.get("status") or ("delivered-with-caveats" if gen or win else "delivered")
        elif bid in PENDING_REVIEW and passed == len(cases):
            status = "delivered-pending-review"
            gen = gen + ROUND4_CAVEATS.get(bid, [])
        gen = gen + LIST_NOTES.get(bid, [])
        e = {"block": bid, "statusDocBlock": num, "status": status,
             "cases": sorted(c["case"] for c in cases), "casesPassingDecidingGate": f"{passed}/{len(cases)}",
             "apis": {"fromManifest": manifest_apis(mblocks[bid]) if bid in mblocks else [],
                      "fromCaseSources": {"types": sorted(types), "modifiersAndMembers": sorted(mods)}},
             "verdict": {"text": row["verdict"],
                         "source": "docs/sr1-status.md table + factory/pipeline/closure/closure-table.json (blocks 1-20) / consolidation-table.json (blocks 21+)",
                         "date": sdate, "runDates": rundates},
             "stage": stg[0] if len(stg) == 1 else stg,
             "caveats": gen, "windowsDifferences": win}
        if review:
            e["review"] = review
        if ci_runs:
            e["ciN20"] = {"runs": ci_runs, "stages": sorted({CI_RUNS[r]["stage"] for r in ci_runs}),
                          "casesPassing": f"{sum(1 for c in cases if c['case'] in CI_CASE_RUN)}/{len(cases)}",
                          "renderer": _renderers(ci_runs), "renderScale": 2.5, "windowsAdapter": "WARP (CI runner)",
                          "runDirs": {r: CI_RUNS[r]["runDirs"] for r in ci_runs}}
        if bid == "swiftui.layout-priority":                 # hand-set: two stages and two gates (H33)
            e["stage"], e["casesPassingDecidingGate"] = STAGE_27, CASES_GATE_27
        if bid == "swiftui.system-font":                     # hand-set: the three N=20 stages share one staged tree (H37); older passing rows are history
            e["stage"] = "staged tree f2322127 (stages d4267ce69-f2322127, 1d309081d-f2322127, 49680e32d-f2322127; renderer-0.10-c13b62a4)"
        ov = OVERRIDES.get(bid)
        if ov:
            e["statusFromSources"] = e["status"]
            e.update(ov)
            e["caveats"] = [ov["statusReason"]] + e["caveats"]
        entries.append(e)
    hand = hand_entries()
    return {"generator": "factory/tools/proven-controls/generate.py", "schema": 1,
            "sources": ["factory/pipeline/closure/closure-table.json", "factory/pipeline/consolidation/consolidation-table.json", "factory/registry/manifest.json",
                        "docs/sr1-status.md", "factory/pipeline/consolidation/results.jsonl", "factory/pipeline/closure/results.jsonl", "Witness.swift of each case"],
            "statusDate": sdate,
            "statusValues": STATUS_VALUES,
            "apisNotCovered": {"hint": "Any SwiftUI API not listed under a block is not proven. See docs/pulse-notch-demand-map.md "
                                       "for the notch's SwiftUI APIs that no delivered block covers.",
                               "see": "docs/pulse-notch-demand-map.md"},
            "knownGapsAll": gaps,
            "blocks": entries + hand, "_hand": hand, "_generated": [e["block"] for e in entries]}


def build_checked():
    """The document and its violations: hand entries are validated against the generated block ids and docs/sr1-status.md."""
    doc = build()
    hand, generated = doc.pop("_hand"), set(doc.pop("_generated"))
    return doc, validate_hand_entries(hand, generated, STATUS.read_text())


def hand_entries():
    """Entries with no source in this generator (wave 1 I2, `foundations.image-layout`: its status row is not a numbered row); kept verbatim in hand-entries.json."""
    return json.loads((Path(__file__).resolve().parent / "hand-entries.json").read_text())


def main(argv):
    doc, errors = build_checked()
    if errors:
        print("hand-entries.json violates the registry rules:", file=sys.stderr)
        for e in errors:
            print(f"  {e}", file=sys.stderr)
        return 1
    new = json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    if "--check" in argv:
        old = OUT.read_text() if OUT.exists() else ""
        if old != new:
            print("docs/proven-controls.json drifted from its sources; run generate.py", file=sys.stderr)
            return 1
        print("docs/proven-controls.json is current")
        return 0
    OUT.write_text(new)
    print(f"wrote {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
