#!/usr/bin/env python3
"""Creates (or re-stamps) the text-in-a-stack cases of the layout rules lane (SR1 round 5 follow-up, requested by the Pulse hub track: a Text offered zero width, the priority
groups and the equal shares; decisions L1-L8 in docs/sr1-decisions.md, measurements probes/layout-rules/). Same shape as make_cases.py (new-case.py stamps package/ + mac-source/).
usage: make_cases_textstack.py [case-substring ...]

Every Text is Tinos Regular 13 (the bundled font both sides draw with identical advances: decision E14c) under an opaque `.overlay { Color }`: the glyphs are hidden and the pixels
are the frame each Text was given, which is what a stack decides. Rows are 23 pt tall (the 15 pt line plus 4 pt either side: whole points) and every row's frame is exact, so the
pixel gate is exact. Natural widths (Mac, Tinos 13): "Unused 90+ days" 91, "Demo Install" 68, "Hi" 13, the 44-character sentence 226 (probes/layout-rules, `tinos`)."""
import json, subprocess, sys, tempfile
from pathlib import Path
H = Path(__file__).resolve().parent
FONT_FILE = str((H.parent.parent / "resources/fonts/Tinos-Regular.ttf").resolve())
HEADER = "#if os(Windows)\nimport SwiftRightRuntime\nimport Foundation\n#else\nimport SwiftUI\n#endif\n\n"
CASES = {}
A, B, S, L = "Unused 90+ days", "Demo Install", "Hi", "Settings and preferences for the application"
COL = ["Color.red", "Color.blue", "Color.green", "Color.orange", "Color.purple"]
FONT = '.font(.custom("Tinos-Regular", size: 13))'


NAT = {A: 90.4, B: 67.6, S: 13.2, L: 226.0}   # Mac natural widths of the Tinos 13 texts, pt (probes/layout-rules `tinos`, snapped to the 2.5 grid)


def item(text, p=0, ll=1, fixed=False, h=False):
    return dict(text=text, p=p, ll=ll, fixed=fixed)


def sp(minlen=None, p=0):
    return dict(spacer=True, minlen=minlen, p=p)


def swift_item(it, color):
    if isinstance(it, str):
        return "Color.gray.frame(width: 30, height: 15)"   # a fixed marker
    if it.get("spacer"):
        s = "Spacer()" if it["minlen"] is None else f"Spacer(minLength: {it['minlen']})"
        return s + (f".layoutPriority({it['p']})" if it["p"] else "")
    s = f'Text("{it["text"]}"){FONT}' + (f".lineLimit({it['ll']})" if it["ll"] else "")
    if it["fixed"]: s += ".fixedSize()"
    s += f".overlay {{ {color} }}"
    if it["p"]: s += f".layoutPriority({it['p']})"
    return s


ROWNAT = []   # per row defined by row()/hub_row(): the natural width of each block in order (None: a marker or a block with no natural width; -1: wrapped text, any width)


def row(width, items, spacing=8, height=23):
    ROWNAT.append([None if (isinstance(it, str)) else (NAT[it["text"]] if it["ll"] else -1) for it in items if not (not isinstance(it, str) and it.get("spacer"))])
    colors = iter(COL * 3)
    body = "; ".join(swift_item(it, next(colors) if not (isinstance(it, str) or it.get("spacer")) else "") for it in items)
    return f"            HStack(spacing: {spacing}) {{ {body} }}.frame(width: {width}, height: {height}, alignment: .leading)"


CUT_REASON = ("a block that is narrower than its text's natural width is a cut Text: the Windows host cuts at the longest prefix + ellipsis that fits the offer, the Mac at its own break, "
              "so the width differs by up to one character (measured up to 8.4 pt for lineLimit 2 and 5.6 pt for one line; decision L1); every other block is within a device pixel")


