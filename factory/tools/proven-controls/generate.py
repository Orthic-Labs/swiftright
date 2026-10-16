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
    "swiftui.system-font": ["Segoe UI at the requested size: Windows lines are 1-3 pt taller from 15 pt up and glyphs a little larger; the text position gate carries measured tolerances (decision F1).",
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
    "swiftui.uia-walk": ["Pixels are report-only; the semantic tree is gated for every control kind listed in the case."],
    "swiftui.ime-traps": ["Hardware IME is deferred: the cases drive the in-process TextStore script and the NSTextInputClient path, not a real IME (H9(b))."],
    "swiftui.compat": ["Ported from OpenSwiftUI's MIT tests as view bodies and expectations only (H9a); EquatableView and animation completion are not ported and not delivered."],
}
ROUND4_CAVEATS.update(ROUND5_CAVEATS)
ROUND4_CAVEATS.update(ROUND6_CAVEATS)
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
REVIEWED["swiftui.system-font"]["caveats"] = ["The blanket tolerance set was replaced by per-row tolerances (decision G71); on the final renderer (fc4a39a89, renderer 0.8) the independent gate fails for 8 of 9 cases."]
# Text in priority groups: the eight text cases pass at N=20 on stage 3d3c6f5c2-0a0d1f39 (L1-L8); the Oracle narrowing is lifted, the review is not repeated.
# Block 27 (16 October): the eight Text cases pass the block gate 8/8 at N=20 on stage 3d3c6f5c2-0a0d1f39 (strict recompare; block-gate.json in each run dir).
# The Oracle narrowing of 15 October is lifted on those verdicts; the block is not independently re-reviewed.
REVIEWED["swiftui.layout-priority"] = {"review": "oracle 2026-10-15 (narrowed); narrowing lifted 2026-10-16 on the block-gate verdicts, not re-reviewed", "caveats": [
    "Text coverage is Tinos-only (`.custom(\"Tinos-Regular\")`); system fonts in priority groups are not covered.",
    "Three of the eight Text cases (text-labels, text-zero-proposal, line-limit-two) contain no layoutPriority.",
    "The block gate ignores blocks under 8 px (about 3.2 pt) (pair_blocks_report.py:50).",
    "The text-priority row-6 Windows capture shows a 1 px red hairline that the gate drops.",
    "A cut Text gets a 9 pt width tolerance and the x allowance accumulates (pair_blocks_report.py:93, :97, :100), so equal and priority splits of all-cut rows can pass.",
    "hub-rows is gated at the cut tolerance throughout; its row 2 blue block differs by about 7 px and passes.",
    "The eight Text verdicts ran on renderer 0.7 (`renderer-0.7-baseline`, sha 82513ae0…) and are not yet confirmed on renderer 0.8.",
    "text-line-limit-two (system-font) measures an 8.4 pt width difference on row 1, a cut Text, against the 9 pt cut tolerance: 0.6 pt of slack, and the tolerance was set from that same 8.4 pt measurement; the case has no layoutPriority."]}
# Block 37 slider (Oracle, 16 October 2026: PASS-WITH-CAVEATS). Delivered with caveats; the caveats below are the review's, not a re-run.
REVIEWED["swiftui.slider"] = {"review": "oracle 2026-10-16 (block 37: PASS-WITH-CAVEATS)", "caveats": [
    "Labels and value labels are checked semantically only (role, name, value, enabled, range, count, order); they have no position gate of their own.",
    "The value-label buttons' vertical position is not gated: Windows y 61.2 h 14.0 against the Mac's y 62.4 h 13.2, a 1.2 pt gap, so the boundsY check was dropped (decision H15).",
    "Dark cases gate at hazeTolerance 2 (values-dark, disabled-dark); the light cases at 1 (decision H4, which says within 1 level).",
    "No negative controls yet: the gate has not been shown to fail on a 1 px thumb offset or a wrong fill colour."],
    "windowsDifferences": ["Stepped-slider tick marks are not drawn on Windows (decision H4 records the Mac's tick marks under a stepped slider)."]}
