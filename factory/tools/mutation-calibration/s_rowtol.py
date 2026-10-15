"""Per-row position tolerances (decision G71, F2 and block 28). Every region carries its own firstInkY, baseline, mid-point and firstInkX tolerance. The seeded faults are placed
relative to each row's OWN tolerance, read from its pair.json region at run time, so one blanket value cannot hide a row:

  row-dy-beyond     first ink y moved to |dy| = tolerance + 1 (catch)
  row-dy-at-tol     first ink y moved to |dy| = tolerance (near-miss: must pass)
  row-dx-beyond     first ink x moved to |dx| = tolerance + 1 (catch)
  row-2pt-natural   the row moved 2 pt (5 px) in the direction of its natural Windows offset (catch)
  row-2pt-counter   the row moved 2 pt (5 px) against its natural offset (catch): the first ink y can land inside its tolerance, but a vertical shift moves the baseline too, and the
                    baseline tolerance of these rows is 0. A tolerance per metric is needed; a single first-ink tolerance would pass this fault
"""
from core import M
from mutlib import *
import pair_textcolour_report as TC

MUTATIONS = []
add = lambda gate, *a, **k: MUTATIONS.append(M(gate, *a, **k))
GP = "text-colour"


def W(ctx): return load(ctx.p("windows/native-01.png"))
def S(ctx, im): save(im, ctx.p("windows/native-01.png"))
TOLKEY = {"dy": "firstInkYTolerancePx", "db": "baselineTolerancePx", "dc": "inkCentreYTolerancePx", "dx": "firstInkXTolerancePx"}
BASES_ROWS = (("rowtol-serif", 0), ("rowtol-grid13", 0))


def state(ctx, idx):
    cfg = ctx.cfg["textColourGate"]; reg = cfg["regions"][idx]; bg = cfg.get("background")
    pos = {**cfg.get("position", {}), **reg.get("position", {})}
    cov = float(pos.get("coverage", 0.15)); rect = tuple(reg["rect"])
    pm = TC.position(load(ctx.p("mac/run-01.png")), rect, bg, cov)
    return dict(reg=reg, rect=rect, bg=bg, cov=cov, pm=pm, tol=lambda m: float(pos.get(TOLKEY[m], 0)))


def metric(pw, pm, m):
    dy, db = pw["firstInkY"] - pm["firstInkY"], pw["baselineY"] - pm["baselineY"]
    return {"dy": dy, "db": db, "dc": (dy + db) / 2, "dx": pw["firstInkX"] - pm["firstInkX"]}[m]


def moved(ctx, st, s, axis):
    base_bg = tuple(st["bg"]) if st["bg"] else bg_of(W(ctx))
    dx, dy = (s, 0) if axis == "x" else (0, s)
    im = shift_rect(W(ctx), st["rect"], dx, dy, base_bg)
    return im, TC.position(im, st["rect"], st["bg"], st["cov"])


def seek(idx, m, axis, beyond):
    """the shift that makes |metric| exactly tolerance (+1 when beyond), searched by size from zero"""
    def f(ctx):
        st = state(ctx, idx); target = int(st["tol"](m)) + (1 if beyond else 0)
        for s in sorted(range(-40, 41), key=abs):
            im, pw = moved(ctx, st, s, axis); v = metric(pw, st["pm"], m)
            if abs(v) == target:
                S(ctx, im)
                return f"row '{st['reg']['name']}': moved {s:+d} px on {axis}; {m} {v:+d}, tolerance {st['tol'](m):g}: " + ("one beyond" if beyond else "exactly at")
        raise RuntimeError(f"no shift gives |{m}| = {target}")
    return f


def fixed(idx, pt, axis, m, natural):
    """a 2 pt (5 px) shift: natural=True moves the row in the direction of its own offset (or +5 when the offset is zero), False against it"""
    def f(ctx):
        st = state(ctx, idx)
        _, pw0 = moved(ctx, st, 0, axis); v0 = metric(pw0, st["pm"], m)
        sign = (1 if v0 >= 0 else -1) if natural else (-1 if v0 >= 0 else 1)
        s = sign * 5 * pt
        im, pw = moved(ctx, st, s, axis); v = metric(pw, st["pm"], m)
        S(ctx, im)
        return f"row '{st['reg']['name']}': 2 pt ({s:+d} px) on {axis} {'with' if natural else 'against'} the natural offset {v0:+d}; {m} now {v:+d}, tolerance {st['tol'](m):g}"
    return f


for base, r in BASES_ROWS:
    add(GP, base, f"r{r}-dy-beyond", "catch", seek(r, "dy", "y", True), "first ink y one px beyond the row's own tolerance")
    add(GP, base, f"r{r}-dy-at-tol", "near", seek(r, "dy", "y", False), "first ink y exactly at the row's own tolerance: must pass")
    add(GP, base, f"r{r}-dx-beyond", "catch", seek(r, "dx", "x", True), "first ink x one px beyond the row's own tolerance")
    add(GP, base, f"r{r}-2pt-natural", "catch", fixed(r, 1, "y", "dy", True), "row 2 pt (5 px) further in the direction of its natural offset")
    add(GP, base, f"r{r}-2pt-counter", "catch", fixed(r, 1, "y", "dy", False), "row 2 pt (5 px) against its natural offset: first ink y may land inside its tolerance, but the baseline (tolerance 0 on these rows) moves with it and fails")
