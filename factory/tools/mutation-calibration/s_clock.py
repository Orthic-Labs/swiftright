"""Clock gate (F1 manual clock, decisions C1-C2): pair_clock_report.py: per (run, frame) coverage-integrated extent within extentTolerancePx, exact pixels outside the
strips around tracked edges, and progress (Mac wrapper log vs the runtime's HOST_GEOMETRY) within progressTolerance. Mutations edit the Windows frames and host log."""
import json, math, re, shutil
from core import M
from mutlib import *
import pair_clock_report as K

MUTATIONS = []
add = lambda *a, **k: MUTATIONS.append(M("clock", *a, **k))
WHITE = (255, 255, 255)


def WF(ctx, k): return ctx.p(f"windows/native-01-f{k:02d}.png")
def MF(ctx, k): return ctx.p(f"mac/run-01-f{k:02d}.png")
def LOG(ctx, k): return ctx.p(f"windows/host-01-f{k:02d}.stdout.txt")


def run_of(ctx, k, track=0, who="win"):
    tr = ctx.cfg["clockGate"]["tracks"][track]
    return K.coverage_run(load(WF(ctx, k) if who == "win" else MF(ctx, k)), tr["axis"], tr["line"], tr["colour"])


def swap_frames(k1, k2, logs=True):
    def f(ctx):
        a, b = WF(ctx, k1), WF(ctx, k2); t = a.read_bytes(); a.write_bytes(b.read_bytes()); b.write_bytes(t)
        if logs:
            a, b = LOG(ctx, k1), LOG(ctx, k2); t = a.read_text(errors="replace"); a.write_text(b.read_text(errors="replace")); b.write_text(t)
        return f"Windows frames {k1} and {k2} swapped (out of sequence), " + ("host logs too" if logs else "host logs untouched")
    return f


def extent_edit(k, track, target_abs, sign=1):
    """resize the bar's right edge on every full row of the Windows frame so that (Windows extent - Mac extent) = sign * target_abs"""
    def f(ctx):
        tr = ctx.cfg["clockGate"]["tracks"][track]; assert tr["axis"] == "x"
        im = load(WF(ctx, k)); px = im.load(); colour = tuple(tr["colour"])
        wr, mr = run_of(ctx, k, track, "win"), run_of(ctx, k, track, "mac"); d0 = wr["extent"] - mr["extent"]; delta = sign * target_abs - d0
        ch = max(range(3), key=lambda c: 255 - colour[c]); span = 255 - colour[ch]
        mid = (wr["first"] + wr["last"]) // 2
        rows = [y for y in range(im.height) if px[mid, y] == colour]
        for y in rows:
            cov = [(255 - px[x, y][ch]) / span for x in range(im.width)]
            idx = [i for i, c in enumerate(cov) if c > 0.02]; a, b = idx[0], idx[-1]; e = b + min(1.0, cov[b]); ne = e + delta
            for x in range(int(math.floor(min(e, ne))) - 1, int(math.ceil(max(e, ne))) + 2):
                c = max(0.0, min(1.0, ne - x)); px[x, y] = tuple(clip(255 * (1 - c) + colour[i] * c) for i in range(3))
        save(im, WF(ctx, k)); n = run_of(ctx, k, track, "win")
        return f"frame {k} track {track}: right edge moved {delta:+.2f} px on {len(rows)} rows; extent delta vs Mac {d0:+.3f} -> {n['extent'] - mr['extent']:+.3f} px (tolerance {ctx.cfg['clockGate'].get('extentTolerancePx', 1.0)})"
    return f


def tol_of(ctx): return ctx.cfg["clockGate"].get("extentTolerancePx", 1.0)


def extent_rel(k, track, beyond, sign=1):
    def f(ctx):
        t = tol_of(ctx) + (0.15 if beyond else -0.08)
        return extent_edit(k, track, t, sign)(ctx)
    return f


def mac_progress(ctx, k, leaf):
    log = (ctx.p("mac-run-01.log")).read_text(errors="replace")
    m = re.search(rf"MAC_FRAME index={k} (.*)", log); mv = re.search(r"value=\[([^\]]*)\] result=\[([^\]]*)\] ended=(\w+)", m.group(1))
    v = [float(x) for x in mv.group(1).split(",") if x.strip()]; r = [float(x) for x in mv.group(2).split(",") if x.strip()]
    return 1.0 if mv.group(3) == "true" else (r[leaf] / v[leaf] if r and leaf < len(v) and v[leaf] else None)