def define(name, rows, spacing=0, typename=None, block="swiftui.layout-priority", extra_pair=None):
    typename = typename or "Witness_ts_" + name.replace("-", "_").replace("_v1", "")
    body = "\n".join(rows)
    naturals = list(ROWNAT[-len(rows):]); del ROWNAT[-len(rows):]
    extra_pair = {"blockGate": {"tolerancePx": 1.5, "cutTolerancePt": 9, "cutReason": CUT_REASON, "naturals": naturals}}
    CASES[f"{block}/{name}"] = dict(type=typename, pair=extra_pair, body=f"""struct {typename}: View {{
    var body: some View {{
        VStack(alignment: .leading, spacing: {spacing}) {{
{body}
        }}.frame(width: 240, height: 200, alignment: .topLeading)
    }}
}}""")


# --- block 27: swiftui.layout-priority -----------------------------------------------------------------------------------------------------------------------------------
# long and short labels at constrained widths: the least flexible child is offered an equal share first, the most flexible takes what is left (L4); nothing is cut while the row has room
define("text-labels-v1", [
    row(130, [item(A), item(B)]), row(160, [item(A), item(B)]), row(180, [item(A), item(B)]),
    row(100, [item(A), item(S)]), row(70, [item(S), item(A)]), row(150, [item(L), item(S)]), row(150, [item(S), item(L)]), row(120, [item(A), item(B), item(S)]),
])
# priority inversion and groups: the lower group gives way first, the higher one is cut last (L3)
define("text-priority-v1", [
    row(130, [item(A), item(B, p=1)]), row(130, [item(A, p=1), item(B)]), row(100, [item(A), item(B, p=1)]), row(100, [item(A, p=1), item(B)]),
    row(130, [item(A, p=2), item(B, p=1), item(S)]), row(130, [item(S), item(A, p=1), item(B, p=2)]),
    row(150, [item(A, p=1), item(B, p=1), item(S)]), row(120, [item(A, p=1), item(S, p=1), item(B)]),
])
define("text-three-groups-v1", [
    row(240, [item(L, p=2), item(A, p=1), item(B)]), row(240, [item(L), item(A, p=1), item(B, p=2)]), row(200, [item(L, p=1), item(A), item(B), item(S)]),
    row(200, [item(L), item(A, p=1), item(B, p=1), item(S, p=2)]), row(110, [item(A, p=-1), item(B)]), row(110, [item(A, p=0.5), item(B, p=0.25)]),
])
# Spacers keep their minimum length and take what the texts leave; a prioritised text is served before them (L5)
define("text-spacer-v1", [
    row(170, [item(A), sp(), item(B)]), row(200, [item(A), sp(), item(B)]), row(240, [item(A), sp(), item(B)]), row(150, [item(A, p=1), sp(), item(B)]),
    row(80, [sp(), item(A)]), row(200, [item(A), sp(30), item(B)]), row(130, [item(A), sp(), item(B, p=1)]), row(150, [item(A), sp(), item(B), sp(), item(S)]),
])
# the hub's exact controls: the Apps filter ("All", "Unused 90+ days", "Updates"), its priority-2 control beside the summary text, and the label rows that were cut at half
SEG = '            HStack(spacing: 8) {{ {inner} }}.frame(width: {w}, height: 28, alignment: .leading)'


def segmented(labels, color_start=0, prio=lambda label: 0, spacing=2):
    parts = []
    for i, lab in enumerate(labels):
        c = COL[(color_start + i) % len(COL)]
        pr = prio(lab)
        parts.append(f'Text("{lab}"){FONT}.lineLimit(1).padding(.horizontal, 12).padding(.vertical, 5).overlay {{ {c} }}' + (f".layoutPriority({pr})" if pr else ""))
    return f"HStack(spacing: {spacing}) {{ " + "; ".join(parts) + " }.padding(2)"


