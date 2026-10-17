"""H34 proof (sr1-decisions H34): body-text first ink x, Windows minus Mac, must lie in [firstInkMinPx 0, firstInkMaxPx 1] (the one-sided range of the
four fixtures below, each measured +1 px in CI run 38984400470 and in the 20261017-000201 captures). The seeded faults move the Windows first ink by a
1 pt = 2.5 px shift (applied as 2 px and 3 px, the two whole-pixel neighbours of 2.5), a 2 pt = 5 px shift, and single pixels:

  shift +2 / +3 px (+1 pt)     catch: the delta becomes +3 / +4
  shift -2 / -3 px (-1 pt)     catch: the delta becomes -1 / -2, below the range's 0
  shift +5 px / -5 px (2 pt)   catch
  shift +1 px                  catch: the delta becomes +2, above the range's 1
  shift -1 px                  near-miss, must PASS: the delta becomes 0, inside [0, 1]. A one-pixel move the other way is inside the allowance by design;
                               the negative side is caught by -2 px (delta -1)

Gates: textfield bases are decided by the text-origin gate, text-dark by the text-colour gate, the switch label by the control gate (its label x and gap).
Verdicts come from pair.py --recompare (core.run_one); this module only stages the pixels."""
from core import M
from mutlib import *
import pair_control_report as C
import pair_textcolour_report as TC
import pair_textorigin_report as T

MUTATIONS = []
add = lambda *a, **k: MUTATIONS.append(M(*a, **k))

GO, GCOL, GCTL = "text-origin", "text-colour", "control"
SHIFTS = [
    (2, "catch", "+1 pt (2 px)"), (3, "catch", "+1 pt (3 px)"), (5, "catch", "+2 pt (5 px)"),
    (1, "catch", "+1 px (delta +2, past the range)"),
    (-1, "near", "-1 px (delta 0, inside the range: must pass)"),
    (-2, "catch", "-1 pt (2 px)"), (-3, "catch", "-1 pt (3 px)"), (-5, "catch", "-2 pt (5 px)"),
]


def W(ctx): return load(ctx.p("windows/native-01.png"))
def S(ctx, im): save(im, ctx.p("windows/native-01.png"))
def MAC(ctx): return load(ctx.p("mac/run-01.png"))


def shift_rect_px(im, rect, dx):
    """move the content of rect by dx px along x, the vacated columns take the rect's most common colour"""
    x0, y0, x1, y1 = rect
    bg = Counter(im.crop(rect).getdata()).most_common(1)[0][0]
    box = Image.new("RGB", (x1 - x0, y1 - y0), bg)
    box.paste(im.crop(rect), (dx, 0))
    out = im.copy(); out.paste(box, (x0, y0)); return out


def textfield_inner(f): return (f[0] + 4, f[1] + 12, f[2] - 4, f[3] - 12)   # bezelled: inside the field, clear of the border (as s_textorigin.inner)
def plain_inner(f): return (f[0] + 1, f[1] + 2, f[2] - 1, f[3] - 2)          # no bezel: the text starts at x 27 of a frame at 25, so only 1 px of margin


def textfield_shift(dx, inner):
    def f(ctx):
        fr = ctx.cfg["textOriginGate"]["fields"][0]; im = W(ctx)
        out = shift_rect_px(im, inner(fr), dx); S(ctx, out)
        margin = int(ctx.cfg["textOriginGate"].get("scanInteriorPx", 2))
        m, w = T.analyse(MAC(ctx), fr, margin), T.analyse(out, fr, margin)
        return f"field 0 contents {dx:+d} px: first ink Mac {m['firstInkX']}, Windows {w['firstInkX']} (delta {w['firstInkX'] - m['firstInkX']:+d})"
    return f


def textcolour_shift(dx):
    def f(ctx):
        tc = ctx.cfg["textColourGate"]; r = tc["regions"][0]; rect = tuple(r["rect"]); im = W(ctx)
        out = shift_rect_px(im, rect, dx); S(ctx, out)
        bg = tuple(tc["background"]); cov = float(tc.get("position", {}).get("coverage", 0.15))
        m, w = TC.position(MAC(ctx), rect, bg, cov), TC.position(out, rect, bg, cov)
        return f"region {r['name']} {dx:+d} px: first ink Mac {m['firstInkX']}, Windows {w['firstInkX']} (delta {w['firstInkX'] - m['firstInkX']:+d})"
    return f


def label_rect(im, min_h):
    cm = C.ink_columns(im, min_h)
    x0, x1 = C.grow_to_gap(im, *cm[0])
    lb = C.label_box(im, (x0, x1))
    return (x0, x1), lb


def control_label_shift(dx):
    def f(ctx):
        min_h = int(ctx.cfg["controlGate"].get("minControlHeightPx", 50)); im = W(ctx)
        span, lb = label_rect(im, min_h)
        w_, h_ = im.size
        rect = (max(0, lb[0] - 6), max(0, lb[1] - 2), min(w_, lb[2] + 6), min(h_, lb[3] + 2))
        out = shift_rect_px(im, rect, dx); S(ctx, out)
        _, lbm = label_rect(MAC(ctx), min_h)
        _, lbw = label_rect(out, min_h)
        return f"label {dx:+d} px: label first ink Mac {lbm[0]}, Windows {lbw[0]} (delta {lbw[0] - lbm[0]:+d})"
    return f


for base, inner in (("h34-textfield-plain", plain_inner), ("h34-textfield-auto", textfield_inner)):
    for dx, kind, what in SHIFTS:
        add(GO, base, f"first-ink-shift{dx:+d}px", kind, textfield_shift(dx, inner), f"text-origin first ink, {what}")
for dx, kind, what in SHIFTS:
    add(GCOL, "h34-textdark", f"first-ink-shift{dx:+d}px", kind, textcolour_shift(dx), f"text-colour first ink (region primary), {what}")
    add(GCTL, "h34-switch", f"label-shift{dx:+d}px", kind, control_label_shift(dx), f"switch label first ink, {what}")
