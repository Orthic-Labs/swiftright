#!/usr/bin/env python3
"""Creates (or re-stamps) the block 35 cases (SR1 round 5, hub gap: app icons): swiftui.image-data. `Image(decorative:scale:)` of a PNG held in the Witness as base64.
Windows builds the pixels with the SwiftRight `ImageDecoder` (a Swift PNG decoder, no zlib), the Mac with ImageIO (CGImageSourceCreateWithData -> CGImage); both then call
`Image(decorative:scale:)`, so the only difference between the two sides is the decoder and the paint path. The Witness is a 240 x 200 pt frame at (40, 20) pt in the
320 x 240 pt viewport (scale 2.5), as the other blocks 26-34 cases.
Scale 2.5 and a P px image give a P / 2.5 pt image: 40 px = 16 pt, device pixels map 1:1 and the pixels are gated exactly (the whole frame, decision 5 exact verdict).
Frame: the semantic tree (role image, count, order, bounds in pt, accessibilityLabel = name). Pixel position: the exact pixel gate itself.
Cases: exact-opaque-v1 (alpha 0 or 255 only: decoded values equal Apple's), alpha-blend-v1 (partial alpha over white: Apple premultiplies in 8 bits, so the blend is within a
measured tolerance), scaled-down-v1 (.resizable().frame / scaledToFit: Apple's interpolation vs a box filter, a measured tolerance, named in pair.json).
The tolerances below are filled from measurement (see TOLERANCE_*), never guessed.
usage: make_cases_imagedata.py [case-substring ...]"""
import base64, json, struct, subprocess, sys, tempfile, zlib
from pathlib import Path
H = Path(__file__).resolve().parent
HEADER = """#if os(Windows)
import Foundation
import SwiftRightRuntime
import SwiftRightHost
#else
import SwiftUI
import ImageIO
#endif

"""
HELPER = """
/// Windows: the SwiftRight decoder. Mac: ImageIO. Either way the result is drawn by `Image(decorative:scale:)`.
@MainActor @ViewBuilder func witnessImage(_ base64: String, scale: CGFloat, resizable: Bool = false, fit: Bool = false) -> some View {
#if os(Windows)
    let pixels = try! ImageDecoder.decode(Data(base64Encoded: base64)!, maxPixel: 0)
    let image = Image(decorative: pixels, scale: scale)
#else
    let source = CGImageSourceCreateWithData(Data(base64Encoded: base64)! as CFData, nil)!
    let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)!
    let image = Image(decorative: cgImage, scale: scale)
#endif
    if !resizable {
        image
    } else if fit {
        image.resizable().scaledToFit()
    } else {
        image.resizable()
    }
}
"""
SCALE, OX, OY = 2.5, 40, 20
CASES = {}
# measured on 15 October 2026 (see docs/sr1-decisions.md F17..F21); None = not yet measured (the case then gates exactly)
TOLERANCE = {"alpha-blend-v1": None,
             "scaled-down-v1": (100, 0, "CI 39580013879 (issue #61), 3 runs x 2 phases identical: the host's fitted bilinear (ImageResampler.plan(nil): triangle, sampled at the pixel centre, not widened; reproduced offline to max 1 level) against a Mac downscale that is widened and slightly sharpened (blue plateaus overshoot 200 -> 206..209 and 40 -> 31..34; no standard kernel fits: widened Mitchell best, max 43/26/41 per cell). The I2 fit (default == .low, max 1) used sources built with shouldInterpolate: false; this case decodes through ImageIO on the Mac (UNVERIFIED: shouldInterpolate true selects CoreGraphics' high-quality downscale). Measured: Half 40->20x21 max 79, Fraction 40->25 max 62, Squashed palette 40->30x15 max 98, all inside the 1 px edge band (0 out-of-band), smooth gradients (Fit, Quarter) max 3; position and size exact. Rounded up to 100; N=3 identical runs, widen only with new evidence. Fixing it means carrying shouldInterpolate on RGBAImage (SwiftRightRuntime) and a widened plan.")}


def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)


def png(w, h, ctype, rows, plte=None, trns=None):
    raw = b"".join(b"\x00" + bytes(r) for r in rows)
    d = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0))
    if plte: d += chunk(b"PLTE", bytes(plte))
    if trns is not None: d += chunk(b"tRNS", bytes(trns))
    return d + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")


def rgba_png(w, h, f):
    return png(w, h, 6, [[c for x in range(w) for c in f(x, y)] for y in range(h)])


def pal_png(w, h, palette, alphas, f):
    return png(w, h, 3, [[f(x, y) for x in range(w)] for y in range(h)], plte=[c for p in palette for c in p], trns=alphas)


