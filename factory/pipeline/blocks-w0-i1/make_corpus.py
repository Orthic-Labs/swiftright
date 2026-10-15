#!/usr/bin/env python3
"""Wave 0 block I1: deterministic image corpus for the decode gate (docs/foundations-images-fonts.md section 4, I1).
usage: make_corpus.py          writes corpus/*.{png,jpg,ico,bmp,gif,bin} and corpus/manifest.json next to this script (small files only; no fonts, no Windows assets).
PNG, ICO, BMP and GIF files are written byte by byte here (struct + zlib); JPEG uses Pillow (the committed bytes are the corpus, regeneration may differ by encoder version).
The ICC profile embedded in the "P3" files is generated here too (a v2 matrix/TRC profile with Display P3 primaries, D50-adapted, and the sRGB curve): no Apple or
Microsoft profile is redistributed."""
import io, json, struct, sys, zlib
from pathlib import Path
from PIL import Image

H = Path(__file__).resolve().parent
OUT = H / "corpus"
OUT.mkdir(exist_ok=True)
manifest = []


def add(case_id, file, kind, data, max_pixel=0, note="", **extra):
    (OUT / file).write_bytes(data)
    manifest.append(dict(id=case_id, file=file, kind=kind, maxPixel=max_pixel, note=note, bytes=len(data), **extra))


# ---------- deterministic pixel source ----------
def lcg(seed):
    s = seed & 0xffffffff
    while True:
        s = (s * 1664525 + 1013904223) & 0xffffffff
        yield s >> 8


def photo(w, h, seed=7):
    """smooth colour field plus small noise: stands in for a photograph (RGB, 8-bit)."""
    g = lcg(seed)
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            r = int(128 + 100 * __import__("math").sin(x / 7.0 + y / 11.0))
            gg = int(128 + 100 * __import__("math").sin(x / 9.0 - y / 5.0 + 1))
            b = int(128 + 100 * __import__("math").cos(x / 13.0 + y / 8.0))
            n = (next(g) & 7) - 3
            row.append(tuple(max(0, min(255, c + n)) for c in (r, gg, b)))
        rows.append(row)
    return rows


def rgba_field(w, h):
    """RGBA test pattern: opaque, fully transparent and partial alpha regions, an alpha ramp, colour edges."""
    rows = []
    for y in range(h):
        row = []
        for x in range(w):
            r = (x * 255) // max(1, w - 1); g = (y * 255) // max(1, h - 1); b = ((x + y) * 255) // max(1, w + h - 2)
            if y < h // 4: a = 255
            elif y < h // 2: a = (x * 255) // max(1, w - 1)          # alpha ramp across the row
            elif y < 3 * h // 4: a = 0 if (x // 4) % 2 == 0 else 255   # transparent / opaque bands
            else: a = (64, 128, 192, 254)[x % 4]
            row.append((r, g, b, a))
        rows.append(row)
    return rows


# ---------- PNG writer ----------
def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else (b if pb <= pc else c)


def filter_rows(rows, bpp):
    """every row gets filter (y mod 5): None, Sub, Up, Average, Paeth cycle, so every decoder path is exercised."""
    out = bytearray(); prev = bytes(len(rows[0]))
    for y, row in enumerate(rows):
        ft = y % 5; out.append(ft)
        for i, v in enumerate(row):
            a = row[i - bpp] if i >= bpp else 0
            b = prev[i]; c = prev[i - bpp] if i >= bpp else 0
            pred = (0, a, b, (a + b) // 2, paeth(a, b, c))[ft]
            out.append((v - pred) & 255)
        prev = bytes(row)
    return bytes(out)


def pack_samples(samples, depth):
    """one row of integer samples -> bytes at the given bit depth (MSB first, rows padded to a byte)"""
    if depth == 8: return bytes(samples)
    if depth == 16: return b"".join(struct.pack(">H", s) for s in samples)
    out = bytearray(); acc = 0; n = 0
    for s in samples:
        acc = (acc << depth) | s; n += depth
        if n == 8: out.append(acc); acc = 0; n = 0
    if n: out.append(acc << (8 - n))
    return bytes(out)


ADAM7 = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]