def progress_edit(k, track, target_abs, sign=1):
    """set the runtime's presented frame in HOST_GEOMETRY so that (windows progress - Mac progress) = sign * target_abs"""
    def f(ctx):
        tr = ctx.cfg["clockGate"]["tracks"][track]; p = LOG(ctx, k); t = p.read_text(errors="replace")
        m = re.search(r"HOST_GEOMETRY (\{.*\})", t); g = json.loads(m.group(1)); nodes = [n for n in g["nodes"] if n["kind"] == tr["kind"]]; node = nodes[tr.get("index", 0)]
        macp = mac_progress(ctx, k, tr.get("leaf", 2)); old = (node["w"] - tr["from"]) / (tr["to"] - tr["from"])
        node["w"] = tr["from"] + (macp + sign * target_abs) * (tr["to"] - tr["from"])
        p.write_text(t.replace(m.group(1), json.dumps(g, separators=(",", ":"))))
        return f"frame {k}: runtime progress {old:.5f} -> {macp + sign * target_abs:.5f} (Mac {macp:.5f}; delta {sign * target_abs:+.4f}, tolerance {ctx.cfg['clockGate'].get('progressTolerance', 0.004)})"
    return f


def progress_rel(k, track, beyond):
    def f(ctx):
        t = ctx.cfg["clockGate"].get("progressTolerance", 0.004) + (0.0006 if beyond else -0.0004)
        return progress_edit(k, track, t)(ctx)
    return f


def missing_bar(k, track=0):
    def f(ctx):
        tr = ctx.cfg["clockGate"]["tracks"][track]; im = load(WF(ctx, k)); recolour = recolour_where(im, lambda p: p == tuple(tr["colour"]), lambda p: WHITE); save(recolour, WF(ctx, k)); return f"frame {k}: the tracked bar removed (a missing element)"
    return f


def stray_pixel(k):
    def f(ctx):
        im = load(WF(ctx, k)); im.putpixel((700, 520), (254, 254, 254)); save(im, WF(ctx, k)); return f"frame {k}: one background pixel far from the bar 1 level off"
    return f


def translate_bar(k, track, dx, dy=0):
    def f(ctx):
        tr = ctx.cfg["clockGate"]["tracks"][track]; im = load(WF(ctx, k)); colour = tuple(tr["colour"])
        out = recolour_where(im, lambda p: p == colour, lambda p: WHITE); src = im.load(); dst = out.load()
        for y in range(im.height):
            for x in range(im.width):
                if src[x, y] == colour and 0 <= x + dx < im.width and 0 <= y + dy < im.height: dst[x + dx, y + dy] = colour
        # partial-coverage (edge) pixels follow the bar
        for y in range(im.height):
            for x in range(im.width):
                p = src[x, y]
                if p != WHITE and p != colour and 0 <= x + dx < im.width and 0 <= y + dy < im.height: dst[x + dx, y + dy] = p
        save(out, WF(ctx, k)); return f"frame {k}: the whole bar translated ({dx},{dy}) px (extent unchanged)"
    return f


def drop_frame(k):
    def f(ctx):
        WF(ctx, k).unlink(); return f"Windows capture of frame {k} missing"
    return f


def whole_shift(k, dx, dy):
    def f(ctx):
        im = load(WF(ctx, k)); save(shift_rect(im, (0, 0) + im.size, dx, dy, WHITE), WF(ctx, k)); return f"frame {k}: whole frame moved ({dx},{dy}) px"
    return f


