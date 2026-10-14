"""Pixel gate: pair.py compare() / edge_gate() (exact, edge-aa<=32, hazeTolerance, named exclusions, the half-pixel tie cases). Mutations edit the Windows capture."""
from core import M
from mutlib import *

G = "pixel"


def W(ctx):
    return load(ctx.p("windows/native-01.png"))


def S(ctx, im):
    save(im, ctx.p("windows/native-01.png"))


def Mac(ctx):
    return load(ctx.p("mac/run-01.png"))


def content_rect(im, margin=8):
    b = ink_bbox(im, (0, 0) + im.size, bg_of(im), 1)
    return (max(0, b[0] - margin), max(0, b[1] - margin), min(im.width, b[2] + margin), min(im.height, b[3] + margin))


def layer_shift(im, colour, dx, dy):
    """move every pixel of exactly `colour` by (dx, dy); vacated pixels take the background"""
    bg = bg_of(im); out = im.copy(); src = im.load(); dst = out.load(); moved = []
    for y in range(im.height):
        for x in range(im.width):
            if src[x, y] == colour:
                dst[x, y] = bg; moved.append((x, y))
    for x, y in moved:
        if 0 <= x + dx < im.width and 0 <= y + dy < im.height:
            dst[x + dx, y + dy] = colour
    return out


def first_blob(im, colour):
    """bbox of the top-left-most solid rectangle of `colour` (rows scanned top to bottom): grows right and down while the colour holds"""
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            if px[x, y] == colour:
                x1 = x
                while x1 < im.width and px[x1, y] == colour: x1 += 1
                y1 = y
                while y1 < im.height and px[x, y1] == colour: y1 += 1
                return (x, y, x1, y1)


def mut_shift_all(dx, dy):
    def f(ctx):
        im = W(ctx); S(ctx, shift_rect(im, content_rect(im), dx, dy)); return f"whole content moved ({dx},{dy}) px"
    return f


def mut_layer(colour, dx, dy, what):
    def f(ctx):
        S(ctx, layer_shift(W(ctx), colour, dx, dy)); return f"{what} moved ({dx},{dy}) px"
    return f


def mut_colour_layer(colour, delta, what):
    def f(ctx):
        S(ctx, recolour_where(W(ctx), lambda p: p == colour, lambda p: add_delta(p, delta))); return f"{what}: colour {colour} {delta:+d} level in every channel"
    return f


def mut_remove_blob(colour):
    def f(ctx):
        im = W(ctx); b = first_blob(im, colour); S(ctx, fill(im, b, bg_of(im))); return f"first {colour} rectangle {b} painted background"
    return f


def mut_narrow_blob(colour):
    def f(ctx):
        im = W(ctx); b = first_blob(im, colour); S(ctx, fill(im, (b[2] - 1, b[1], b[2], b[3]), bg_of(im))); return f"first {colour} rectangle {b} one pixel narrower"
    return f


def mut_round_blob(colour, r):
    def f(ctx):
        im = W(ctx); b = first_blob(im, colour); bg = bg_of(im); px = im.load()
        for cx, cy, sx, sy in ((b[0], b[1], 1, 1), (b[2] - 1, b[1], -1, 1), (b[0], b[3] - 1, 1, -1), (b[2] - 1, b[3] - 1, -1, -1)):
            for j in range(r):
                for i in range(r):
                    x, y = cx + sx * i, cy + sy * j
                    if math.hypot(r - 0.5 - i, r - 0.5 - j) > r:
                        px[x, y] = bg
        S(ctx, im); return f"first {colour} rectangle {b}: four corners rounded to a {r}-px radius (it had square corners)"
    return f


def mut_band(delta, in_band, region=None):
    def f(ctx):
        mac, win = Mac(ctx), W(ctx)
        xy = mid_band_pixel(mac, in_band, region)
        S(ctx, set_diff_vs_mac(win, mac, xy, delta))
        return f"one {'in-band (AA edge)' if in_band else 'out-of-band (flat)'} pixel {xy} set {delta} levels from the Mac pixel {mac.getpixel(xy)}"
    return f


