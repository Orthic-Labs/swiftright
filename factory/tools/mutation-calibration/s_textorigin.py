"""Text-origin gate (sr1-decisions #12): pair_textorigin_report.py: first ink x, selection colour and start x, caret x, for bezeled TextField cases."""
from core import M
from mutlib import *
import pair_textorigin_report as T

MUTATIONS = []
add = lambda *a, **k: MUTATIONS.append(M("text-origin", *a, **k))
CARET = (17, 17, 17)


def W(ctx): return load(ctx.p("windows/native-01.png"))
def S(ctx, im): save(im, ctx.p("windows/native-01.png"))


def inner(f): return (f[0] + 4, f[1] + 12, f[2] - 4, f[3] - 12)     # inside the field, clear of the 1 pt border and the 15 px corners


def field_bg(im, f):
    return Counter(im.crop(inner(f)).getdata()).most_common(1)[0][0]


def move_text(k, dx, dy):
    def f(ctx):
        fr = ctx.cfg["textOriginGate"]["fields"][k]; im = W(ctx); r = inner(fr); bg = field_bg(im, fr)
        box = Image.new("RGB", (r[2] - r[0], r[3] - r[1]), bg); box.paste(im.crop(r), (dx, dy)); out = im.copy(); out.paste(box, r[:2]); S(ctx, out)
        a, b = T.analyse(load(ctx.p("mac/run-01.png")), fr), T.analyse(W(ctx), fr)
        return f"field {k}: contents moved ({dx},{dy}) px; first ink x Mac {a['firstInkX']}, Windows {b['firstInkX']}"
    return f


def missing_ink(k):
    def f(ctx):
        fr = ctx.cfg["textOriginGate"]["fields"][k]; im = W(ctx); S(ctx, fill(im, inner(fr), field_bg(im, fr))); return f"field {k}: all contents removed"
    return f


def clip_right(k):
    def f(ctx):
        fr = ctx.cfg["textOriginGate"]["fields"][k]; im = W(ctx); a = T.analyse(im, fr); r = inner(fr); x = a["firstInkX"] + 12
        S(ctx, fill(im, (x, r[1], r[2], r[3]), field_bg(im, fr))); return f"field {k}: everything right of x={x} removed (first ink at {a['firstInkX']} untouched: the text is clipped/truncated differently on the right)"
    return f


def sel_recolour(k, colour):
    def f(ctx):
        fr = ctx.cfg["textOriginGate"]["fields"][k]; im = W(ctx); sel = T.analyse(im, fr)["selection"]; col = tuple(sel["colour"])
        S(ctx, recolour_where(im, lambda p: p == col, lambda p: colour, fr)); return f"field {k}: selection colour {col} -> {colour}"
    return f


def sel_missing(k):
    def f(ctx):
        fr = ctx.cfg["textOriginGate"]["fields"][k]; im = W(ctx); sel = T.analyse(im, fr)["selection"]; col = tuple(sel["colour"]); bg = field_bg(im, fr)
        S(ctx, recolour_where(im, lambda p: p == col, lambda p: bg, fr)); return f"field {k}: selection highlight not drawn"
    return f


def sel_start(k, d):
    """move the highlight's left edge: d>0 trims d columns, d<0 grows -d columns (columns of the exact selection colour over the highlight's rows)"""
    def f(ctx):
        fr = ctx.cfg["textOriginGate"]["fields"][k]; im = W(ctx); sel = T.analyse(im, fr)["selection"]; col = tuple(sel["colour"]); bg = field_bg(im, fr); px = im.load()
        for i in range(abs(d)):
            x = sel["startX"] + i if d > 0 else sel["startX"] - 1 - i
            for y in range(sel["y0"], sel["y1"]):
                if d > 0:
                    if px[x, y] == col: px[x, y] = bg
                else:
                    if px[x, y] == bg: px[x, y] = col
        S(ctx, im); now = T.analyse(W(ctx), fr)["selection"]; return f"field {k}: highlight left edge moved {d:+d} px (start x {sel['startX']} -> {now['startX'] if now else None})"
    return f


def sel_end(k, d):
    def f(ctx):
        fr = ctx.cfg["textOriginGate"]["fields"][k]; im = W(ctx); sel = T.analyse(im, fr)["selection"]; col = tuple(sel["colour"]); bg = field_bg(im, fr); px = im.load()
        for i in range(d):
            for y in range(sel["y0"], sel["y1"]):
                if px[sel["endX"] - i, y] == col: px[sel["endX"] - i, y] = bg
        S(ctx, im); return f"field {k}: highlight right edge trimmed {d} px (end x {sel['endX']} -> {T.analyse(W(ctx), fr)['selection']['endX']}; reported only)"
    return f


