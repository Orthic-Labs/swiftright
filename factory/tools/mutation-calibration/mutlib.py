"""Mutation helpers: pure functions over PIL images and the dump JSON. Nothing here decides a verdict; the gates do."""
import json, math, sys
from collections import Counter
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import pair as pairmod          # edge_band: used only to PICK pixels (in or out of the AA band); the verdict always comes from pair.py --recompare


def load(p):
    return Image.open(p).convert("RGB")


def save(im, p):
    im.save(p, optimize=True)


def bg_of(im):
    return Counter(im.getdata()).most_common(1)[0][0]


def clip(v):
    return max(0, min(255, int(round(v))))


def shift_rect(im, rect, dx, dy, bg=None):
    """Move the content of rect by (dx, dy) inside the image (vacated area becomes bg); content moved past the rect is kept (the rect grows to hold it)."""
    bg = bg or bg_of(im)
    x0, y0, x1, y1 = rect
    crop = im.crop(rect)
    out = im.copy()
    out.paste(bg, rect)
    out.paste(crop, (x0 + dx, y0 + dy))
    return out


def fill(im, rect, colour):
    out = im.copy(); out.paste(colour, rect); return out


def ink_bbox(im, rect, bg, thresh=8):
    crop = im.crop(rect)
    d = ImageChops.difference(crop, Image.new("RGB", crop.size, bg))
    m = ImageChops.lighter(ImageChops.lighter(*d.split()[:2]), d.split()[2]).point(lambda v: 255 if v >= thresh else 0)
    b = m.getbbox()
    return None if b is None else [b[0] + rect[0], b[1] + rect[1], b[2] + rect[0], b[3] + rect[1]]


def add_delta(p, delta):
    return tuple(clip(c + delta) for c in p)


def recolour_where(im, pred, fn, rect=None):
    out = im.copy(); px = out.load()
    x0, y0, x1, y1 = rect or (0, 0) + im.size
    for y in range(y0, y1):
        for x in range(x0, x1):
            p = px[x, y]
            if pred(p):
                px[x, y] = fn(p)
    return out


def band_pixels(mac, in_band, region=None, avoid=None):
    """Coordinates of the Mac image that are inside (in_band=True) or outside the 1 px AA band of the factory edge gate (pair.edge_band), optionally in region."""
    band = pairmod.edge_band(mac).load()
    x0, y0, x1, y1 = region or (0, 0) + mac.size
    return [(x, y) for y in range(y0, y1) for x in range(x0, x1) if (band[x, y] != 0) == in_band]


def set_diff_vs_mac(win, mac, xy, delta):
    """Make the Windows pixel differ from the Mac pixel by exactly `delta` levels in every channel where that fits (the sign is chosen to avoid clipping)."""
    out = win.copy(); m = mac.getpixel(xy)
    sign = 1 if max(m) + delta <= 255 else -1
    out.putpixel(xy, tuple(clip(c + sign * delta) for c in m))
    return out


def mid_band_pixel(mac, in_band, region=None, pick=0.5):
    """A pixel in/out of the band whose neighbourhood is stable enough to take a single-pixel level change without clipping (a mid-grey or flat colour)."""
    pts = band_pixels(mac, in_band, region)
    if in_band:   # prefer a partially covered pixel (neither pure background nor pure fill)
        bg = bg_of(mac)
        pts = [p for p in pts if mac.getpixel(p) != bg] or pts
    return pts[int(len(pts) * pick)]


def render_rrect_stroke(size, rect, radius, width, ss=8):
    """Coverage (0..1 float rows) of a circular-corner rounded-rect stroke of `width` centred on the path rect/radius, supersampled ss x."""
    W, H = size
    big = Image.new("L", (W * ss, H * ss), 0)
    d = ImageDraw.Draw(big)
    x0, y0, x1, y1 = [v * ss for v in rect]
    h = width * ss / 2
    d.rounded_rectangle([x0 - h, y0 - h, x1 + h - 1, y1 + h - 1], radius=(radius + width / 2) * ss, fill=255)
    d.rounded_rectangle([x0 + h, y0 + h, x1 - h - 1, y1 - h - 1], radius=max(0, radius - width / 2) * ss, fill=0)
    return big.resize((W, H), Image.BOX)


def apply_cov_delta(im, colour, bg, cov_a, cov_b):
    """im + (colour - bg) * (cov_b - cov_a) per channel: moves a shape from rendering a to rendering b while leaving every other pixel untouched."""
    out = im.copy(); px = out.load(); a, b = cov_a.load(), cov_b.load()
    for y in range(im.height):
        for x in range(im.width):
            dv = (b[x, y] - a[x, y]) / 255.0
            if dv:
                px[x, y] = tuple(clip(px[x, y][i] + (colour[i] - bg[i]) * dv) for i in range(3))
    return out


# ---- JSON dumps (UIA: windows/uia-NN*.json, Mac AX: mac/ax-NN*.json) ----
def jload(p):
    return json.loads(Path(p).read_text(encoding="utf-8-sig"))


def jsave(d, p):
    Path(p).write_text(json.dumps(d))


def walk(node, fn, depth=0, parent=None):
    """pre-order; fn(node, parent, depth); returns the first truthy fn result"""
    r = fn(node, parent, depth)
    if r:
        return r
    for c in node.get("children") or []:
        r = walk(c, fn, depth + 1, node)
        if r:
            return r
    return None


def windows_of(doc, main=True):
    return [w for w in doc.get("windows", []) if bool(w.get("main")) == main]


def find(doc, role=None, name=None, main=True, nth=0):
    """(node, parent) of the nth UIA node of that role/name in the main window (or the extra windows when main=False)."""
    hits = []
    for w in windows_of(doc, main):
        def f(n, par, dep):
            if (role is None or n.get("role") == role) and (name is None or n.get("name") == name):
                hits.append((n, par))
        walk(w["tree"], f)
    return hits[nth]
