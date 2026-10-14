"""Text gates: pair_text_report.py (glyph-region ink bbox, positions outside the region) and pair_textcolour_report.py (strongest ink colour per region)."""
from core import M
from mutlib import *
import pair_text_report as T
import pair_textcolour_report as TC

MUTATIONS = []
add = lambda gate, *a, **k: MUTATIONS.append(M(gate, *a, **k))
GT, GC = "text", "text-colour"
D2 = "decision 2: glyph pixels excluded from the pixel gate"


def W(ctx): return load(ctx.p("windows/native-01.png"))
def S(ctx, im): save(im, ctx.p("windows/native-01.png"))


def clipped_shift(im, rect, dx, dy, bg):
    inner = Image.new("RGB", (rect[2] - rect[0], rect[3] - rect[1]), bg); inner.paste(im.crop(rect), (dx, dy))
    out = im.copy(); out.paste(inner, rect[:2]); return out


# ---- text gate (text-gate: bundled-font v6, rect [0,5,297,53], edgeTolerancePx 1) ----
def half_deltas(ctx, im):
    rect = tuple(ctx.cfg["textGate"]["rect"])
    ma, wa = T.bbox_of(load(ctx.p("mac/run-01.png")), rect, 127), T.bbox_of(im, rect, 127)
    return None if ma is None or wa is None else [w - m for m, w in zip(ma, wa)] and [w - m for m, w in zip(ma, wa)]


def tg_shift(dx, dy, label):
    def f(ctx):
        rect = tuple(ctx.cfg["textGate"]["rect"]); im = W(ctx)
        S(ctx, clipped_shift(im, rect, dx, dy, bg_of(im)))
        return f"glyph region content moved ({dx},{dy}) px; half-coverage bbox delta now {half_deltas(ctx, W(ctx))} (tolerance 1)"
    return f


def tg_derived(beyond, axis="x"):
    """the largest shift (right/down) whose half-coverage bbox deltas all stay within the tolerance, or one pixel more"""
    def f(ctx):
        rect = tuple(ctx.cfg["textGate"]["rect"]); base = W(ctx); tol = ctx.cfg["textGate"]["edgeTolerancePx"]; best = 0
        for s in range(0, 8):
            im = clipped_shift(base, rect, s if axis == "x" else 0, s if axis == "y" else 0, bg_of(base))
            d = half_deltas(ctx, im)
            if d is not None and max(abs(v) for v in d) <= tol: best = s
        s = best + (1 if beyond else 0)
        S(ctx, clipped_shift(base, rect, s if axis == "x" else 0, s if axis == "y" else 0, bg_of(base)))
        return f"glyph region content moved {s} px along {axis} ({'1 px beyond' if beyond else 'the largest shift'} that keeps every half-coverage bbox edge within the 1 px tolerance); deltas now {half_deltas(ctx, W(ctx))}"
    return f


def tg_missing(ctx):
    rect = tuple(ctx.cfg["textGate"]["rect"]); im = W(ctx); S(ctx, fill(im, rect, bg_of(im))); return "all text removed from the glyph region"


def tg_colour(colour, what):
    def f(ctx):
        rect = tuple(ctx.cfg["textGate"]["rect"])
        S(ctx, recolour_where(W(ctx), lambda p: sum(p) < 600, lambda p: tuple(clip(c * k / 40 + (255 - k * 255 / 40) * 0) if False else c for c, k in zip(p, (1, 1, 1))) if False else colour_mix(p, colour), rect))
        return f"every ink pixel recoloured towards {colour} (luminance {int(0.299 * colour[0] + 0.587 * colour[1] + 0.114 * colour[2])}); {what}"
    return f


def colour_mix(p, colour):
    cov = (255 - sum(p) / 3) / 255.0       # coverage of black text over white
    return tuple(clip(255 + (c - 255) * cov) for c in colour)


def tg_noise(ctx):
    rect = tuple(ctx.cfg["textGate"]["rect"])
    S(ctx, recolour_where(W(ctx), lambda p: 200 < sum(p) / 3 < 250, lambda p: add_delta(p, -40), rect))
    return "faint anti-aliasing pixels (luminance 200-250) darkened by 40 levels; half-coverage ink (<=127) untouched"