# Blocks 14, 15, 19 (16 October): the N=3 layout-rules regression on stage 3d3c6f5c2 with renderer 0.7 fails them; they pass on fc4a39a89 with renderer 0.8,
# which predates the layout commits, so their status on current code with renderer 0.8 is unknown (docs/sr1-decisions.md, verification 16 October).
REVIEWED["swiftui.focus-state"]["caveats"].append("On stage 3d3c6f5c2 with renderer 0.7 the N=3 layout-rules regression fails 4 of 4 cases; they pass on fc4a39a89 with renderer 0.8, so the status on current code with renderer 0.8 is unknown.")
REVIEWED["swiftui.ime-marked-text"]["caveats"].append("On stage 3d3c6f5c2 with renderer 0.7 the N=3 layout-rules regression fails 4 of 4 cases; they pass on fc4a39a89 with renderer 0.8, so the status on current code with renderer 0.8 is unknown.")
REVIEWED["swiftui.opacity-transition"]["caveats"].append("On stage 3d3c6f5c2 with renderer 0.7 the N=3 layout-rules regression fails opacity-text-v1; the block passes on fc4a39a89 with renderer 0.8, so the status on current code with renderer 0.8 is unknown.")
PENDING_REVIEW -= set(REVIEWED)

# No hand-set status: the closure run reran blocks 13-15 (text-origin fix, decision 12) and every block 1-20 is derived from its cases (delivered-pending-review).
# Reopened 16 October on the F2 rebaseline (3cb231a98, factory/pipeline/blocks-w1-f2/rebaseline-final-verdicts.json, stage fc4a39a89, decision G70): these blocks
# had passed on final-stage captures that have since been deleted, and fresh N=3 captures fail them by 1 px (textorigin first ink or control label x at tolerance 0).
NOT_DELIVERED_1PX = ("Reopened 16 October (F2 rebaseline, decision G70): fresh N=3 captures on stage fc4a39a89 fail by 1 px at tolerance 0 "
                     "(textorigin first-ink or control-label x); the earlier passing captures on stage 6459bb8cd still exist (e.g. `blocks-6-10/swiftui.textfield/plain-v1/runs/20261015-050354`), and the deleted final-stage captures failed with the same 1 px deltas. Failing cases: ")
OVERRIDES = {
    "swiftui.system-font": {"status": "not-delivered", "statusReason": "Reopened 16 October (decision G71): the blanket tolerance was replaced by per-row tolerances, which fail the independent block 28 gate on the final renderer (styles-large passes; 8 of 9 cases fail; unfitted sizes and weights, undersampled rows)."},
    "swiftui.textfield": {"status": "not-delivered", "statusReason": NOT_DELIVERED_1PX + "textfield automatic-style-v1, caret-empty-v1, filled-truncated-v1, placeholder-v1, plain-v1, prompt-v1."},
    "swiftui.toggle": {"status": "not-delivered", "statusReason": NOT_DELIVERED_1PX + "toggle switch-labelled-on-v1, checkbox-labelled-on-v1."},
    "swiftui.color-scheme": {"status": "not-delivered", "statusReason": NOT_DELIVERED_1PX + "color-scheme text-dark-v1."},
    "swiftui.textfield-axis": {"status": "not-delivered", "statusReason": NOT_DELIVERED_1PX + "textfield-axis plain-v1."},
}
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


def build():
    def top(r):
        n = r["block"].split()[0]
        return int(n) if n.isdigit() else n
    table = [r for r in json.loads(CLOSURE_TABLE.read_text())["rows"] if not (isinstance(top(r), int) and top(r) > 20)] + \
            [r for r in json.loads(TABLE.read_text()) if isinstance(top(r), int) and top(r) > 20]
    manifest = json.loads(MANIFEST.read_text())
    mblocks = {b["id"]: b for b in manifest["blocks"]}
    sdate, rows, gaps = parse_status()
    stages = {}
    cstage = json.loads(CLOSURE_TABLE.read_text())["stage"]
    cases_closure = {r["case"] for r in table if not (isinstance(top(r), int) and top(r) > 20)}
    for line in RESULTS.read_text().splitlines():            # rounds 4 and 5: every stage the case was recorded on
        r = json.loads(line)
        if r.get("done") and r["case"] not in cases_closure:
            stages.setdefault(r["case"], set()).add(r["stage"])
    for line in CLOSURE_RESULTS.read_text().splitlines():    # blocks 1-20: the single closure stage
        r = json.loads(line)
        if r.get("done") and r["stage"] == cstage:
            stages.setdefault(r["case"], set()).add(cstage)
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
        types, mods = set(), set()
        for c in cases:
            for p in witness_files(c["case"]):
                t, m = witness_apis(p); types |= t; mods |= m
        stg = sorted({s for c in cases for s in stages.get(c["case"], set())})
        rundates = sorted({f"{d[:4]}-{d[4:6]}-{d[6:]}" for d in
                           (re.search(r"/runs/(\d{8})-", c["out"]).group(1) for c in cases if c.get("out"))})
        passed = sum(1 for c in cases if c["exit"] == 0)
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