def mut_rrect(radius_px=None, width_px=None):
    # Witness: RoundedRectangle(cornerRadius: 6).stroke(lineWidth: 2) in a 40x20 pt frame at scale 2.5: path rect (350,275)-(450,325), radius 15 px, stroke 5 px
    def f(ctx):
        im = W(ctx); size = im.size; rect = (350, 275, 450, 325); r0, w0 = 15.0, 5.0
        a = render_rrect_stroke(size, rect, r0, w0)
        b = render_rrect_stroke(size, rect, r0 if radius_px is None else r0 + radius_px, w0 if width_px is None else w0 + width_px)
        S(ctx, apply_cov_delta(im, (0, 136, 255), (255, 255, 255), a, b))
        return ("corner radius %+g px" % radius_px if radius_px is not None else "stroke width %+g px" % width_px) + " (6 pt radius = 15 px, 2 pt stroke = 5 px)"
    return f


def mut_no_haze(ctx):
    ctx.cfg.pop("hazeTolerance", None); ctx.save_cfg()
    mut_band(3, False)(ctx); return "case config without hazeTolerance; one out-of-band pixel 3 levels off"


def mut_excl_glyph(name_part):
    def f(ctx):
        r = [e for e in ctx.cfg["excludeRects"]][0]["rect"]
        im = W(ctx); S(ctx, fill(im, tuple(r), bg_of(im))); return f"all ink inside the named exclusion rect {r} removed"
    return f


def mut_excl_shift(dx, dy):
    def f(ctx):
        r = ctx.cfg["excludeRects"][0]["rect"]
        im = W(ctx); r = tuple(r); bg = bg_of(im)
        inner = Image.new("RGB", (r[2] - r[0], r[3] - r[1]), bg); inner.paste(im.crop(r), (dx, dy))   # clipped to the rect: nothing leaves it
        out = im.copy(); out.paste(inner, r[:2]); S(ctx, out); return f"ink inside the named exclusion rect {list(r)} moved ({dx},{dy}) px, clipped to the rect"
    return f


def mut_outside_excl(ctx):
    r = ctx.cfg["excludeRects"][0]["rect"]
    im = W(ctx); mac = Mac(ctx)
    d = ImageChops.difference(im, mac)
    # an element outside every exclusion: shift the content outside the rect by 1 px (everything except the rect)
    keep = im.crop(tuple(r)); out = shift_rect(im, content_rect(im), 1, 0); out.paste(keep, tuple(r)); S(ctx, out)
    return "all ink outside the exclusion rect moved 1 px right"


def mut_rrect_probe(radius_px=None, width_px=None):
    return mut_rrect(radius_px, width_px)


MUTATIONS = []
add = lambda *a, **k: MUTATIONS.append(M(G, *a, **k))
BLUE, RED, GREEN = (0, 136, 255), (255, 56, 60), (52, 199, 89)