def sel_height(k, d):
    def f(ctx):
        fr = ctx.cfg["textOriginGate"]["fields"][k]; im = W(ctx); sel = T.analyse(im, fr)["selection"]; col = tuple(sel["colour"]); bg = field_bg(im, fr); px = im.load()
        for y in range(sel["y0"], sel["y0"] + d):
            for x in range(sel["startX"] + 1, sel["endX"]):
                if px[x, y] == col: px[x, y] = bg
        S(ctx, im); return f"field {k}: highlight {d} rows shorter (reported only)"
    return f


def caret_move(dx):
    def f(ctx):
        fr = ctx.cfg["textOriginGate"]["fields"][0]; im = W(ctx); a = T.analyse(im, fr); bg = field_bg(im, fr); px = im.load()
        cols = a["caretX"]
        pts = [(x, y) for x in cols for y in range(fr[1], fr[3]) if px[x, y] == CARET]
        for x, y in pts: px[x, y] = bg
        for x, y in pts: px[x + dx, y] = CARET
        S(ctx, im); return f"caret columns {cols} moved {dx:+d} px (Mac insertion point {T.mac_caret_px(ctx.run, '01')})"
    return f


def caret_missing(ctx):
    fr = ctx.cfg["textOriginGate"]["fields"][0]; im = W(ctx); bg = field_bg(im, fr); S(ctx, recolour_where(im, lambda p: p == CARET, lambda p: bg, fr)); return "caret not drawn"


def tol_cfg(ink=None):
    def f(ctx):
        ctx.cfg["textOriginGate"]["firstInkTolerancePx"] = ink; ctx.save_cfg()
    return f


# to-filled: a filled, truncated TextField (first ink 42 on both sides)
B = "to-filled"
add(B, "origin-2pt-left", "catch", move_text(0, -5, 0), "text origin 2 pt (5 px) too far left (the original defect)")
add(B, "origin-2pt-right", "catch", move_text(0, 5, 0), "text origin 2 pt (5 px) too far right")
add(B, "origin-1px", "catch", move_text(0, 1, 0), "text origin 1 px off (tolerance is 0)")
add(B, "origin--1px", "catch", move_text(0, -1, 0), "text origin 1 px left")
add(B, "centring-y-2pt", "catch", move_text(0, 0, 5), "text 2 pt (5 px) too low (centring)", design="decision 12 gates x (first ink, selection start, caret); the text rect stays excluded from the pixel gate (decision 2) and no gate reads the text's y")
add(B, "text-missing", "catch", missing_ink(0), "a missing element: the text is gone")
add(B, "right-clip-differs", "near", clip_right(0), "text clipped/truncated differently on the right (first ink unchanged)")
# to-selected: Tab/FocusState focus selects the whole text (field 0 selected, field 1 not)
B = "to-selected"
add(B, "selection-colour+1", "catch", sel_recolour(0, (179, 215, 254)), "selection colour one level off (179,215,254)")
add(B, "selection-colour-grey", "catch", sel_recolour(0, (220, 220, 220)), "selection in the inactive grey (220)")
add(B, "selection-colour-accent", "catch", sel_recolour(0, (0, 100, 225)), "selection in the list accent colour instead of (179,215,255)")
add(B, "selection-missing", "catch", sel_missing(0), "a missing element: the selection is not drawn")
add(B, "selection-start+1", "catch", sel_start(0, 1), "selection start 1 px right")
add(B, "selection-start-1", "catch", sel_start(0, -1), "selection start 1 px left")
add(B, "selection-start+5", "catch", sel_start(0, 5), "selection start 2 pt (5 px) right")
add(B, "origin-2pt-left", "catch", move_text(0, -5, 0), "text origin 2 pt (5 px) left inside a selected field")
add(B, "selection-end-5px", "near", sel_end(0, 5), "selection end 5 px shorter (glyph advances, Segoe vs SF: reported only)")
add(B, "selection-height-2px", "near", sel_height(0, 2), "selection 2 rows shorter (line height, reported only)")
add(B, "unselected-field-origin-2pt", "catch", move_text(1, -5, 0), "the second (unselected) field's text 2 pt left")
# to-caret: empty focused field, Mac insertion point read from MAC_FACT caretXpx
B = "to-caret"
add(B, "caret+1px", "catch", caret_move(1), "caret 1 px right of the Mac insertion point")
add(B, "caret-1px", "catch", caret_move(-1), "caret 1 px left")
add(B, "caret+5px", "catch", caret_move(5), "caret 2 pt (5 px) right (text origin offset)")
add(B, "caret-missing", "catch", caret_missing, "a missing element: no caret")
MUTATIONS = [m for m in MUTATIONS if m is not None]