def tg_outside(ctx):
    im = W(ctx); xy = (500, 300); im.putpixel(xy, add_delta(im.getpixel(xy), -1)); S(ctx, im); return "one pixel outside the glyph region 1 level off"


add(GT, "text-gate", "origin-offset-2pt-x", "catch", tg_shift(5, 0, "x"), "text origin 2 pt (5 px) to the right")
add(GT, "text-gate", "origin-offset-2pt-y", "catch", tg_shift(0, 5, "y"), "text 2 pt (5 px) too low")
add(GT, "text-gate", "centring-x-near", "near", tg_derived(False, "x"), "horizontal offset right at the 1 px tolerance: must pass")
add(GT, "text-gate", "centring-x-beyond", "catch", tg_derived(True, "x"), "horizontal offset 1 px beyond the tolerance")
add(GT, "text-gate", "centring-y-near", "near", tg_derived(False, "y"), "vertical offset right at the 1 px tolerance: must pass")
add(GT, "text-gate", "centring-y-beyond", "catch", tg_derived(True, "y"), "vertical offset 1 px beyond the tolerance")
add(GT, "text-gate", "text-missing", "catch", tg_missing, "a missing element: the text is gone")
add(GT, "text-gate", "ink-colour-light-grey", "catch", tg_colour((190, 190, 190), "ink too light for the half-coverage rule"), "label ink colour shifted to light grey (luminance 190)")
add(GC, "text-gate", "ink-colour-dark-red", "catch", tg_colour((120, 0, 0), "still dark enough to count as half-coverage ink"), "label ink colour shifted to dark red (the text-colour gate runs beside the text gate, decision 19)")
add(GT, "text-gate", "aa-noise-inside-region", "near", tg_noise, "anti-aliasing differences inside the glyph region (reported, never gated)")
add(GT, "text-gate", "pixel-outside-region", "catch", tg_outside, "a pixel outside the glyph region 1 level off")


# ---- text colour gate ----
def strongest_of(img, rect, bg):
    return TC.strongest(img, tuple(rect), bg)


def tc_shift(region, delta):
    """shift every ink pixel (not the background) of the region by +/-delta, sign chosen so the strongest pixel does not clip"""
    def f(ctx):
        cfg = ctx.cfg["textColourGate"]; reg = cfg["regions"][region]; bg = cfg.get("background"); im = W(ctx); rect = tuple(reg["rect"])
        base_bg = tuple(bg) if bg else (255, 255, 255)
        s = strongest_of(im, rect, bg)
        sign = next(sg for sg in (-1, 1) if all(0 <= c + sg * delta <= 255 for c in s))
        S(ctx, recolour_where(im, lambda p: p != base_bg, lambda p: add_delta(p, sign * delta), rect))
        now = strongest_of(W(ctx), rect, bg); mac = strongest_of(load(ctx.p("mac/run-01.png")), rect, bg)
        return f"region '{reg['name']}': every ink pixel {sign * delta:+d} levels; strongest ink {s} -> {now}, Mac {mac}, max channel delta {max(abs(a - b) for a, b in zip(now, mac))} (tolerance {cfg.get('tolerance', 24)})"
    return f


def tc_just(region, beyond):
    """find the per-channel shift that puts the max channel difference vs the Mac at exactly tolerance (near) or tolerance+1 (beyond)"""
    def f(ctx):
        cfg = ctx.cfg["textColourGate"]; tol = cfg.get("tolerance", 24); reg = cfg["regions"][region]; bg = cfg.get("background"); rect = tuple(reg["rect"])
        base = W(ctx); mac = strongest_of(load(ctx.p("mac/run-01.png")), rect, bg); base_bg = tuple(bg) if bg else (255, 255, 255)
        for d in range(0, 120):
            for sg in (-1, 1):
                im = recolour_where(base, lambda p: p != base_bg, lambda p: add_delta(p, sg * d), rect)
                s = strongest_of(im, rect, bg)
                if s and max(abs(a - b) for a, b in zip(s, mac)) == tol + (1 if beyond else 0):
                    S(ctx, im)
                    return f"region '{reg['name']}': ink {sg * d:+d} levels; strongest ink now {s} vs Mac {mac}: max channel delta {tol + (1 if beyond else 0)} ({'1 beyond' if beyond else 'at'} the tolerance {tol})"
        raise RuntimeError("no shift found")
    return f