def png(w, h, depth, ctype, pixels, plte=None, trns=None, interlace=False, extra=(), channels=None):
    """pixels[y][x] is a tuple of integer samples (1 for grey/palette, 2 grey+alpha, 3 RGB, 4 RGBA) already at `depth` bits."""
    nch = len(pixels[0][0])
    bpp = max(1, (nch * depth) // 8)
    ihdr = struct.pack(">IIBBBBB", w, h, depth, ctype, 0, 0, 1 if interlace else 0)
    if not interlace:
        rows = [pack_samples([s for px in pixels[y] for s in px], depth) for y in range(h)]
        raw = filter_rows(rows, bpp)
    else:
        raw = b""
        for (x0, y0, dx, dy) in ADAM7:
            ys = list(range(y0, h, dy)); xs = list(range(x0, w, dx))
            if not ys or not xs: continue
            rows = [pack_samples([s for x in xs for s in pixels[y][x]], depth) for y in ys]
            raw += filter_rows(rows, bpp)
    d = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr)
    for t, body in extra: d += chunk(t, body)
    if plte: d += chunk(b"PLTE", bytes(plte))
    if trns is not None: d += chunk(b"tRNS", bytes(trns))
    return d + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def to_depth(v8, depth):
    """8-bit value -> `depth` bits by exact scaling v * (2^depth-1) / 255 rounded (grey ramps use values that survive the round trip)"""
    return (v8 * ((1 << depth) - 1) + 127) // 255


# ---------- ICC (matrix/TRC, v2) ----------
def s15(v): return struct.pack(">i", int(round(v * 65536)))


def xyz_tag(x, y, z): return b"XYZ \0\0\0\0" + s15(x) + s15(y) + s15(z)


def icc_p3():
    """Display P3 primaries (D50-adapted, Bradford, the values Apple's Display P3 profile carries) with the sRGB transfer curve as a 1024 point table."""
    curve = [(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4) for c in (i / 1023 for i in range(1024))]
    trc = b"curv\0\0\0\0" + struct.pack(">I", 1024) + b"".join(struct.pack(">H", int(round(v * 65535))) for v in curve)
    ascii_ = b"SwiftRight test P3\0"
    desc = b"desc\0\0\0\0" + struct.pack(">I", len(ascii_)) + ascii_ + b"\0" * 8 + b"\0" * 3 + b"\0" * 67
    cprt = b"text\0\0\0\0" + b"Public domain test profile\0"
    tags = [(b"desc", desc), (b"cprt", cprt), (b"wtpt", xyz_tag(0.9642, 1.0, 0.8249)),
            (b"rXYZ", xyz_tag(0.5151, 0.2412, -0.0011)), (b"gXYZ", xyz_tag(0.2920, 0.6922, 0.0419)), (b"bXYZ", xyz_tag(0.1571, 0.0666, 0.7841)),
            (b"rTRC", trc), (b"gTRC", trc), (b"bTRC", trc)]
    # tables share data for the three TRC entries
    body = b""; table = b""; offset = 128 + 4 + 12 * len(tags)
    seen = {}
    for sig, data in tags:
        pad = (-len(data)) % 4
        if data in seen: off = seen[data]
        else:
            off = offset + len(body); seen[data] = off; body += data + b"\0" * pad
        table += sig + struct.pack(">II", off, len(data))
    size = offset + len(body)
    header = struct.pack(">I4sI4s4s4s", size, b"\0\0\0\0", 0x02200000, b"mntr", b"RGB ", b"XYZ ") + b"\x07\xe6\x00\x0a\x00\x0f\x00\x00\x00\x00\x00\x00" + b"acsp" + b"APPL" + b"\0\0\0\0" + b"\0" * 12
    header += struct.pack(">III", 0, 0, 0)  # attributes (2x4), intent
    header = header[:64] + struct.pack(">I", 0) + s15(0.9642) + s15(1.0) + s15(0.8249)
    header = header.ljust(128, b"\0")
    return header + struct.pack(">I", len(tags)) + table + body


ICC_P3 = icc_p3()