def hub_row(w, inner, nat=None):
    ROWNAT.append(nat or [-1] * inner.count(".overlay {"))   # the padded labels: no per-block natural width, every block may be a cut one
    return f"            {inner}.frame(width: {w}, height: 31, alignment: .leading)"


APPS = ["All", A, "Updates"]
define("hub-rows-v1", [
    hub_row(240, segmented(APPS)), hub_row(200, segmented(APPS)), hub_row(170, segmented(APPS)),
    hub_row(240, "HStack(spacing: 8) { " + f'Text("Sizes are measured on disk and keep updating"){FONT}.lineLimit(1).overlay {{ Color.green }}; ' + segmented(APPS).replace("}.padding(2)", "}.padding(2).layoutPriority(2)") + " }"),
    hub_row(170, segmented(["Start", B, "Status", "Clear 4.2 GB"], 1)),
    hub_row(150, segmented(["Start", B, "Status", "Clear 4.2 GB"], 1)),
])

# --- block 26: swiftui.text-views --------------------------------------------------------------------------------------------------------------------------------------
# a Text offered zero width reports zero (L1): a text that gets nothing leaves its neighbours' places, and a Text in a zero-width frame has no frame to show
define("text-zero-proposal-v1", [
    row(30, [item(A), "RECT30"]), row(58, [item(A), "RECT30"]), row(38, ["RECT30", item(A, ll=None), "RECT30"]),
    '            Text("Unused 90+ days").font(.custom("Tinos-Regular", size: 13)).lineLimit(1).frame(width: 0, height: 23, alignment: .leading).overlay { Color.red }',
    '            HStack(spacing: 0) { Color.blue.frame(width: 30, height: 23); Text("Demo Install").font(.custom("Tinos-Regular", size: 13)).frame(width: 0, height: 23).overlay { Color.red }; Color.green.frame(width: 30, height: 23) }.frame(width: 120, height: 23, alignment: .leading)',
], block="swiftui.text-views")
# fixedSize keeps the line whatever it is offered and is served first (L7)
define("text-fixed-size-v1", [
    row(110, [item(A, fixed=True), item(B)]), row(170, [item(A, fixed=True), item(B)]), row(130, [item(A, p=1, fixed=True), item(B)]), row(150, [item(A), item(B, p=1, fixed=True), item(S)]),
    row(60, [item(A, ll=None, fixed=True)]), row(110, [item(S), item(A, fixed=True)]), row(240, [item(L, fixed=True)]),
], block="swiftui.text-views")

# --- block 28: swiftui.system-font ---------------------------------------------------------------------------------------------------------------------------------------
# lineLimit(2) beside lineLimit(1) and unlimited neighbours: the rows are two lines tall (L6)
define("text-line-limit-two-v1", [
    row(100, [item(A, ll=2), item(B, ll=2)], height=38), row(130, [item(L, ll=2), item(S, ll=2)], height=38), row(110, [item(A, ll=2), item(B, ll=1)], height=38),
], block="swiftui.system-font")
# Not gated (decision L6): an unlimited Text that wraps onto two lines. The Mac balances the lines (A offered 77 pt of Tinos: "Unused" over "90+ days", 47.6 wide) where the Windows host wraps
# greedily ("Unused 90+" over "days", 66.4 wide); the offer, the order and the sizes of the stack are the same, the wrapping is the renderer's.


def main():
    only = sys.argv[1:]
    for name, c in CASES.items():
        if only and not any(o in name for o in only): continue
        body = c["body"]
        with tempfile.TemporaryDirectory() as d:
            w = Path(d) / "Witness.swift"; w.write_text(HEADER + body + "\n")
            cmd = [sys.executable, str(H / "new-case.py"), name, str(w), c["type"] + "()", "--font", FONT_FILE]
            if c["pair"]:
                p = Path(d) / "pair.json"; p.write_text(json.dumps(c["pair"])); cmd += ["--pair-json", str(p)]
            subprocess.check_call(cmd)


if __name__ == "__main__":
    main()