def pattern_opaque(x, y):
    """40 x 40: a colour gradient with a checker, a diagonal line and a see-through disc (alpha 0 with a loud colour that must not show)."""
    if (x - 19.5) ** 2 + (y - 19.5) ** 2 < 36: return (255, 0, 0, 0)
    if abs(x - y) <= 1: return (255, 255, 255, 255)
    return (255 * x // 39, 255 * y // 39, 40 + 160 * (((x // 5) + (y // 5)) % 2), 255)


def pattern_gradient(x, y):
    """100 x 60: smooth horizontal and vertical gradients, opaque."""
    return (255 * x // 99, 255 * y // 59, 255 - 255 * x // 99, 255)


def pattern_alpha(x, y):
    """40 x 40: the same colours with alpha running 0..255 along x and a second ramp along y in the lower half."""
    r, g, b, _ = pattern_opaque(x, y)
    return (r, g, b, 255 * x // 39 if y < 20 else 255 - 255 * x // 39)


PAL = [(230, 40, 40), (250, 170, 30), (240, 230, 60), (60, 190, 70), (40, 120, 220), (120, 60, 200), (20, 20, 20), (250, 250, 250)]
OPAQUE_ALPHAS = [255, 255, 255, 255, 255, 0, 255, 255]   # index 5 is see-through
PARTIAL_ALPHAS = [255, 192, 128, 64, 32, 0, 160, 96]


def palette_index(x, y):
    d = max(abs(x - 19.5), abs(y - 19.5))
    return int(d // 2.5) % 8


IMG = {
    "opaque": base64.b64encode(rgba_png(40, 40, pattern_opaque)).decode(),
    "palette": base64.b64encode(pal_png(40, 40, PAL, OPAQUE_ALPHAS, palette_index)).decode(),
    "gradient": base64.b64encode(rgba_png(100, 60, pattern_gradient)).decode(),
    "alpha": base64.b64encode(rgba_png(40, 40, pattern_alpha)).decode(),
    "palette-alpha": base64.b64encode(pal_png(40, 40, PAL, PARTIAL_ALPHAS, palette_index)).decode(),
}


def r(x0, y0, x1, y1):
    return [round((OX + x0) * SCALE), round((OY + y0) * SCALE), round((OX + x1) * SCALE), round((OY + y1) * SCALE)]


def witness(typename, rows):
    """rows: list of rows; a row is a list of (image key, mode, frame suffix, label, scale). Each row is an HStack(spacing: 8) at the leading edge, rows 8 pt apart."""
    consts = "".join(f'private let png_{k.replace("-", "_")} = "{v}"\n' for k, v in IMG.items())
    lines = []
    for row in rows:
        cells = []
        for key, mode, frame, label, scale in row:
            # mode: "" (natural size), "resizable" or "fit" (resizable().scaledToFit()); the accessibility element wraps the Image alone, the frame goes outside it
            flags = (", resizable: true" if mode else "") + (", fit: true" if mode == "fit" else "")
            cells.append(f'witnessImage(png_{key.replace("-", "_")}, scale: {scale}{flags}).accessibilityElement(children: .ignore).accessibilityLabel("{label}").accessibilityAddTraits(.isImage){frame}')
        lines.append("            HStack(spacing: 8) { " + "; ".join(cells) + " }")
    return HEADER + consts + HELPER + f"""
struct {typename}: View {{
    var body: some View {{
        VStack(alignment: .leading, spacing: 8) {{
{chr(10).join(lines)}
        }}.frame(width: 240, height: 200, alignment: .topLeading)
    }}
}}"""


def pair_json(case_name, with_tolerance):
    pair = {"semanticGate": {"fields": ["role", "name", "count", "order", "bounds"], "scope": "main", "phases": ["start", ""], "boundsTolerancePt": 0.05},
            "phaseShots": ["start"]}
    if with_tolerance:
        pair["edgeAATolerance"] = {"levels": with_tolerance[0], "reason": with_tolerance[2]}
        pair["hazeTolerance"] = with_tolerance[1]
    return pair


STEPS = [{"op": "wait", "ms": 700}, {"op": "dump", "label": "start"}, {"op": "wait", "ms": 250}, {"op": "shot", "label": "start"}, {"op": "wait", "ms": 200}]


def case(name, typename, rows, tolerance=None):
    CASES["swiftui.image-data/" + name] = dict(type=typename, body=witness(typename, rows), pair=pair_json(name, tolerance), steps=STEPS)


# P px at scale 2.5 is P / 2.5 pt: 40 px = 16 pt, 100 x 60 px = 40 x 24 pt: every edge lands on a device pixel.
case("exact-opaque-v1", "Witness_img_opaque", [
    [("opaque", "", "", "Pattern", 2.5), ("palette", "", "", "Rings", 2.5)],
    [("gradient", "", "", "Gradient", 2.5)],
])
case("alpha-blend-v1", "Witness_img_alpha", [
    [("alpha", "", "", "Alpha ramp", 2.5), ("palette-alpha", "", "", "Partial palette", 2.5)],
], TOLERANCE["alpha-blend-v1"])
case("scaled-down-v1", "Witness_img_scaled", [
    [("opaque", "resizable", ".frame(width: 8, height: 8)", "Half", 2.5), ("opaque", "resizable", ".frame(width: 10, height: 10)", "Fraction", 2.5),
     ("palette", "resizable", ".frame(width: 12, height: 6)", "Squashed", 2.5)],
    [("gradient", "fit", ".frame(width: 20, height: 20)", "Fit", 2.5), ("gradient", "resizable", ".frame(width: 16, height: 9.6)", "Quarter", 2.5)],
], TOLERANCE["scaled-down-v1"])


def main():
    only = sys.argv[1:]
    for name, c in CASES.items():
        if only and not any(o in name for o in only): continue
        with tempfile.TemporaryDirectory() as d:
            w = Path(d) / "Witness.swift"; w.write_text(c["body"] + "\n")
            p = Path(d) / "pair.json"; p.write_text(json.dumps(c["pair"]))
            s = Path(d) / "steps.json"; s.write_text(json.dumps(c["steps"]))
            subprocess.check_call([sys.executable, str(H / "new-case.py"), name, str(w), c["type"] + "()", "--pair-json", str(p), "--steps", str(s)])


if __name__ == "__main__":
    main()
