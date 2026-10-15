"""Deterministic, integer-only synthetic images for wave 1 block I2 (docs/foundations-images-fonts.md 1.4). The SAME functions exist in Swift (SWIFT_GEN below, pasted
into every witness), so a witness builds byte-identical straight-alpha RGBA8 on the Mac (CGImage) and on Windows (RGBAImage) and this module reproduces the pixels
offline for the filter fit. Families: photo (value noise at three scales), lineart (stripes, an outline, a ring, a 2 px rule), text (6 px tall pseudo glyph rows),
alpha (a ring-edged disc with a straight-alpha ramp, loud RGB under alpha 0, an opaque inner square), checker (n px cells)."""
M = 0xFFFFFFFF


def h32(x, y, s):
    v = (x * 0x9E3779B1 + y * 0x85EBCA77 + s * 0xC2B2AE3D) & M
    v ^= v >> 15; v = (v * 0x2C1B3C6D) & M; v ^= v >> 12; v = (v * 0x297A2D39) & M; v ^= v >> 15
    return v


def vnoise(x, y, step, seed, ch):
    gx, fx, gy, fy = x // step, x % step, y // step, y % step
    s = seed * 8 + ch
    a, b, c, d = (h32(gx, gy, s) & 255), (h32(gx + 1, gy, s) & 255), (h32(gx, gy + 1, s) & 255), (h32(gx + 1, gy + 1, s) & 255)
    return ((a * (step - fx) + b * fx) * (step - fy) + (c * (step - fx) + d * fx) * fy) // (step * step)


