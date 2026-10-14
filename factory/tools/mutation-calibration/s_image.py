"""Image gate (Image(systemName:), decision 3): pair_image_report.py: the logged Image view frame, exact pixels outside the frame, half-coverage ink bbox, tint colour; glyph shape reported only."""
import re
from core import M
from mutlib import *
import pair_image_report as I

MUTATIONS = []
add = lambda *a, **k: MUTATIONS.append(M("image", *a, **k))
WHITE, TINT = (255, 255, 255), (255, 204, 0)


def W(ctx): return load(ctx.p("windows/native-01.png"))
def S(ctx, im): save(im, ctx.p("windows/native-01.png"))


def glyph_move(dx, dy):
    def f(ctx):
        im = W(ctx); S(ctx, shift_rect(im, (0, 0, 84, 84), dx, dy, WHITE)); return f"the symbol moved ({dx},{dy}) px inside its frame"
    return f


def log_frame(key, delta):
    def f(ctx):
        p = ctx.p("windows/host-01.stdout.txt"); t = p.read_text(errors="replace"); m = re.search(rf"{key}=(-?\d+)", t); v = int(m.group(1))
        p.write_text(t.replace(m.group(0), f"{key}={v + delta}")); return f"host log {key} {v} -> {v + delta}"
    return f


def tint_shift(d):
    def f(ctx):
        S(ctx, recolour_where(W(ctx), lambda p: p == TINT, lambda p: (p[0], p[1] + d, p[2]))); return f"every fully covered glyph pixel {TINT} -> {(TINT[0], TINT[1] + d, TINT[2])}"
    return f


def tint_wrong(ctx):
    S(ctx, recolour_where(W(ctx), lambda p: p != WHITE, lambda p: (clip(255 - (255 - p[0]) * 0), clip(p[1] * 0.6), p[2]))); return "glyph tint wrong (green channel scaled to 60 percent)"


def missing(ctx):
    S(ctx, fill(W(ctx), (0, 0, 100, 100), WHITE)); return "a missing element: the symbol is gone"


def smaller(ctx):
    im = W(ctx); g = im.crop((0, 0, 80, 80)).resize((72, 72), Image.LANCZOS); out = fill(im, (0, 0, 84, 84), WHITE); out.paste(g, (4, 4)); S(ctx, out); return "the symbol drawn 10 percent smaller (wrong aspect-fit size)"


def aa_noise(ctx):
    mac = load(ctx.p("mac/run-01.png"))
    S(ctx, recolour_where(W(ctx), lambda p: p != WHITE and p != TINT and I.alpha_of(p, TINT) < 0.45, lambda p: tuple(clip(c + (255 - c) * 0.3) for c in p), (0, 0, 84, 84)))
    return "anti-aliasing pixels below half coverage lightened (glyph shape: reported, never gated)"


def glyph_interior_hole(ctx):
    im = W(ctx); out = im.copy(); out.paste(WHITE, (36, 36, 44, 44)); S(ctx, out); return "an 8x8 px hole punched in the middle of the symbol (inside the ink bbox, shape only)"


def stray(ctx):
    im = W(ctx); im.putpixel((300, 300), (254, 254, 254)); S(ctx, im); return "one pixel outside the frame 1 level off"


B = "img-star"
add(B, "frame-logged-x+1", "catch", log_frame("xPX", 1), "the Image view frame logged 1 px off in x")
add(B, "frame-logged-y+1", "catch", log_frame("yPX", 1), "the Image view frame logged 1 px off in y")
add(B, "frame-logged-width+1", "catch", log_frame("widthPX", 1), "the Image view frame logged 1 px wider")
add(B, "glyph-shift-x+1", "catch", glyph_move(1, 0), "1 px shift of the symbol")
add(B, "glyph-shift-y+1", "catch", glyph_move(0, 1), "1 px shift of the symbol (vertical)")
add(B, "glyph-shift-2pt", "catch", glyph_move(5, 0), "the symbol 2 pt (5 px) off")
add(B, "tint+1", "catch", tint_shift(1), "tint one level off (just beyond: the tint gate has no tolerance)")
add(B, "tint-wrong", "catch", tint_wrong, "wrong tint colour")
add(B, "missing-element", "catch", missing, "a missing element")
add(B, "wrong-size", "catch", smaller, "wrong size: the symbol 10 percent smaller")
add(B, "pixel-outside-frame", "catch", stray, "one pixel outside the frame 1 level off")
add(B, "aa-noise-in-glyph", "near", aa_noise, "glyph anti-aliasing differs (shape reported only): must pass")
add(B, "interior-hole", "near", glyph_interior_hole, "the glyph shape differs inside the frame while bbox and tint hold (decision 3: shape reported only)")