# clk-linear: width 100 -> 200 pt linear over 1 s, extent tolerance 1 px, progress 0.004; frame 2 = t 0.5 (fractional edge)
B = "clk-linear"
add(B, "frame-out-of-sequence", "catch", swap_frames(1, 2), "a frame out of sequence (frames 1 and 2 swapped, logs too)")
add(B, "frame-out-of-sequence-images", "catch", swap_frames(2, 3, logs=False), "a frame out of sequence (pictures only; host log says the right time)")
add(B, "extent+beyond", "catch", extent_rel(2, 0, True, +1), "extent 0.15 px beyond the C2 tolerance (1 px), wider")
add(B, "extent-beyond", "catch", extent_rel(2, 0, True, -1), "extent 0.15 px beyond the C2 tolerance, narrower")
add(B, "extent+near", "near", extent_rel(2, 0, False, +1), "extent 0.08 px inside the C2 tolerance: must pass")
add(B, "extent-near", "near", extent_rel(2, 0, False, -1), "extent 0.08 px inside the tolerance, narrower: must pass")
add(B, "extent+1.5px", "catch", extent_edit(2, 0, 1.5), "extent 1.5 px wider")
add(B, "extent+5px", "catch", extent_edit(2, 0, 5.0), "extent 5 px (2 pt) wider")
add(B, "timing-progress-beyond", "catch", progress_rel(2, 0, True), "wrong timing: runtime progress 0.0006 beyond progressTolerance 0.004 (images untouched)")
add(B, "timing-progress-near", "near", progress_rel(2, 0, False), "runtime progress 0.0004 inside progressTolerance: must pass")
add(B, "timing-progress-0.05", "catch", progress_edit(2, 0, 0.05), "wrong timing: runtime 5 percent ahead")
add(B, "timing-progress-neg", "catch", progress_edit(3, 0, 0.02, -1), "wrong timing: runtime 2 percent behind")
add(B, "missing-element", "catch", missing_bar(2), "a missing element: the bar is not drawn")
add(B, "stray-pixel", "catch", stray_pixel(2), "one background pixel 1 level off outside the strips")
add(B, "whole-frame-shift-x-1px", "near", whole_shift(2, 1, 0), "the whole frame 1 px off in x (a 1 px edge translation is inside the C2 snap: must pass)")
add(B, "whole-frame-shift-y-1px", "catch", whole_shift(2, 0, 1), "the whole frame 1 px off in y")
add(B, "bar-translate-y-1px", "catch", translate_bar(2, 0, 0, 1), "the bar 1 px too low")
add(B, "bar-translate-x-2", "catch", translate_bar(2, 0, 2), "the bar 2 px right (left edge moves, width the same)")
add(B, "bar-translate-x-5", "catch", translate_bar(2, 0, 5), "the bar 2 pt (5 px) right")
add(B, "frame-missing", "catch", drop_frame(2), "a missing capture")
# clk-spring: the named 2 px extent tolerance (decision C4), progress 0.005
B = "clk-spring"
add(B, "extent+beyond", "catch", extent_rel(3, 0, True, +1), "extent 0.15 px beyond the named 2 px spring tolerance")
add(B, "extent-beyond", "catch", extent_rel(3, 0, True, -1), "extent 0.15 px beyond the 2 px tolerance, narrower")
add(B, "extent+near", "near", extent_rel(3, 0, False, +1), "extent 0.08 px inside the 2 px tolerance: must pass")
add(B, "extent-near", "near", extent_rel(3, 0, False, -1), "extent 0.08 px inside the 2 px tolerance, narrower: must pass")
add(B, "extent-1.2px-passes", "near", extent_edit(3, 0, 1.2), "extent 1.2 px (beyond a 1 px gate, inside the spring's 2 px)")
add(B, "frame-out-of-sequence", "catch", swap_frames(2, 3), "a frame out of sequence")
add(B, "timing-progress-beyond", "catch", progress_rel(3, 0, True), "runtime progress just beyond progressTolerance 0.005")
add(B, "timing-progress-near", "near", progress_rel(3, 0, False), "runtime progress just inside progressTolerance: must pass")
add(B, "missing-element", "catch", missing_bar(3), "a missing element")
# clk-move: opacity-transition move(edge: .leading); one tracked bar, no progress block
B = "clk-move"
add(B, "frame-out-of-sequence", "catch", swap_frames(1, 2), "a frame out of sequence")
add(B, "extent+beyond", "catch", extent_rel(2, 0, True, +1), "extent just beyond the 1 px tolerance")
add(B, "extent+near", "near", extent_rel(2, 0, False, +1), "extent just inside the tolerance: must pass")
add(B, "translate-x-1px", "near", translate_bar(2, 0, 1), "the moving bar 1 px off in x (inside the C2 snap)")
add(B, "translate-x-2px", "catch", translate_bar(2, 0, 2), "the moving bar 2 px off in x")
add(B, "translate-x-3px", "catch", translate_bar(2, 0, 3), "the moving bar 3 px off in x")
add(B, "translate-x-5px", "catch", translate_bar(2, 0, 5), "the moving bar 2 pt (5 px) off in x")
add(B, "translate-y-1px", "catch", translate_bar(2, 0, 0, 1), "the moving bar 1 px too low")
add(B, "missing-element", "catch", missing_bar(2), "a missing element")
# clk-fade: insertion fade, no tracks: every pixel exact
B = "clk-fade"
add(B, "frame-out-of-sequence", "catch", swap_frames(1, 2, logs=False), "a frame out of sequence")
add(B, "opacity-1-level", "catch", lambda ctx: (lambda im: (save(recolour_where(im, lambda p: p != WHITE, lambda p: add_delta(p, 1)), WF(ctx, 2)), "frame 2: every non-white pixel 1 level off (opacity error)")[1])(load(WF(ctx, 2))), "opacity 1 level off")
add(B, "missing-element", "catch", lambda ctx: (lambda im: (save(fill(im, (0, 0) + im.size, WHITE), WF(ctx, 2)), "frame 2: blank")[1])(load(WF(ctx, 2))), "a missing element")
add(B, "shift-1px", "catch", whole_shift(2, 1, 0), "1 px shift")