def tc_swap(region):
    """wrong text colour: every ink pixel re-tinted towards (0, 136, 255) (the accent blue) with its own coverage; a hue change even for neutral grey text"""
    def f(ctx):
        cfg = ctx.cfg["textColourGate"]; reg = cfg["regions"][region]; rect = tuple(reg["rect"]); bg = tuple(cfg["background"]) if cfg.get("background") else (255, 255, 255)
        im = W(ctx); s = strongest_of(im, rect, cfg.get("background")); dmax = sum(abs(a - b) for a, b in zip(s, bg)) or 1
        def tint(p):
            cov = min(1.0, sum(abs(a - b) for a, b in zip(p, bg)) / dmax)
            return tuple(clip(b + (t - b) * cov) for b, t in zip(bg, (0, 136, 255)))
        S(ctx, recolour_where(im, lambda p: p != bg, tint, rect))
        return f"region '{reg['name']}': every ink pixel re-tinted to the accent blue (0,136,255) with its own coverage; strongest ink {s} -> {strongest_of(W(ctx), rect, cfg.get('background'))}"
    return f


def tc_missing(region):
    def f(ctx):
        reg = ctx.cfg["textColourGate"]["regions"][region]; rect = tuple(reg["rect"]); bg = ctx.cfg["textColourGate"].get("background")
        S(ctx, fill(W(ctx), rect, tuple(bg) if bg else (255, 255, 255))); return f"region '{reg['name']}': text removed"
    return f


def tc_move(region, dx, dy, clip=True):
    def f(ctx):
        reg = ctx.cfg["textColourGate"]["regions"][region]; rect = tuple(reg["rect"]); im = W(ctx)
        bg = ctx.cfg["textColourGate"].get("background"); bgc = tuple(bg) if bg else (255, 255, 255)
        S(ctx, clipped_shift(im, rect, dx, dy, bgc) if clip else shift_rect(im, rect, dx, dy, bgc))
        return f"region '{reg['name']}': text moved ({dx},{dy}) px" + (" inside its region" if clip else " out of its region")
    return f


for base, regions in (("tc-red", [0]), ("tc-fg", [0, 1]), ("tc-dark", [0, 3])):
    for r in regions:
        tag = f"{base}/r{r}"
        add(GC, base, f"r{r}-ink-just-beyond", "catch", tc_just(r, True), "ink colour 1 level beyond the 24 tolerance")
        add(GC, base, f"r{r}-ink-at-tolerance", "near", tc_just(r, False), "ink colour exactly at the 24 tolerance: must pass")
        add(GC, base, f"r{r}-ink-+40", "catch", tc_shift(r, 40), "label ink colour shifted by 40 levels")
        add(GC, base, f"r{r}-wrong-colour", "catch", tc_swap(r), "wrong ink colour (re-tinted to the accent blue)")
        add(GC, base, f"r{r}-missing-text", "catch", tc_missing(r), "a missing element")
        add(GC, base, f"r{r}-origin-offset-2pt", "catch", tc_move(r, 5, 0), "text origin 2 pt (5 px) off inside its excluded region (decision 19 gates the line's position)")
        add(GC, base, f"r{r}-origin-offset-2pt-left", "catch", tc_move(r, -5, 0), "text origin 2 pt (5 px) off to the left inside its excluded region")
        add(GC, base, f"r{r}-centring-y-2pt", "catch", tc_move(r, 0, 5), "text 2 pt (5 px) off vertically inside its excluded region")
        add(GC, base, f"r{r}-centring-y-up-2pt", "catch", tc_move(r, 0, -5), "text 2 pt (5 px) too high inside its excluded region")
        add(GC, base, f"r{r}-centring-y-2px", "catch", tc_move(r, 0, 2), "text 2 px (about 1 pt) too low (the mid-point of first ink y and baseline is gated to 0.5 px)")
    add(GC, base, "text-moved-out-of-exclusions", "catch", tc_move(regions[0], 60, 0, clip=False) if base != "tc-dark" else tc_move(regions[0], 0, 300, clip=False), "text moved out of every excluded region (the pixel gate sees it)")
