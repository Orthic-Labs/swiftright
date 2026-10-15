"""Offline resampling model for wave 1 block I2: the candidate filters of docs/foundations-images-fonts.md 1.4 (box, triangle, Catmull-Rom, Mitchell, Lanczos-3), each in
premultiplied gamma-encoded space and in premultiplied linear-light space, separable, with the kernel widened by the scale on a reduction. Needs numpy (offline fit only: the
gate itself, pair_resample_report.py, needs only Pillow). The product's Swift filters (ImageResampler.swift) implement the same weights; the Swift unit test checks them against
vectors this module produced (tests/vectors written by i2fit.py --emit-vectors)."""
import functools
import math
import numpy as np

KERNELS = ["box", "triangle", "catmull-rom", "mitchell", "lanczos3"]
EXTRA_KERNELS = ["bspline", "lanczos2", "gaussian"]   # not in the design list; tried so that a poor fit is not hidden by a short list (recorded as extras)
SPACES = ["gamma", "linear"]


def _cubic(B, C):
    def k(x):
        x = np.abs(x)
        r = np.zeros_like(x)
        a = x < 1
        b = (x >= 1) & (x < 2)
        r[a] = ((12 - 9 * B - 6 * C) * x[a] ** 3 + (-18 + 12 * B + 6 * C) * x[a] ** 2 + (6 - 2 * B)) / 6
        r[b] = ((-B - 6 * C) * x[b] ** 3 + (6 * B + 30 * C) * x[b] ** 2 + (-12 * B - 48 * C) * x[b] + (8 * B + 24 * C)) / 6
        return r
    return k


def _lanczos(x):
    x = np.abs(x)
    r = np.where(x < 1e-9, 1.0, np.sin(np.pi * x) * np.sin(np.pi * x / 3) / (np.pi ** 2 * x ** 2 / 3 + 1e-30))
    return np.where(x < 3, r, 0.0)


def _lanczos2(x):
    x = np.abs(x)
    r = np.where(x < 1e-9, 1.0, np.sin(np.pi * x) * np.sin(np.pi * x / 2) / (np.pi ** 2 * x ** 2 / 2 + 1e-30))
    return np.where(x < 2, r, 0.0)


SUPPORT = {"triangle": 1.0, "catmull-rom": 2.0, "mitchell": 2.0, "lanczos3": 3.0, "bspline": 2.0, "lanczos2": 2.0, "gaussian": 3.0}
FN = {"bspline": _cubic(1, 0), "lanczos2": _lanczos2, "gaussian": lambda x: np.exp(-2 * x * x), "triangle": lambda x: np.maximum(0, 1 - np.abs(x)), "catmull-rom": _cubic(0, 0.5), "mitchell": _cubic(1 / 3, 1 / 3), "lanczos3": _lanczos}


@functools.lru_cache(maxsize=None)
def weights(n_src, n_dst, kernel, shift=0.0, frame=None):
    """(n_dst, n_src) row-stochastic matrix. Destination pixel t covers source [t*s, (t+1)*s]; its centre maps to c = (t+0.5)*s + shift (source units, pixel i centred at i+0.5).
    `box` is exact area coverage (a box of width max(1, s)); the other kernels are evaluated at (i + 0.5 - c) / max(1, s) and renormalised over the in-range taps."""
    fixed = kernel.endswith("@1")                       # "<kernel>@1": the kernel is NOT widened on a reduction (point-sampled, aliasing)
    kernel = kernel[:-2] if fixed else kernel
    s = n_src / (n_dst if frame is None else frame)    # frame: the UNSNAPPED destination size; n_dst: the snapped rect's size (the output has n_dst pixels)
    f = 1.0 if fixed else max(1.0, s)
    W = np.zeros((n_dst, n_src))
    for t in range(n_dst):
        c = (t + 0.5) * s + shift
        if kernel == "box" and f <= 1.0:          # enlargement: a box of one source pixel is nearest-neighbour
            W[t, min(n_src - 1, max(0, int(math.floor(c))))] = 1
        elif kernel == "box":
            lo, hi = c - f / 2, c + f / 2
            for i in range(max(0, int(math.floor(lo))), min(n_src, int(math.ceil(hi)))):
                W[t, i] = max(0.0, min(hi, i + 1) - max(lo, i))
        else:
            sup = SUPPORT[kernel] * f
            i0, i1 = int(math.floor(c - sup)), int(math.ceil(c + sup))
            idx = np.arange(max(0, i0), min(n_src, i1 + 1))
            W[t, idx] = FN[kernel]((idx + 0.5 - c) / f)
        tot = W[t].sum()
        W[t] = W[t] / tot if abs(tot) > 1e-12 else W[t]
    return W


def srgb_to_lin(v):
    return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(v):
    v = np.clip(v, 0, 1)
    return np.where(v <= 0.0031308, v * 12.92, 1.055 * v ** (1 / 2.4) - 0.055)


