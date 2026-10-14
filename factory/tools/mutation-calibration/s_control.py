"""Control gates: pair_button_report.py (push Button: height/y, caps, flat bands, label centre and ink) and pair_control_report.py (labelled Toggle: control size/y/edges, label centre)."""
from core import M
from mutlib import *
import pair_button_report as B
import pair_control_report as C

MUTATIONS = []
add = lambda gate, *a, **k: MUTATIONS.append(M(gate, *a, **k))
GB, GK = "button", "control"
WHITE = (255, 255, 255)


def W(ctx): return load(ctx.p("windows/native-01.png"))
def MAC(ctx): return load(ctx.p("mac/run-01.png"))
def S(ctx, im): save(im, ctx.p("windows/native-01.png"))


def clipped_shift(im, rect, dx, dy, bg):
    inner = Image.new("RGB", (rect[2] - rect[0], rect[3] - rect[1]), bg); inner.paste(im.crop(rect), (dx, dy))
    out = im.copy(); out.paste(inner, rect[:2]); return out


# ---------------- button gate ----------------
def bb(im): return C.bbox_nonwhite(im, (0, 0) + im.size)


def cap(ctx): return int(ctx.cfg["buttonGate"].get("capPx", 28))


def fill_of(ctx):
    m = MAC(ctx); mb = bb(m); return m.getpixel((mb[0] + cap(ctx) // 2, (mb[1] + mb[3]) // 2))


def label_rect(ctx, im):
    b = bb(im); c = cap(ctx); return (b[0] + c - 4, b[1] + 4, b[2] - c + 4, b[3] - 4)


def b_yshift(dy):
    def f(ctx):
        im = W(ctx); b = bb(im); S(ctx, shift_rect(im, (b[0] - 2, b[1] - 2, b[2] + 2, b[3] + 3), 0, dy, WHITE)); return f"whole button moved {dy} px down (height and width unchanged); y gate tolerance {ctx.cfg['buttonGate'].get('yTolerancePx', 0)} px"
    return f


def b_height(ctx):
    im = W(ctx); b = bb(im); row = im.crop((b[0], b[3] - 1, b[2], b[3])); out = im.copy(); out.paste(row, (b[0], b[3])); S(ctx, out)
    return f"button one pixel taller (bottom row repeated): {b} -> {bb(W(ctx))}"


def b_missing(ctx):
    im = W(ctx); b = bb(im); S(ctx, fill(im, (b[0] - 2, b[1] - 2, b[2] + 2, b[3] + 2), WHITE)); return "the whole button removed"


def b_label_missing(ctx):
    im = W(ctx); r = label_rect(ctx, im); S(ctx, fill(im, r, fill_of(ctx))); return "the label removed (flat fill left)"


def label_dark(ctx, im):
    return B.label_ink(im, bb(im), fill_of(ctx), cap(ctx))


def b_label_colour(target):
    """shift every label ink pixel until the darkest/brightest ink differs from the Mac's by exactly `target` levels (tolerance 40: 40 must pass, 41 must fail)"""
    def f(ctx):
        base = W(ctx); fill_c = fill_of(ctx); r = label_rect(ctx, base); mac_ink = B.label_ink(MAC(ctx), bb(MAC(ctx)), fill_c, cap(ctx))[1]
        for d in range(0, 150):
            for sg in (1, -1):
                im = recolour_where(base, lambda p: p != fill_c, lambda p: add_delta(p, sg * d), r)
                got = B.label_ink(im, bb(im), fill_c, cap(ctx))[1]
                if got is not None and abs(got - mac_ink) == target:
                    S(ctx, im); return f"label ink {sg * d:+d} levels in every channel: darkest/farthest ink luminance {got} vs Mac {mac_ink}: delta {target} (tolerance {ctx.cfg['buttonGate'].get('labelColourTolerance', 40)})"
        raise RuntimeError("no label shift reaches the target")
    return f


def b_label_move(axis, px=None, beyond=None):
    def f(ctx):
        base = W(ctx); fill_c = fill_of(ctx); tol = ctx.cfg["buttonGate"].get("labelCentreTolerancePx", 3)
        def err(im):
            b = bb(im); lw = B.label_ink(im, b, fill_c, cap(ctx))[0]
            return abs(((lw[0] + lw[2]) if axis == "x" else (lw[1] + lw[3])) / 2 - ((b[0] + b[2]) if axis == "x" else (b[1] + b[3])) / 2)
        sh = lambda s: clipped_shift(base, label_rect(ctx, base), s if axis == "x" else 0, s if axis == "y" else 0, fill_c)
        if px is None:
            ok = [s for s in range(0, 9) if err(sh(s)) <= tol]; s = max(ok) + (1 if beyond else 0)
        else:
            s = px
        S(ctx, sh(s)); return f"label moved {s} px along {axis}; label centre error now {err(W(ctx)):.1f} px (tolerance {tol})"
    return f


def b_corners(ctx):
    im = W(ctx); b = bb(im); R = 26; px = im.load()
    for cx, cy, sx, sy in ((b[0], b[1], 1, 1), (b[2] - 1, b[1], -1, 1), (b[0], b[3] - 1, 1, -1), (b[2] - 1, b[3] - 1, -1, -1)):
        for j in range(R):
            for i in range(R):
                if math.hypot(R - 0.5 - i, R - 0.5 - j) > R:
                    px[cx + sx * i, cy + sy * j] = WHITE
    S(ctx, im); return "wrong corner radius: the four button corners cut to a 26 px radius (artwork has about 17.5 px)"


def b_fill(delta):
    def f(ctx):
        fc = fill_of(ctx); S(ctx, recolour_where(W(ctx), lambda p: p == fc, lambda p: add_delta(p, delta))); return f"flat fill {fc} {delta:+d} levels everywhere"
    return f


def partial_in_band(canvas, region, pick=0.5):
    """a pixel inside the AA band of `canvas` (the very image the gate hands to edge_gate) that is neither the white background nor a flat interior colour"""
    pts = [p for p in band_pixels(canvas, True, region) if canvas.getpixel(p) != WHITE]
    return pts[int(len(pts) * pick)]


def b_cap_pixel(delta):
    def f(ctx):
        mac, win = MAC(ctx), W(ctx); mb, wb = bb(mac), bb(win); c = cap(ctx)
        canvas = Image.new("RGB", mac.size, WHITE); canvas.paste(mac.crop((mb[0], mb[1], mb[0] + c, mb[3])), (0, 0))   # the left-cap canvas the gate builds
        cx, cy = partial_in_band(canvas, (0, 0, c, mb[3] - mb[1]))
        mxy, wxy = (mb[0] + cx, mb[1] + cy), (wb[0] + cx, mb[1] + cy)
        S(ctx, set_diff_vs_mac(win, mac, wxy, delta) if False else _setdiff(win, mac.getpixel(mxy), wxy, delta))
        return f"one left-cap AA pixel (canvas {(cx, cy)}, Mac {mxy}, Windows {wxy}) set {delta} levels from the Mac pixel {mac.getpixel(mxy)} (edge-aa 32)"
    return f


def _setdiff(win, macpix, wxy, delta):
    out = win.copy(); sign = 1 if max(macpix) + delta <= 255 else -1
    out.putpixel(wxy, tuple(clip(c + sign * delta) for c in macpix)); return out


def b_width(n):
    """widen (n>0) or narrow (n<0) the straight middle by |n| px, half on each side of the label, flat columns only; the label stays centred"""
    def f(ctx):
        im = W(ctx); b = bb(im); c = cap(ctx); h = abs(n) // 2; H = im.height; xl, xr = b[0] + c, b[2] - c
        L, R = im.crop((0, 0, xl, H)), im.crop((xr, 0, im.width, H)); Mid = im.crop((xl, 0, xr, H))
        if n > 0:
            fl, fr = im.crop((xl, 0, xl + 1, H)).resize((h, H)), im.crop((xr - 1, 0, xr, H)).resize((h, H))
            new = Image.new("RGB", (im.width + 2 * h, H), WHITE); new.paste(L, (0, 0)); new.paste(fl, (xl, 0)); new.paste(Mid, (xl + h, 0)); new.paste(fr, (xr + h, 0)); new.paste(R, (xr + 2 * h, 0))
        else:
            new = Image.new("RGB", (im.width - 2 * h, H), WHITE); new.paste(L, (0, 0)); new.paste(Mid.crop((h, 0, Mid.width - h, H)), (xl, 0)); new.paste(R, (xr - 2 * h, 0))
        out = Image.new("RGB", im.size, WHITE); off = -h if n > 0 else h; out.paste(new, (off, 0)); S(ctx, out)
        return f"button {'widened' if n > 0 else 'narrowed'} by {abs(n)} px in the flat middle (label untouched): width {b[2] - b[0]} -> {(bb(W(ctx))[2] - bb(W(ctx))[0])} (reported only: label advance, decision 2)"
    return f


def b_enabled_look(ctx):
    """a disabled button painted with the enabled look: fill 245 -> 235 and label 182 -> 36"""
    fc = fill_of(ctx); im = W(ctx); r = label_rect(ctx, im)
    im = recolour_where(im, lambda p: p == fc, lambda p: (235, 235, 235)); S(ctx, im)
    S(ctx, recolour_where(W(ctx), lambda p: p != (235, 235, 235) and abs(p[0] - 235) > 30, lambda p: tuple(clip(c * 36 / max(1, 182)) for c in p), r))
    return f"disabled button drawn with the enabled fill (235) and a dark label"


def b_fill_wrong(colour):
    def f(ctx):
        fc = fill_of(ctx); S(ctx, recolour_where(W(ctx), lambda p: p == fc, lambda p: colour)); return f"flat fill {fc} replaced by {colour}"
    return f


for base in ("btn-bordered", "btn-prominent", "btn-disabled"):
    add(GB, base, "y-shift-1px", "catch", b_yshift(1), "1 px vertical shift of the button (y tolerance 0)")
    add(GB, base, "height+1px", "catch", b_height, "button 1 px taller")
    add(GB, base, "missing-button", "catch", b_missing, "a missing element: the button is gone")
    add(GB, base, "label-missing", "catch", b_label_missing, "a missing element: the label is gone")
    add(GB, base, "label-ink-just-beyond", "catch", b_label_colour(41), "label ink colour 41 levels from the Mac (tolerance 40)")
    add(GB, base, "label-ink-at-tolerance", "near", b_label_colour(40), "label ink colour exactly 40 levels from the Mac: must pass")
    add(GB, base, "label-centre-x-beyond", "catch", b_label_move("x", beyond=True), "label centring offset 1 px beyond the 3 px tolerance (x)")
    add(GB, base, "label-centre-x-near", "near", b_label_move("x", beyond=False), "label centring offset at the 3 px tolerance (x): must pass")
    add(GB, base, "label-centre-y-beyond", "catch", b_label_move("y", beyond=True), "label centring offset 1 px beyond the 3 px tolerance (y)")
    add(GB, base, "label-centre-y-near", "near", b_label_move("y", beyond=False), "label centring offset at the 3 px tolerance (y): must pass")
    add(GB, base, "label-origin-2pt-x", "catch", b_label_move("x", px=5), "label text origin 2 pt (5 px) off horizontally")
    add(GB, base, "label-origin-2pt-y", "catch", b_label_move("y", px=5), "label text 2 pt (5 px) off vertically")
    add(GB, base, "corner-radius", "catch", b_corners, "wrong corner radius")
    add(GB, base, "fill+5", "catch", b_fill(5), "flat fill 5 levels off")
    add(GB, base, "cap-pixel+33", "catch", b_cap_pixel(33), "one cap edge pixel 33 levels off (edge-aa 32)")
    add(GB, base, "cap-pixel+32", "near", b_cap_pixel(32), "one cap edge pixel exactly 32 levels off: must pass")
    add(GB, base, "width+8px", "near", b_width(8), "button 8 px wider (label advance difference is reported, never gated)")
    add(GB, base, "width-8px", "near", b_width(-8), "button 8 px narrower")
add(GB, "btn-disabled", "enabled-look", "catch", b_enabled_look, "disabled button drawn with the enabled colours")
add(GB, "btn-prominent", "fill-grey", "catch", b_fill_wrong((235, 235, 235)), "prominent (accent) fill replaced by the bordered grey")


# ---------------- control gate (labelled toggle) ----------------
def cmin(ctx): return int(ctx.cfg["controlGate"].get("minControlHeightPx", 50))


def ctl_geometry(ctx, im):
    cols = C.ink_columns(im, cmin(ctx)); x0, x1 = C.grow_to_gap(im, *cols[0]); rect = (x0, 0, x1, im.height); b = C.bbox_nonwhite(im, rect)
    return dict(span=(x0, x1), box=b, label=C.label_box(im, (x0, x1)))


def k_cmove(dx, dy):
    def f(ctx):
        im = W(ctx); g = ctl_geometry(ctx, im); b = g["box"]
        S(ctx, shift_rect(im, (max(0, b[0] - 1), max(0, b[1] - 1), b[2] + 1, b[3] + 1), dx, dy, WHITE)); return f"control moved ({dx},{dy}) px (box {b})"
    return f


def k_cy_derived(beyond):
    def f(ctx):
        base = W(ctx); mg = ctl_geometry(ctx, MAC(ctx)); tol = int(ctx.cfg["controlGate"].get("controlYTolerancePx", 0))
        def dy_of(im): return ctl_geometry(ctx, im)["box"][1] - mg["box"][1]
        b = ctl_geometry(ctx, base)["box"]; d0 = dy_of(base)
        want = (tol + 1 if beyond else tol) * (1 if d0 >= 0 else 1)
        s = want - d0
        im = shift_rect(base, (b[0] - 1, b[1] - 1, b[2] + 1, b[3] + 3 + abs(s)), 0, s, WHITE) if s else base
        S(ctx, im); return f"control y offset vs the Mac {d0} -> {dy_of(W(ctx))} px (tolerance {tol}); moved {s} px"
    return f


def k_height(ctx):
    im = W(ctx); b = ctl_geometry(ctx, im)["box"]; S(ctx, fill(im, (b[0], b[3] - 1, b[2], b[3]), WHITE)); return "control one pixel shorter (bottom row removed)"


def k_label_move(dx, dy, beyond=None):
    def f(ctx):
        base = W(ctx); g = ctl_geometry(ctx, base); lb = g["label"]; tol = int(ctx.cfg["controlGate"].get("labelCentreTolerancePx", 3)); mg = ctl_geometry(ctx, MAC(ctx))
        mc = (mg["label"][1] + mg["label"][3]) / 2
        def err(im): l = ctl_geometry(ctx, im)["label"]; return abs((l[1] + l[3]) / 2 - mc)
        rect = (lb[0] - 1, lb[1] - 8, lb[2] + 1, lb[3] + 8)
        if beyond is not None:
            sh = lambda s: clipped_shift(base, rect, 0, s, WHITE)
            ok = [s for s in range(0, 10) if err(sh(s)) <= tol]; s = max(ok) + (1 if beyond else 0); S(ctx, sh(s)); return f"label moved {s} px down; centre error now {err(W(ctx)):.1f} px (tolerance {tol})"
        S(ctx, clipped_shift(base, rect, dx, dy, WHITE)); return f"label moved ({dx},{dy}) px; centre error now {err(W(ctx)):.1f} px"
    return f


def k_label_missing(ctx):
    im = W(ctx); lb = ctl_geometry(ctx, im)["label"]; S(ctx, fill(im, (lb[0] - 1, lb[1] - 1, lb[2] + 1, lb[3] + 1), WHITE)); return "the label removed"


def k_control_missing(ctx):
    im = W(ctx); b = ctl_geometry(ctx, im)["box"]; S(ctx, fill(im, (b[0] - 3, b[1] - 3, b[2] + 3, b[3] + 3), WHITE)); return "the control removed"


def k_recolour(delta=None, target=None):
    def f(ctx):
        im = W(ctx); b = ctl_geometry(ctx, im)["box"]
        cnt = Counter(p for p in im.crop(tuple(b)).getdata() if p != WHITE); col = cnt.most_common(1)[0][0]
        fn = (lambda p: target) if target else (lambda p: add_delta(p, delta))
        S(ctx, recolour_where(im, lambda p: p == col, fn, tuple(b))); return f"control's dominant flat colour {col} " + (f"replaced by {target}" if target else f"{delta:+d} levels")
    return f


def k_band(delta):
    def f(ctx):
        mac, win = MAC(ctx), W(ctx); mg, wg = ctl_geometry(ctx, mac), ctl_geometry(ctx, win); mb, wb = mg["box"], wg["box"]
        canvas = Image.new("RGB", mac.size, WHITE); canvas.paste(mac.crop(tuple(mb)), (mb[0], mb[1]))   # canvas A of the gate
        xy = partial_in_band(canvas, tuple(mb)); wxy = (xy[0] + wb[0] - mb[0], xy[1] + wb[1] - mb[1])
        S(ctx, _setdiff(win, mac.getpixel(xy), wxy, delta)); return f"one control edge pixel (Mac {xy}, Windows {wxy}) set {delta} levels from the Mac pixel {mac.getpixel(xy)} (edge-aa 32)"
    return f


for base in ("ctl-switch", "ctl-checkbox"):
    add(GK, base, "control-y-at-tolerance", "near", k_cy_derived(False), "control y offset exactly at its tolerance: must pass")
    add(GK, base, "control-y-beyond", "catch", k_cy_derived(True), "control y offset 1 px beyond its tolerance")
    add(GK, base, "control-y-2pt", "catch", k_cmove(0, 5), "control 2 pt (5 px) too low")
    add(GK, base, "control-height-1px", "catch", k_height, "control one pixel shorter (wrong size)")
    add(GK, base, "missing-control", "catch", k_control_missing, "a missing element: the control is gone")
    add(GK, base, "label-missing", "catch", k_label_missing, "a missing element: the label is gone")
    add(GK, base, "label-centre-beyond", "catch", k_label_move(0, 0, True), "label centring offset 1 px beyond the 3 px tolerance")
    add(GK, base, "label-centre-near", "near", k_label_move(0, 0, False), "label centring offset at the 3 px tolerance: must pass")
    add(GK, base, "label-origin-2pt-y", "catch", k_label_move(0, 5), "label 2 pt (5 px) off vertically")
    add(GK, base, "label-origin-3px-x", "near", k_label_move(3, 0), "label 3 px further right (label advance: reported only)")
    add(GK, base, "label-origin-2pt-x", "catch", k_label_move(5, 0), "label text origin 2 pt (5 px) off horizontally (label advance is reported, never gated)", design="docs/sr1-decisions.md item 2 and pair_control_report.py: dx and the label pixels are reported only")
    add(GK, base, "wrong-state-colour", "catch", k_recolour(target=(180, 180, 180)), "wrong toggle state: the on colour replaced by a grey")
    add(GK, base, "flat-colour+1", "catch", k_recolour(delta=1), "control flat colour 1 level off")
    add(GK, base, "edge-pixel+33", "catch", k_band(33), "one control edge pixel 33 levels off")
    add(GK, base, "edge-pixel+32", "near", k_band(32), "one control edge pixel exactly 32 levels off: must pass")
    add(GK, base, "control-x-2pt", "catch", k_cmove(5, 0), "control 2 pt (5 px) off horizontally", design="docs/sr1-decisions.md item 2 and pair_control_report.py: the control is compared after translating by the measured dx (the label-advance difference); dx is reported only")