# px-exact: frame-alignment-v1 (flat blue/red rectangles, exact on all runs)
add("px-exact", "shift-1px", "catch", mut_shift_all(1, 0), "1 px shift of the whole picture")
add("px-exact", "shift-element-1px", "catch", mut_layer(RED, 0, 1, "red layer"), "1 px shift of one element layer")
add("px-exact", "colour+1", "catch", mut_colour_layer(BLUE, 1, "blue layer"), "colour shift of one level (the gate has no tolerance here)")
add("px-exact", "missing-element", "catch", mut_remove_blob(BLUE), "a missing element")
add("px-exact", "size-1px", "catch", mut_narrow_blob(BLUE), "an element one pixel narrower")
add("px-exact", "corner-radius", "catch", mut_round_blob(BLUE, 6), "a wrong corner radius on a rectangle")
# px-ties: layout-v1 (half-pixel tie rule 3353d63f; exact on all runs)
add("px-ties", "tie-shift-1px", "catch", mut_layer(GREEN, 1, 0, "green layer"), "a tie resolved the other way: one element one pixel off")
add("px-ties", "tie-shift-1px-red", "catch", mut_layer(RED, 0, 1, "red layer"), "a tie resolved the other way, vertical")
add("px-ties", "missing-element", "catch", mut_remove_blob(BLUE), "a missing element")
# px-edge: rounded stroke (edge-aa<=32, max 9 on the evidence)
add("px-edge", "shift-1px", "catch", mut_shift_all(1, 0), "1 px shift")
add("px-edge", "radius+10px", "catch", mut_rrect(radius_px=10), "wrong corner radius (4 pt more)")
add("px-edge", "radius-8px", "catch", mut_rrect(radius_px=-8), "wrong corner radius (3 pt less)")
add("px-edge", "stroke+2.5px", "catch", mut_rrect(width_px=2.5), "wrong stroke width (3 pt instead of 2)")
add("px-edge", "stroke-2.5px", "catch", mut_rrect(width_px=-2.5), "wrong stroke width (1 pt instead of 2)")
add("px-edge", "missing-element", "catch", lambda ctx: (S(ctx, fill(W(ctx), (330, 255, 470, 345), (255, 255, 255))), "stroke removed")[1], "a missing element")
add("px-edge", "band+33", "catch", mut_band(33, True), "one AA-edge pixel 33 levels off (beyond edge-aa 32)")
add("px-edge", "band+32", "near", mut_band(32, True), "one AA-edge pixel exactly 32 levels off (edge-aa<=32 must pass)")
add("px-edge", "flat+1", "catch", mut_band(1, False), "one flat pixel 1 level off (out-of-band tolerance is 0 without hazeTolerance)")
for rp in (0.25, 0.5, 1.0, 2.0):
    add("px-edge", f"probe-radius+{rp}px", "probe", mut_rrect(radius_px=rp), f"sensitivity: corner radius +{rp} px")
for wp in (0.25, 0.5, 1.0):
    add("px-edge", f"probe-stroke+{wp}px", "probe", mut_rrect(width_px=wp), f"sensitivity: stroke width +{wp} px")
# px-fractional: nested fractional edges (edge-aa<=32, max 31 on the evidence)
add("px-fractional", "shift-1px", "catch", mut_shift_all(1, 0), "1 px shift")
add("px-fractional", "band+33", "catch", mut_band(33, True), "one AA-edge pixel 33 levels off")
add("px-fractional", "band+32", "near", mut_band(32, True), "one AA-edge pixel exactly 32 levels off")
add("px-fractional", "flat+1", "catch", mut_band(1, False), "one flat pixel 1 level off")
# px-haze: dark switch, hazeTolerance 3 (sr1-decisions D9)
add("px-haze", "haze+4", "catch", mut_band(4, False), "haze level 4 (above the named 3)")
add("px-haze", "haze+3", "near", mut_band(3, False), "haze level exactly 3 (within hazeTolerance 3, must pass)")
add("px-haze", "haze+2", "near", mut_band(2, False), "haze level 2")
add("px-haze", "haze+3-without-tolerance", "catch", mut_no_haze, "level 3 in a case that does not name hazeTolerance")
add("px-haze", "band+33", "catch", mut_band(33, True), "in-band 33 levels (haze does not widen the AA band)")
add("px-haze", "band+32", "near", mut_band(32, True), "in-band exactly 32 levels")
add("px-haze", "shift-1px", "catch", mut_shift_all(1, 0), "1 px shift")
# px-excl: stack-overlay-centered-execution-v9 (named '+' glyph exclusion, decision 2)
add("px-excl", "shift-outside-exclusion-1px", "catch", mut_outside_excl, "1 px shift of everything outside the named glyph region")
add("px-excl", "glyph-removed", "catch", mut_excl_glyph(""), "the '+' glyph removed from the excluded region", design="decision 2: the named glyph region is excluded from the pixel gate (the case has no text/colour gate)")
add("px-excl", "glyph-moved-5px", "catch", mut_excl_shift(5, 0), "the '+' glyph 5 px (2 pt) off inside the excluded region", design="decision 2: the named glyph region is excluded from the pixel gate (the case has no text/colour gate)")
# capture integrity
add("px-exact", "capture-size-799x600", "catch", lambda ctx: (S(ctx, W(ctx).crop((0, 0, 799, 600))), "Windows capture 799x600 instead of 800x600")[1], "a wrong capture size")
add("px-exact", "capture-missing", "catch", lambda ctx: (ctx.p("windows/native-01.png").unlink(), "Windows capture missing")[1], "a missing Windows capture")