def photo(w, h, seed):
    out = []
    for y in range(h):
        for x in range(w):
            px = []
            for ch in range(3):
                px.append((vnoise(x, y, 16, seed, ch) * 5 + vnoise(x, y, 6, seed + 100, ch) * 2 + vnoise(x, y, 3, seed + 200, ch)) // 8)
            out.append((px[0], px[1], px[2], 255))
    return out


def lineart(w, h, seed):
    s = h32(seed, 7, 3)
    a, b, m = 1 + s % 3, 1 + (s >> 3) % 3, 7 + (s >> 6) % 5
    cx, cy, r = w // 2, h // 2, min(w, h) // 3
    out = []
    for y in range(h):
        for x in range(w):
            on = (x * a + y * b) % m == 0
            on = on or x == 3 or x == w - 4 or y == 3 or y == h - 4
            d2 = (x - cx) ** 2 + (y - cy) ** 2
            on = on or abs(d2 - r * r) <= r
            on = on or y == h // 3 or y == h // 3 + 1
            out.append((0, 0, 0, 255) if on else (255, 255, 255, 255))
    return out


def text(w, h, seed):
    out = []
    for y in range(h):
        for x in range(w):
            line, ly = y // 9, y % 9
            on = False
            if 2 <= ly < 8 and x >= 2:
                cx, lx = (x - 2) // 4, (x - 2) % 4
                if cx * 4 + 2 + 3 <= w and h32(cx, line, seed) & 7 != 0 and lx < 3:
                    on = (h32(cx, line, seed + 1) >> (lx + (ly - 2) * 4)) & 1 == 1
            out.append((20, 20, 20, 255) if on else (250, 250, 250, 255))
    return out


def alpha(w, h, seed):
    cx, cy = w // 2, h // 2
    R = min(w, h) * 5 // 12
    lo, hi = (R - 3) ** 2, (R + 3) ** 2
    col = (200 - seed % 5 * 10, 60 + seed % 7 * 8, 30 + seed % 3 * 40)
    out = []
    for y in range(h):
        for x in range(w):
            d2 = (x - cx) ** 2 + (y - cy) ** 2
            if abs(x - cx) < R // 4 and abs(y - cy) < R // 4:
                out.append((20, 160, 60, 255)); continue
            if d2 <= lo: a = 255
            elif d2 >= hi: a = 0
            else: a = 255 * (hi - d2) // (hi - lo)
            out.append(col + (a,) if a else (255, 255, 0, 0))
    return out


def checker(w, h, seed):
    n = 1 + seed % 3
    return [((230, 230, 230, 255) if ((x // n) + (y // n)) % 2 == 0 else (30, 60, 200, 255)) for y in range(h) for x in range(w)]


FAMILIES = {"photo": photo, "lineart": lineart, "text": text, "alpha": alpha, "checker": checker}


def make(family, w, h, seed):
    return FAMILIES[family](w, h, seed)


SWIFT_GEN = r'''
func i2h32(_ x: UInt32, _ y: UInt32, _ s: UInt32) -> UInt32 {
    var v = x &* 0x9E3779B1 &+ y &* 0x85EBCA77 &+ s &* 0xC2B2AE3D
    v ^= v >> 15; v = v &* 0x2C1B3C6D; v ^= v >> 12; v = v &* 0x297A2D39; v ^= v >> 15
    return v
}
func i2vnoise(_ x: Int, _ y: Int, _ step: Int, _ seed: Int, _ ch: Int) -> Int {
    let gx = x / step, fx = x % step, gy = y / step, fy = y % step
    let s = UInt32(seed * 8 + ch)
    let a = Int(i2h32(UInt32(gx), UInt32(gy), s) & 255), b = Int(i2h32(UInt32(gx + 1), UInt32(gy), s) & 255)
    let c = Int(i2h32(UInt32(gx), UInt32(gy + 1), s) & 255), d = Int(i2h32(UInt32(gx + 1), UInt32(gy + 1), s) & 255)
    return ((a * (step - fx) + b * fx) * (step - fy) + (c * (step - fx) + d * fx) * fy) / (step * step)
}
typealias I2Px = (UInt8, UInt8, UInt8, UInt8)
func i2Pixel(_ family: String, _ w: Int, _ h: Int, _ seed: Int, _ x: Int, _ y: Int) -> I2Px {
    switch family {
    case "photo":
        var p = [UInt8](repeating: 0, count: 3)
        for ch in 0..<3 { p[ch] = UInt8((i2vnoise(x, y, 16, seed, ch) * 5 + i2vnoise(x, y, 6, seed + 100, ch) * 2 + i2vnoise(x, y, 3, seed + 200, ch)) / 8) }
        return (p[0], p[1], p[2], 255)
    case "lineart":
        let s = Int(i2h32(UInt32(seed), 7, 3))
        let a = 1 + s % 3, b = 1 + (s >> 3) % 3, m = 7 + (s >> 6) % 5
        let cx = w / 2, cy = h / 2, r = min(w, h) / 3
        var on = (x * a + y * b) % m == 0
        on = on || x == 3 || x == w - 4 || y == 3 || y == h - 4
        let d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy)
        on = on || abs(d2 - r * r) <= r
        on = on || y == h / 3 || y == h / 3 + 1
        return on ? (0, 0, 0, 255) : (255, 255, 255, 255)
    case "text":
        let line = y / 9, ly = y % 9
        var on = false
        if ly >= 2 && ly < 8 && x >= 2 {
            let cx = (x - 2) / 4, lx = (x - 2) % 4
            if cx * 4 + 2 + 3 <= w && i2h32(UInt32(cx), UInt32(line), UInt32(seed)) & 7 != 0 && lx < 3 {
                on = (i2h32(UInt32(cx), UInt32(line), UInt32(seed + 1)) >> UInt32(lx + (ly - 2) * 4)) & 1 == 1
            }
        }
        return on ? (20, 20, 20, 255) : (250, 250, 250, 255)
    case "alpha":
        let cx = w / 2, cy = h / 2, R = min(w, h) * 5 / 12
        let lo = (R - 3) * (R - 3), hi = (R + 3) * (R + 3)
        let d2 = (x - cx) * (x - cx) + (y - cy) * (y - cy)
        if abs(x - cx) < R / 4 && abs(y - cy) < R / 4 { return (20, 160, 60, 255) }
        let a: Int = d2 <= lo ? 255 : (d2 >= hi ? 0 : 255 * (hi - d2) / (hi - lo))
        if a == 0 { return (255, 255, 0, 0) }
        return (UInt8(200 - seed % 5 * 10), UInt8(60 + seed % 7 * 8), UInt8(30 + seed % 3 * 40), UInt8(a))
    default:
        let n = 1 + seed % 3
        return ((x / n) + (y / n)) % 2 == 0 ? (230, 230, 230, 255) : (30, 60, 200, 255)
    }
}
'''