# ---------- PNG corpus ----------
def grey_px(w, h, depth):
    return [[(to_depth(((x * 7 + y * 13) * 255 // (w * 7 + h * 13)) & 255, depth) if depth >= 8 else ((x + y) % (1 << depth)),) for x in range(w)] for y in range(h)]


W, Hh = 24, 20
for depth in (1, 2, 4, 8, 16):
    px = grey_px(W, Hh, depth)
    add(f"png-grey{depth}", f"png-grey{depth}.png", "lossless", png(W, Hh, depth, 0, px), note=f"{depth}-bit greyscale, filters cycle 0-4")
for depth in (1, 2, 4, 8):
    n = 1 << depth if depth < 8 else 40
    plte = []
    for i in range(n): plte += [(i * 53 + 17) & 255, (i * 97 + 41) & 255, (i * 29 + 5) & 255]
    trns = [255] * n
    for i, a in enumerate((0, 64, 128, 200)):
        if i < n: trns[i] = a
    px = [[((x * 3 + y * 5) % n,) for x in range(W)] for y in range(Hh)]
    add(f"png-palette{depth}-trns", f"png-palette{depth}-trns.png", "lossless", png(W, Hh, depth, 3, px, plte=plte, trns=trns), note=f"{depth}-bit palette, tRNS alpha 0/64/128/200")
    add(f"png-palette{depth}", f"png-palette{depth}.png", "lossless", png(W, Hh, depth, 3, px, plte=plte), note=f"{depth}-bit palette, opaque")
f = rgba_field(W, Hh)
for depth in (8, 16):
    mul = 1 if depth == 8 else 257
    add(f"png-greyalpha{depth}", f"png-greyalpha{depth}.png", "lossless", png(W, Hh, depth, 4, [[((r + g + b) // 3 * mul, a * mul) for (r, g, b, a) in row] for row in f]), note=f"{depth}-bit grey+alpha")
    add(f"png-rgb{depth}", f"png-rgb{depth}.png", "lossless", png(W, Hh, depth, 2, [[(r * mul, g * mul, b * mul) for (r, g, b, a) in row] for row in f]), note=f"{depth}-bit RGB")
    add(f"png-rgba{depth}", f"png-rgba{depth}.png", "lossless", png(W, Hh, depth, 6, [[(r * mul, g * mul, b * mul, a * mul) for (r, g, b, a) in row] for row in f]), note=f"{depth}-bit RGBA, partial alpha")
# 16-bit samples that are not multiples of 257 (rounding of 16 -> 8 bit): gradient of every 16-bit value pattern
g16 = [[(((x * 2731 + y * 1237) & 0xffff), ((x * 911 + y * 4099 + 300) & 0xffff), ((x * 1777 + y * 31 + 7000) & 0xffff), 65535) for x in range(W)] for y in range(Hh)]
add("png-rgba16-odd", "png-rgba16-odd.png", "lossless", png(W, Hh, 16, 6, g16), note="16-bit RGBA with samples that are not multiples of 257 (16 to 8 bit rounding)")
g16g = [[(((x * 2731 + y * 1237) & 0xffff),) for x in range(W)] for y in range(Hh)]
add("png-grey16-odd", "png-grey16-odd.png", "lossless", png(W, Hh, 16, 0, g16g), note="16-bit grey, samples not multiples of 257")
add("png-grey8-ramp", "png-grey8-ramp.png", "lossless", png(16, 16, 8, 0, [[((y * 16 + x),) for x in range(16)] for y in range(16)]), note="8-bit grey, every value 0..255 once: derives the grey conversion exactly")
add("png-grey16-ramp", "png-grey16-ramp.png", "lossless", png(64, 64, 16, 0, [[((y * 64 + x) * 16 + ((y * 64 + x) * 7) % 16,) for x in range(64)] for y in range(64)]), note="16-bit grey ramp, 4096 values")
add("png-rgb16-ramp", "png-rgb16-ramp.png", "lossless", png(64, 64, 16, 2, [[((y * 64 + x) * 16 + ((y * 64 + x) * 7) % 16, 65535 - (y * 64 + x) * 16, ((y * 64 + x) * 9973) & 0xffff) for x in range(64)] for y in range(64)]), note="16-bit RGB ramps: derives the 16 to 8 bit rounding exactly")
AW, AH = 13, 11
fa = rgba_field(AW, AH)
add("png-rgba8-adam7", "png-rgba8-adam7.png", "lossless", png(AW, AH, 8, 6, [[p for p in row] for row in fa], interlace=True), note="Adam7, RGBA 8-bit, 13x11 so every pass has a partial block")
add("png-rgb8-adam7", "png-rgb8-adam7.png", "lossless", png(AW, AH, 8, 2, [[p[:3] for p in row] for row in fa], interlace=True), note="Adam7, RGB 8-bit")
add("png-grey4-adam7", "png-grey4-adam7.png", "lossless", png(AW, AH, 4, 0, grey_px(AW, AH, 4), interlace=True), note="Adam7, 4-bit grey")
add("png-rgba16-adam7", "png-rgba16-adam7.png", "lossless", png(AW, AH, 16, 6, [[(r * 257, g * 257, b * 257, a * 257) for (r, g, b, a) in row] for row in fa], interlace=True), note="Adam7, RGBA 16-bit")
add("png-rgb8-srgbchunk", "png-rgb8-srgbchunk.png", "lossless", png(W, Hh, 8, 2, [[p[:3] for p in row] for row in f], extra=[(b"sRGB", b"\x00")]), note="RGB with an sRGB chunk")
add("png-rgb8-gama22", "png-rgb8-gama22.png", "colour", png(W, Hh, 8, 2, [[p[:3] for p in row] for row in f], extra=[(b"gAMA", struct.pack(">I", 45455))]), note="RGB with gAMA 1/2.2 and no sRGB chunk: what each platform does with a gamma-tagged PNG is measured, not assumed")
ph = photo(64, 48)
add("png-photo-rgb8", "png-photo-rgb8.png", "lossless", png(64, 48, 8, 2, [[px for px in row] for row in [[(r, g, b) for (r, g, b) in row] for row in ph]]), note="64x48 photo-like RGB, also the maxPixel thumbnail source")
add("png-photo-rgba8", "png-photo-rgba8.png", "lossless", png(64, 48, 8, 6, [[(r, g, b, 255 if (x // 8 + y // 8) % 3 else 128) for x, (r, g, b) in enumerate(row)] for y, row in enumerate(ph)]), note="64x48 RGBA with a half-transparent checker, thumbnail source for premultiplied resampling")
# P3-tagged PNG: iCCP chunk (name, 0, compression 0, zlib profile)
iccp = b"SwiftRight test P3\0\0" + zlib.compress(ICC_P3, 9)
p3px = [[(min(255, x * 11), min(255, y * 12), 200 - (x * 5) % 200) if (x + y) % 5 else (255, 0, 0) for x in range(W)] for y in range(Hh)]
patch = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 0), (0, 255, 255), (255, 0, 255), (200, 50, 50), (50, 200, 50), (50, 50, 200), (230, 120, 30), (30, 120, 230),
         (100, 150, 200), (180, 90, 140), (10, 20, 30), (240, 230, 220), (128, 128, 128), (64, 64, 64), (255, 128, 0), (0, 128, 255), (17, 99, 201), (233, 12, 77), (0, 0, 0), (255, 255, 255), (192, 192, 192)]
p3pat = [[patch[(x // 2) + 12 * (y // 10)] if y < 20 else patch[0] for x in range(24)] for y in range(20)]
add("png-p3-rgb8", "png-p3-rgb8.png", "p3", png(24, 20, 8, 2, p3pat, extra=[(b"iCCP", iccp)]), note="RGB 8-bit tagged with a Display P3 matrix/TRC profile (iCCP); 24 saturated and mid colours")
add("png-p3-rgba8", "png-p3-rgba8.png", "p3", png(W, Hh, 8, 6, [[(*p3px[y][x], 255 if y < 10 else 160) for x in range(W)] for y in range(Hh)], extra=[(b"iCCP", iccp)]), note="RGBA 8-bit P3 with half the rows at alpha 160")
add("png-p3-srgbpixels-untagged", "png-p3-untagged.png", "lossless", png(24, 20, 8, 2, p3pat), note="the same pixels as png-p3-rgb8 without a profile: untagged is sRGB on both platforms (decision 1.2)")


# ---------- JPEG (Pillow) ----------
def jpeg(img, **kw):
    b = io.BytesIO(); img.save(b, "JPEG", **kw); return b.getvalue()


im = Image.new("RGB", (64, 48)); im.putdata([p for row in ph for p in row])
add("jpeg-baseline-420", "jpeg-baseline-420.jpg", "jpeg", jpeg(im, quality=85, subsampling=2), note="baseline, 4:2:0 chroma (the common photo case)")
add("jpeg-baseline-444", "jpeg-baseline-444.jpg", "jpeg", jpeg(im, quality=95, subsampling=0), note="baseline, 4:4:4: isolates the IDCT from chroma upsampling")
add("jpeg-baseline-422", "jpeg-baseline-422.jpg", "jpeg", jpeg(im, quality=90, subsampling=1), note="baseline, 4:2:2")
add("jpeg-progressive", "jpeg-progressive.jpg", "jpeg", jpeg(im, quality=85, subsampling=2, progressive=True), note="progressive, 4:2:0")
add("jpeg-progressive-444", "jpeg-progressive-444.jpg", "jpeg", jpeg(im, quality=95, subsampling=0, progressive=True), note="progressive, 4:4:4")
add("jpeg-grey", "jpeg-grey.jpg", "jpeg", jpeg(im.convert("L"), quality=90), note="greyscale JPEG")
cm = im.convert("CMYK")
add("jpeg-cmyk", "jpeg-cmyk.jpg", "jpeg-cmyk", jpeg(cm, quality=90), note="CMYK JPEG (Adobe marker, inverted): colour managed on the Mac, naive conversion in WIC: a large measured tolerance is expected")
add("jpeg-p3", "jpeg-p3.jpg", "jpeg-p3", jpeg(Image.frombytes("RGB", (24, 20), bytes(c for row in p3pat for px in row for c in px)), quality=100, subsampling=0, icc_profile=ICC_P3), note="JPEG 4:4:4 q100 tagged P3 (ICC APP2)")
# EXIF orientation 1-8: the stored image is the inverse transform of an upright 6x4 image with a distinct colour per pixel, so every file shows the same upright image
up = Image.new("RGB", (12, 8))
upx = [((x * 20) % 256, (y * 30 + 40) % 256, ((x + 2 * y) * 14) % 256) for y in range(8) for x in range(12)]
up.putdata(upx)
# EXIF orientation value -> the transform that maps the stored image to upright; the stored image is the inverse
ORI = {1: None, 2: Image.FLIP_LEFT_RIGHT, 3: Image.ROTATE_180, 4: Image.FLIP_TOP_BOTTOM, 5: Image.TRANSPOSE, 6: Image.ROTATE_270, 7: Image.TRANSVERSE, 8: Image.ROTATE_90}
INV = {1: None, 2: Image.FLIP_LEFT_RIGHT, 3: Image.ROTATE_180, 4: Image.FLIP_TOP_BOTTOM, 5: Image.TRANSPOSE, 6: Image.ROTATE_90, 7: Image.TRANSVERSE, 8: Image.ROTATE_270}
for o in range(1, 9):
    stored = up if INV[o] is None else up.transpose(INV[o])
    ex = Image.Exif(); ex[274] = o
    add(f"jpeg-exif-{o}", f"jpeg-exif-{o}.jpg", "orientation", jpeg(stored, quality=100, subsampling=0, exif=ex.tobytes()), orientation=o, note=f"EXIF orientation {o}; stored {stored.size[0]}x{stored.size[1]}")


# the same eight orientations in a LOSSLESS carrier: PNG with an eXIf chunk (TIFF payload, big endian), so orientation is gated byte-exact
for o in range(1, 9):
    stored = up if INV[o] is None else up.transpose(INV[o])
    sw_, sh_ = stored.size
    spx = list(stored.getdata())
    rows_ = [[spx[y * sw_ + x] for x in range(sw_)] for y in range(sh_)]
    exif = b"MM\x00*" + struct.pack(">I", 8) + struct.pack(">H", 1) + struct.pack(">HHI", 0x0112, 3, 1) + struct.pack(">HH", o, 0) + struct.pack(">I", 0)
    add(f"png-exif-{o}", f"png-exif-{o}.png", "orientation", png(sw_, sh_, 8, 2, rows_, extra=[(b"eXIf", exif)]), orientation=o, note=f"PNG eXIf orientation {o}; stored {sw_}x{sh_}")


# ---------- BMP ----------
def bmp(w, h, bpp, pix, palette=None, top_down=False, v4=False, v5=False):
    stride = ((w * bpp + 31) // 32) * 4
    hdrsize = 124 if v5 else (108 if v4 else 40)
    pal = b"".join(bytes([b, g, r, 0]) for (r, g, b) in palette) if palette else b""
    rows = []
    for y in range(h):
        if bpp == 32: row = b"".join(bytes([b, g, r, a]) for (r, g, b, a) in pix[y])
        elif bpp == 24: row = b"".join(bytes([b, g, r]) for (r, g, b) in pix[y])
        else: row = pack_samples([p for p in pix[y]], bpp)
        rows.append(row.ljust(stride, b"\0"))
    data = b"".join(rows if top_down else rows[::-1])
    off = 14 + hdrsize + len(pal)
    info = struct.pack("<IiiHHIIiiII", hdrsize, w, -h if top_down else h, 1, bpp, 3 if (v4 or v5) else 0, len(data), 2835, 2835, len(palette) if palette else 0, 0)
    if v4 or v5:
        info += struct.pack("<IIII", 0x00ff0000, 0x0000ff00, 0x000000ff, 0xff000000) + b"BGRs" + b"\0" * 48
    if v5:
        info += struct.pack("<IIII", 4, 0, 0, 0)
    return b"BM" + struct.pack("<IHHI", off + len(data), 0, 0, off) + info + pal + data


bw, bh = 20, 16
bp = rgba_field(bw, bh)
add("bmp-32-alpha-v4", "bmp-32-alpha-v4.bmp", "lossless", bmp(bw, bh, 32, bp, v4=True), note="32-bit BITMAPV4HEADER with BI_BITFIELDS and an alpha mask, bottom-up")
add("bmp-32-alpha-v5", "bmp-32-alpha-v5.bmp", "lossless", bmp(bw, bh, 32, bp, v5=True), note="32-bit BITMAPV5HEADER with BI_BITFIELDS and an alpha mask, bottom-up (ImageIO decodes this one)")
add("bmp-32-alpha-v5-topdown", "bmp-32-alpha-v5-topdown.bmp", "lossless", bmp(bw, bh, 32, bp, v5=True, top_down=True), note="the same, top-down")
add("bmp-32-alpha-v4-topdown", "bmp-32-alpha-v4-topdown.bmp", "lossless", bmp(bw, bh, 32, bp, v4=True, top_down=True), note="the same, top-down")
add("bmp-32-v3", "bmp-32-v3.bmp", "lossless", bmp(bw, bh, 32, bp), note="32-bit BITMAPINFOHEADER, BI_RGB (the alpha byte is unused by the format: platforms differ)")
add("bmp-24", "bmp-24.bmp", "lossless", bmp(bw, bh, 24, [[p[:3] for p in r] for r in bp]), note="24-bit bottom-up")
add("bmp-8-palette", "bmp-8-palette.bmp", "lossless", bmp(bw, bh, 8, [[(x * 3 + y) % 64 for x in range(bw)] for y in range(bh)], palette=[((i * 41) & 255, (i * 77) & 255, (i * 13) & 255) for i in range(64)]), note="8-bit palette")
add("bmp-4-palette", "bmp-4-palette.bmp", "lossless", bmp(bw, bh, 4, [[(x + y) % 16 for x in range(bw)] for y in range(bh)], palette=[((i * 17) & 255, (i * 51) & 255, (255 - i * 16) & 255) for i in range(16)]), note="4-bit palette")


# ---------- GIF ----------
def gif(frames, w, h, transparent=None):
    pal = [((i * 37 + 11) & 255, (i * 91 + 3) & 255, (i * 61 + 29) & 255) for i in range(16)]
    d = b"GIF89a" + struct.pack("<HHBBB", w, h, 0xF3, 0, 0) + b"".join(bytes(c) for c in pal)
    d += b"\x21\xff\x0bNETSCAPE2.0\x03\x01\x00\x00\x00"
    for fi, idx in enumerate(frames):
        d += b"\x21\xf9\x04" + bytes([0x09 if transparent is not None else 0x00, 10, 0, transparent if transparent is not None else 0]) + b"\x00"
        d += b"\x2c" + struct.pack("<HHHHB", 0, 0, w, h, 0) + b"\x04"
        # LZW (min code size 4), plain codes with clear codes often: simple valid encoder
        codes = []; bits = 0; nbits = 0; out = bytearray()
        clear, eoi = 16, 17
        def emit(code, size):
            nonlocal bits, nbits
            bits |= code << nbits; nbits += size
            while nbits >= 8: out.append(bits & 255); bits >>= 8; nbits -= 8
        count = 0
        emit(clear, 5)
        for v in idx:
            emit(v, 5); count += 1
            if count == 14: emit(clear, 5); count = 0   # table never outgrows 5-bit codes
        emit(eoi, 5)
        if nbits: out.append(bits & 255)
        blob = bytes(out)
        for i in range(0, len(blob), 255): d += bytes([min(255, len(blob) - i)]) + blob[i:i + 255]
        d += b"\x00"
    return d + b"\x3b"


gw, gh = 16, 12
gframes = [[(x + y + k * 5) % 16 for y in range(gh) for x in range(gw)] for k in range(3)]
add("gif-3frames", "gif-3frames.gif", "lossless", gif(gframes, gw, gh), note="3 frames, opaque: first frame only")
add("gif-3frames-transparent", "gif-3frames-transparent.gif", "lossless", gif(gframes, gw, gh, transparent=3), note="3 frames, palette index 3 transparent")


# ---------- ICO ----------
def dib_entry(w, h, bpp, rgba, palette=None):
    """ICO image: BITMAPINFOHEADER with doubled height, XOR bitmap bottom-up, AND mask"""
    stride = ((w * bpp + 31) // 32) * 4; mstride = ((w + 31) // 32) * 4
    pal = b"".join(bytes([b, g, r, 0]) for (r, g, b) in palette) if palette else b""
    xor = b""; mask = b""
    for y in range(h - 1, -1, -1):
        row = rgba[y]
        if bpp == 32: r_ = b"".join(bytes([b, g, r, a]) for (r, g, b, a) in row)
        elif bpp == 24: r_ = b"".join(bytes([b, g, r]) for (r, g, b, a) in row)
        else: r_ = pack_samples([row_i[0] for row_i in [(p[3],) for p in row]], bpp)
        xor += r_.ljust(stride, b"\0")
        mb = bytearray(mstride)
        for x, p in enumerate(row):
            if p[3] < 128: mb[x // 8] |= 0x80 >> (x % 8)
        mask += bytes(mb)
    hdr = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, bpp, 0, len(xor) + len(mask), 0, 0, len(palette) if palette else 0, 0)
    return hdr + pal + xor + mask


def icon_rgba(n):
    return [[((x * 255) // n, (y * 255) // n, 128, 255 if (x - n / 2) ** 2 + (y - n / 2) ** 2 < (n / 2) ** 2 else 0) for x in range(n)] for y in range(n)]


def png_entry(n):
    return png(n, n, 8, 6, [[p for p in row] for row in icon_rgba(n)])


def ico(entries):
    """entries: list of (w, h, bpp, bytes)"""
    d = struct.pack("<HHH", 0, 1, len(entries)); off = 6 + 16 * len(entries); body = b""
    for (w, h, bpp, data) in entries:
        d += struct.pack("<BBBBHHII", w if w < 256 else 0, h if h < 256 else 0, 0, 0, 1, bpp, len(data), off + len(body)); body += data
    return d + body


def pal_entry(n, bpp):
    pal = [((i * 53) & 255, (i * 97) & 255, (i * 29) & 255) for i in range(1 << bpp)]
    rows = [[(0, 0, 0, (x * 3 + y * 5) % (1 << bpp)) if (x - n / 2) ** 2 + (y - n / 2) ** 2 < (n / 2) ** 2 + 3 else (0, 0, 0, 0) for x in range(n)] for y in range(n)]
    return pal, rows


# Palette entries carry their index in slot 3 (alpha slot) until packed; the AND mask comes from "inside the circle"
def dib_pal(n, bpp):
    pal, rows = pal_entry(n, bpp)
    stride = ((n * bpp + 31) // 32) * 4; mstride = ((n + 31) // 32) * 4
    xor = b""; mask = b""
    for y in range(n - 1, -1, -1):
        idx = [rows[y][x][3] if (x - n / 2) ** 2 + (y - n / 2) ** 2 < (n / 2) ** 2 + 3 else 1 for x in range(n)]
        xor += pack_samples(idx, bpp).ljust(stride, b"\0")
        mb = bytearray(mstride)
        for x in range(n):
            if not ((x - n / 2) ** 2 + (y - n / 2) ** 2 < (n / 2) ** 2 + 3): mb[x // 8] |= 0x80 >> (x % 8)
        mask += bytes(mb)
    hdr = struct.pack("<IiiHHIIiiII", 40, n, n * 2, 1, bpp, 0, len(xor) + len(mask), 0, 0, len(pal), 0)
    return hdr + b"".join(bytes([b, g, r, 0]) for (r, g, b) in pal) + xor + mask


ico_multi = [(16, 16, 32, dib_entry(16, 16, 32, icon_rgba(16))), (32, 32, 32, dib_entry(32, 32, 32, icon_rgba(32))), (48, 48, 24, dib_entry(48, 48, 24, icon_rgba(48))),
             (64, 64, 32, png_entry(64)), (256, 256, 32, png_entry(256))]
add("ico-multi", "ico-multi.ico", "ico", ico(ico_multi), ico=[dict(w=e[0], h=e[1], bpp=e[2]) for e in ico_multi], note="16/32 DIB 32-bit, 48 DIB 24-bit, 64 and 256 PNG entries")
ico_dib = [(16, 16, 4, dib_pal(16, 4)), (32, 32, 8, dib_pal(32, 8)), (24, 24, 32, dib_entry(24, 24, 32, icon_rgba(24)))]
add("ico-dib", "ico-dib.ico", "ico", ico(ico_dib), ico=[dict(w=e[0], h=e[1], bpp=e[2]) for e in ico_dib], note="DIB entries only: 4-bit and 8-bit palette (AND mask), 32-bit")
tie_img = dib_pal(16, 4)
ico_tie = [(16, 16, 4, tie_img), (16, 16, 8, dib_pal(16, 8))]
add("ico-tie", "ico-tie.ico", "ico-policy", ico(ico_tie), ico=[dict(w=e[0], h=e[1], bpp=e[2]) for e in ico_tie], note="two 16 px entries: the rule picks the higher bit depth; unit-tested as policy (ImageIO orders same-size entries unobservably), decoded for crash safety only")
ico_small = [(16, 16, 32, dib_entry(16, 16, 32, icon_rgba(16))), (32, 32, 32, dib_entry(32, 32, 32, icon_rgba(32)))]
add("ico-two", "ico-two.ico", "ico", ico(ico_small), ico=[dict(w=e[0], h=e[1], bpp=e[2]) for e in ico_small], note="two 32-bit DIB entries")
# the same icon at several maxPixel values (entry selection rule moves into the policy layer): expected index by the block 35 rule
def pick(entries, mp):
    side = lambda e: max(e["w"], e["h"])
    enough = [i for i, e in enumerate(entries) if side(e) >= mp]
    if mp > 0 and enough:
        return min(enough, key=lambda i: (side(entries[i]), -entries[i]["bpp"], i))
    return max(range(len(entries)), key=lambda i: (side(entries[i]), entries[i]["bpp"], -i))


for m in list(manifest):
    if m["kind"] in ("ico", "ico-policy"):
        for mp in (0, 1, 16, 17, 33, 48, 100, 256, 1000):
            manifest.append(dict(m, id=f"{m['id']}@{mp}", maxPixel=mp, kind=m["kind"], expectIndex=pick(m["ico"], mp), variantOf=m["id"]))
        manifest.remove(m)
# thumbnails
for src in ("png-photo-rgb8", "png-photo-rgba8", "jpeg-baseline-444"):
    s = next(m for m in manifest if m["id"] == src)
    for mp in (32, 20, 8):
        manifest.append(dict(s, id=f"{src}@thumb{mp}", maxPixel=mp, kind="thumbnail", variantOf=src))
manifest = [m for m in manifest]

# ---------- negative controls ----------
def neg(case_id, data, note, expect="throws"):
    add(case_id, f"neg-{case_id}.bin", "negative", data, note=note, expect=expect)


good_png = (OUT / "png-rgba8-adam7.png").read_bytes()
png_plain = (OUT / "png-photo-rgb8.png").read_bytes()
jp = (OUT / "jpeg-baseline-420.jpg").read_bytes()
jpp = (OUT / "jpeg-progressive.jpg").read_bytes()
neg("empty", b"", "zero bytes")
neg("one-byte", b"\x89", "one byte")
neg("text", b"this is not an image\n" * 20, "plain text")
neg("random", bytes((i * 131 + 7) & 255 for i in range(500)), "pseudo-random bytes")
neg("png-signature-only", png_plain[:8], "PNG signature and nothing else")
neg("png-trunc-ihdr", png_plain[:20], "PNG cut inside IHDR")
neg("png-trunc-idat", png_plain[:len(png_plain) // 2], "PNG cut in the middle of the IDAT data")
neg("png-no-iend", png_plain[:-12], "PNG with the IEND chunk removed (all pixel data present)")
ba = bytearray(png_plain)
ba[40] ^= 0xff
neg("png-bad-crc", bytes(ba), "PNG with one byte of the IDAT payload flipped (bad CRC / bad zlib)")
bi = bytearray(png_plain); bi[16:20] = struct.pack(">I", 0)
neg("png-zero-width", bytes(bi), "PNG IHDR with width 0")
neg("png-adam7-trunc", good_png[:len(good_png) - 30], "Adam7 PNG cut near the end")
neg("jpeg-trunc-half", jp[:len(jp) // 2], "baseline JPEG cut in the middle of the scan")
neg("jpeg-trunc-eoi", jp[:-2], "baseline JPEG with the EOI marker removed (all scan data present)")
neg("jpeg-trunc-header", jp[:100], "JPEG cut inside the quantisation tables")
neg("jpeg-prog-trunc", jpp[:len(jpp) * 2 // 3], "progressive JPEG cut after two thirds")
jb = bytearray(jp); jb[2:4] = b"\x00\x00"
neg("jpeg-bad-marker", bytes(jb), "JPEG whose first marker after SOI is destroyed")
g = (OUT / "gif-3frames.gif").read_bytes()
neg("gif-trunc", g[:len(g) // 3], "GIF cut inside the first frame")
neg("gif-header-only", g[:13], "GIF header and nothing more")
b = (OUT / "bmp-24.bmp").read_bytes()
neg("bmp-trunc", b[:len(b) // 2], "BMP with half the pixel data")
neg("bmp-header-only", b[:30], "BMP cut inside the info header")
ic = (OUT / "ico-multi.ico").read_bytes()
neg("ico-trunc", ic[:len(ic) // 2], "ICO cut so an entry lies outside the file")
ib = bytearray(ic); ib[6 + 8:6 + 12] = struct.pack("<I", 10 ** 8)
neg("ico-bad-size", bytes(ib), "ICO whose first entry claims 100 MB")
neg("ico-no-images", b"\x00\x00\x01\x00\x00\x00", "ICO with an empty directory")
neg("jpeg-cmyk-trunc", (OUT / "jpeg-cmyk.jpg").read_bytes()[:len((OUT / "jpeg-cmyk.jpg").read_bytes()) // 2], "CMYK JPEG cut in the scan")
neg("png-chunk-garbage", png_plain[:33] + b"\xff" * 64 + png_plain[33:], "PNG with 64 bytes of 0xFF between IHDR and the next chunk")

TOL = {"jpeg-baseline-420": "jpeg-420", "jpeg-progressive": "jpeg-420", "jpeg-baseline-422": "jpeg-422", "jpeg-baseline-444": "jpeg-444", "jpeg-progressive-444": "jpeg-444", "jpeg-grey": "jpeg-grey",
       "jpeg-cmyk": "jpeg-cmyk", "jpeg-p3": "jpeg-p3", "png-p3-rgb8": "p3", "png-p3-rgba8": "p3"}
for m in manifest:
    if m["id"] in TOL: m["tolClass"] = TOL[m["id"]]
    elif m["kind"] == "orientation" and m["file"].endswith(".jpg"): m["tolClass"] = "jpeg-444"
    if m["id"] in ("ico-multi@33", "ico-multi@48"):
        m["refOverride"] = "old"; m["refReason"] = "ImageIO ignores the AND mask of a 24-bit ICO DIB entry (alpha 255 everywhere); WIC and the block 35 decoder apply it. The independent Swift decoder is the reference."
EQ = {"bmp-32-alpha-v4": "bmp-32-alpha-v5", "bmp-32-alpha-v4-topdown": "bmp-32-alpha-v5"}
for m in manifest:
    if m["id"] in EQ: m["equalsCase"] = EQ[m["id"]]; m["equalsReason"] = "ImageIO cannot decode BITMAPV4HEADER (returns nil); the same pixels in a V5 header are the Mac reference"
(OUT / "manifest.json").write_text(json.dumps(dict(version=1, cases=manifest), indent=1, sort_keys=True) + "\n")
print(len(manifest), "cases,", sum(m["bytes"] for m in manifest if "variantOf" not in m), "bytes of files")