def resample(rgba, w, h, kernel, space="gamma", straight=False, shift=(0.0, 0.0), frame=None):
    """rgba: (H, W, 4) uint8 straight alpha. Returns (h, w, 4) float straight alpha in 0..255 (unrounded). straight=True is the NEGATIVE control (no premultiplication)."""
    H, Wd = rgba.shape[:2]
    a = rgba[..., 3:4] / 255.0
    c = rgba[..., :3] / 255.0
    if space == "linear": c = srgb_to_lin(c)
    p = c if straight else c * a
    fw, fh = frame if frame else (None, None)
    wx, wy = weights(Wd, w, kernel, shift[0], fw), weights(H, h, kernel, shift[1], fh)
    def sep(x):
        return np.einsum("uy,ytc->utc", wy, np.einsum("tx,yxc->ytc", wx, x))
    pp = sep(p); aa = sep(a)
    if straight:
        c_out = pp
    else:
        c_out = np.where(aa > 1e-6, pp / np.maximum(aa, 1e-6), 0.0)
    if space == "linear": c_out = lin_to_srgb(c_out)
    out = np.concatenate([np.clip(c_out, 0, 1) * 255.0, np.clip(aa, 0, 1) * 255.0], axis=2)
    return out


def composite(rgba_f, ground=128.0):
    """Straight-alpha float RGBA (0..255) over a uniform ground in gamma space, rounded to 8 bit."""
    a = rgba_f[..., 3:4] / 255.0
    return np.floor(rgba_f[..., :3] * a + ground * (1 - a) + 0.5)


def nearest(rgba, w, h, frame=None):
    """Nearest neighbour as measured on the Mac (ImageRenderer): source index = floor(c) with c = (t + 0.5) * src / frame (cells where c lands exactly on an integer, a tie, are excluded from fits and gates: the Mac decides them by float noise)."""
    H, Wd = rgba.shape[:2]
    fw, fh = frame if frame else (w, h)
    xs = np.clip(np.floor((np.arange(w) + 0.5) * Wd / fw).astype(int), 0, Wd - 1)
    ys = np.clip(np.floor((np.arange(h) + 0.5) * H / fh).astype(int), 0, H - 1)
    return rgba[ys][:, xs].astype(float)


def halve(rgba, odd="floor"):
    """One mip level: 2 x 2 box average of premultiplied gamma values, straight 8-bit output (rounded). odd='floor' drops the last odd row/column; 'ceil' keeps it as a 1 x 2 / 2 x 1 / 1 x 1 box."""
    H, Wd = rgba.shape[:2]
    nh, nw = (H // 2, Wd // 2) if odd == "floor" else ((H + 1) // 2, (Wd + 1) // 2)
    a = rgba[..., 3:4] / 255.0
    p = np.concatenate([rgba[..., :3] / 255.0 * a, a], axis=2)
    out = np.zeros((nh, nw, 4))
    cnt = np.zeros((nh, nw, 1))
    for dy in (0, 1):
        for dx in (0, 1):
            ys = np.arange(nh) * 2 + dy
            xs = np.arange(nw) * 2 + dx
            vy, vx = ys < H, xs < Wd
            sub = np.zeros((nh, nw, 4)); ok = np.zeros((nh, nw, 1))
            sub[np.ix_(vy, vx)] = p[np.ix_(ys[vy], xs[vx])]
            ok[np.ix_(vy, vx)] = 1
            out += sub; cnt += ok
    out = out / np.maximum(cnt, 1)
    al = out[..., 3:4]
    col = np.where(al > 1e-6, out[..., :3] / np.maximum(al, 1e-6), 0.0)
    res = np.concatenate([col * 255.0, al * 255.0], axis=2)
    return np.clip(np.floor(res + 0.5), 0, 255).astype(np.uint8)


def resample_mip(rgba, w, h, kernel, space="gamma", frame=None, odd="floor"):
    """The measured Mac structure for medium and high: while the reduction is MORE than 2:1 (exactly 2:1 is sampled directly: measured), halve the image (2 x 2 box); then sample with the point-sampled kernel
    (`<kernel>@1`, not widened) at c = (t + 0.5) * mip_size / frame. Axes are halved together while BOTH reductions are >= 2 (measured only on uniform scales)."""
    fw, fh = frame if frame else (w, h)
    img = rgba
    while img.shape[1] / fw > 2 and img.shape[0] / fh > 2 and img.shape[0] >= 2 and img.shape[1] >= 2:
        img = halve(img, odd)
    return resample(img, w, h, kernel if kernel.endswith("@1") else kernel + "@1", space, frame=frame)


def register_cubic(name, B, C):
    FN[name] = _cubic(B, C); SUPPORT[name] = 2.0; weights.cache_clear()
