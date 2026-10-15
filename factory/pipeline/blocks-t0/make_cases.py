#!/usr/bin/env python3
"""Creates (or re-stamps) the wave 0 block T0 cases (docs/foundations-images-fonts.md 1.2 and 4): swiftui.alpha. The alpha path end to end, judged against the
ANALYTIC composite (factory/tools/pair_alpha_report.py), not against the Mac: out = bg * (1 - a) + fg * a per 8-bit sRGB channel, within 1/255; a pixel of
alpha 0 draws nothing (exact); alpha 255 is exact.
The Witness fills the whole 320 x 240 pt viewport (scale 2.5 = 800 x 600 px). Three background bands of 70 pt (white, black, colour) and a 30 pt white strip;
cells are 40 x 40 pt at x = 20 + 40 i and y = 14 pt below each band's top (a multiple of 2 pt, so every edge is a whole device pixel).
Cases (rect = Rectangle().fill(Color(red:green:blue:opacity:)); image = a registered RGBA8 image drawn 1:1 through Image(decorative:scale:), straight alpha):
  rect-ramp-v1    alpha 0, 1, 64, 128, 192, 254, 255 of 255 over white, black, colour
  image-ramp-v1   the same ramp as 100 x 100 px images (alpha 0 pixels carry non-zero RGB)
  clear-fills-v1  Color.clear, Rectangle().fill(.clear), Color.black.opacity(0.001), Rectangle().fill(black.opacity(0.001)), Color.red.opacity(0) over white, black, colour
  alpha0-rgb-v1   images whose alpha 0 pixels carry loud RGB: a split (alpha 0 yellow | opaque red) and a 4 px checker (alpha 0 white | opaque black)
  red-50-v1       50 % red over white, as a rectangle and as a registered image
usage: make_cases.py [case-substring ...]"""
import json, subprocess, sys
from pathlib import Path
H = Path(__file__).resolve().parent
GROUP = "swiftui.alpha"
S = 2.5
FG = (220, 40, 120)
WHITE, BLACK, COLOUR = (255, 255, 255), (0, 0, 0), (40, 120, 200)
BANDS = [("white", WHITE), ("black", BLACK), ("colour", COLOUR)]
RAMP = [0, 1, 64, 128, 192, 254, 255]
BAND_H, CELL, X0, Y0 = 70, 40, 20, 14   # pt
HEADER = """#if os(Windows)
import Foundation
import SwiftRightRuntime
#else
import SwiftUI
import ImageIO
import CoreGraphics
#endif

"""
HELPER = """
/// Straight-alpha RGBA8 pixels drawn 1:1 (scale 2.5: W px = W / 2.5 pt). Windows: RGBAImage -> Image(decorative:scale:) -> swr_image_register. Mac: CGImage (alpha last, not premultiplied).
@MainActor func pixelImage(_ w: Int, _ h: Int, _ f: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> Image {
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w { let p = f(x, y); let i = (y * w + x) * 4; bytes[i] = p.0; bytes[i + 1] = p.1; bytes[i + 2] = p.2; bytes[i + 3] = p.3 } }
#if os(Windows)
    return Image(decorative: RGBAImage(width: w, height: h, rgba: bytes)!, scale: 2.5)
#else
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    return Image(decorative: cg, scale: 2.5)
#endif
}

func band<Content: View>(_ r: Double, _ g: Double, _ b: Double, @ViewBuilder _ cells: () -> Content) -> some View {
    ZStack(alignment: .topLeading) {
        Rectangle().fill(Color(red: r, green: g, blue: b))
        HStack(spacing: 0) { cells() }.padding(.top, 14).padding(.leading, 20)
    }.frame(width: 320, height: 70, alignment: .topLeading)
}
"""


def px(v):
    r = v * S
    assert abs(r - round(r)) < 1e-9, v
    return int(round(r))


def over(bg, fg, a):
    return [bg[i] * (1 - a) + fg[i] * a for i in range(3)]


def frame_rows(rows):
    """The three bands + the strip as a Witness body; rows = [cells-source for white, black, colour]."""
    out = []
    for (name, c), cells in zip(BANDS, rows):
        out.append(f"            band({c[0]}.0 / 255, {c[1]}.0 / 255, {c[2]}.0 / 255) {{ {cells} }}")
    out.append("            Rectangle().fill(Color(red: 1, green: 1, blue: 1)).frame(width: 320, height: 30)")
    return "\n".join(out)


def witness(name, rows):
    return HEADER + HELPER + f"""
struct {name}: View {{
    var body: some View {{
        VStack(spacing: 0) {{
{frame_rows(rows)}
        }}.frame(width: 320, height: 240, alignment: .topLeading)
    }}
}}
"""


def ground():
    g = [dict(name=f"ground-{n}", rect=[0, px(i * BAND_H), 800, px((i + 1) * BAND_H)], rgb=list(c)) for i, (n, c) in enumerate(BANDS)]
    g.append(dict(name="ground-strip", rect=[0, px(3 * BAND_H), 800, 600], rgb=list(WHITE)))
    return g


def cell_rect(band, col, w=CELL, h=CELL, x0=X0, step=CELL):
    return [px(x0 + col * step), px(band * BAND_H + Y0), px(x0 + col * step + w), px(band * BAND_H + Y0 + h)]


def gate(regions, reason):
    return {"alphaGate": {"toleranceReason": reason, "ground": ground(), "regions": regions}}


REASON = ("analytic model, not a Mac comparison: out = bg * (1 - a) + fg * a per 8-bit sRGB channel, compared as an unrounded float; 1 level covers one rounding step of an 8-bit "
          "source-over blend (premultiplied storage, 255 versus 256 divisors); alpha 0, alpha 255 and the background are exact. Wave 0 T0, docs/foundations-images-fonts.md 1.2.")
CASES = {}


def ramp_case(kind, fg=FG, alphas=RAMP, tag=""):
    rows, regions = [], []
    for b, (bn, bg) in enumerate(BANDS):
        cells = []
        for i, a in enumerate(alphas):
            al = a / 255
            if kind == "rect":
                cells.append(f"Rectangle().fill(Color(red: {fg[0]}.0 / 255, green: {fg[1]}.0 / 255, blue: {fg[2]}.0 / 255, opacity: {a}.0 / 255)).frame(width: 40, height: 40)")
            else:
                cells.append(f"pixelImage(100, 100) {{ _, _ in ({fg[0]}, {fg[1]}, {fg[2]}, {a}) }}")
            regions.append(dict(name=f"{kind}{tag}-{bn}-a{a}", rect=cell_rect(b, i), tol=0 if a in (0, 255) else 1, expect=over(bg, fg, al)))
        rows.append("; ".join(cells))
    return witness(f"Witness_t0_{kind}{tag.replace('-', '_')}_ramp", rows), f"Witness_t0_{kind}{tag.replace('-', '_')}_ramp()", gate(regions, REASON)


def clear_case():
    w = 48
    variants = [f"Color.clear.frame(width: {w}, height: 40)",
                f"Rectangle().fill(Color.clear).frame(width: {w}, height: 40)",
                f"Color.black.opacity(0.001).frame(width: {w}, height: 40)",
                f"Rectangle().fill(Color.black.opacity(0.001)).frame(width: {w}, height: 40)",
                f"Color.red.opacity(0).frame(width: {w}, height: 40)",
                # the hub's hit area: a plain Button whose label is a 0.001 black fill under a small opaque mark
                f"Button {{ }} label: {{ ZStack {{ Color.black.opacity(0.001); Rectangle().fill(Color(red: 1, green: 0, blue: 0)).frame(width: 16, height: 16) }}.frame(width: {w}, height: 40) }}.buttonStyle(.plain)"]
    names = ["Color.clear", "fill-clear", "black-0.001", "fill-black-0.001", "red-opacity-0", "plain-button-hit-area"]
    rows = ["; ".join(variants)] * 3
    regions = []
    for b, (bn, bg) in enumerate(BANDS):
        for i, n in enumerate(names):
            regions.append(dict(name=f"{n}-{bn}", rect=cell_rect(b, i, w=w, x0=X0, step=w), tol=0, expect=list(bg)))
        # the red mark: 16 x 16 pt centred in the last cell (x 20 + 5 * 48 + 16 = 276, y 12 pt below the cell top)
        regions.append(dict(name=f"plain-button-mark-{bn}", rect=[px(X0 + 5 * 48 + 16), px(b * BAND_H + Y0 + 12), px(X0 + 5 * 48 + 32), px(b * BAND_H + Y0 + 28)], tol=0, expect=[255, 0, 0]))
    return witness("Witness_t0_clear_fills", rows), "Witness_t0_clear_fills()", gate(regions, REASON)


HUB_HELPER = """
/// The hub's HubLayered / HubHitArea (Pulse swift/RightKitHub/Components/HubLayered.swift at bd6bd3df), copied verbatim: the plain-Button hit area of every sidebar row (hub gap R12).
struct HubLayered<Content: View>: View {
    private let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { HubLayeredLayout { content } }
}
private struct HubLayeredLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let last = subviews.last else { return .zero }
        return last.sizeThatFits(proposal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let size = ProposedViewSize(width: bounds.width, height: bounds.height)
        for subview in subviews { subview.place(at: bounds.origin, anchor: .topLeading, proposal: size) }
    }
}
struct HubHitArea: View {
    var body: some View { Rectangle().fill(Color.black.opacity(0.001)) }
}
"""


def hub_hit_case():
    row = ("Button { } label: { HubLayered { HubHitArea(); HStack(spacing: 0) { pixelImage(100, 100) { _, _ in (255, 0, 0, 255) }; Spacer(minLength: 0) }.padding(.leading, 8) } }"
           ".buttonStyle(.plain).frame(width: 280, height: 40)")
    rows = [row] * 3
    src = witness("Witness_t0_hub_hit_area", rows).replace("struct Witness_t0_hub_hit_area", HUB_HELPER + "\nstruct Witness_t0_hub_hit_area")
    regions = []
    for b, (bn, bg) in enumerate(BANDS):
        regions.append(dict(name=f"row-{bn}", rect=cell_rect(b, 0, w=280), tol=0, expect=list(bg)))
        regions.append(dict(name=f"mark-{bn}", rect=[px(28), px(b * BAND_H + Y0), px(68), px(b * BAND_H + Y0 + 40)], tol=0, expect=[255, 0, 0]))
    return src, "Witness_t0_hub_hit_area()", gate(regions, REASON)


def alpha0_case():
    split = "pixelImage(100, 100) { x, _ in x < 50 ? (255, 255, 0, 0) : (255, 0, 0, 255) }"
    checker = "pixelImage(100, 100) { x, y in ((x / 4) + (y / 4)) % 2 == 0 ? (255, 255, 255, 0) : (0, 0, 0, 255) }"
    rows = [f"{split}; {checker}"] * 3
    regions = []
    for b, (bn, bg) in enumerate(BANDS):
        r = cell_rect(b, 0)
        regions.append(dict(name=f"split-{bn}", rect=r, tol=0, pattern=dict(kind="split", axis="x", atPx=50, first=list(bg), second=[255, 0, 0])))
        r = cell_rect(b, 1)
        regions.append(dict(name=f"checker-{bn}", rect=r, tol=0, pattern=dict(kind="checker", cellPx=4, even=list(bg), odd=[0, 0, 0])))
    return witness("Witness_t0_alpha0_rgb", rows), "Witness_t0_alpha0_rgb()", gate(regions, REASON)


def red50_case():
    # 50 % red over white; alpha quantised to 128/255 on both sides (the host rounds 0.5 * 255 up), the analytic value is the exact 0.5 (G = B = 127.5): tolerance 1 covers both.
    rect = "Rectangle().fill(Color(red: 1, green: 0, blue: 0, opacity: 0.5)).frame(width: 40, height: 40)"
    img = "pixelImage(100, 100) { _, _ in (255, 0, 0, 128) }"
    rows = [f"{rect}; {img}", "", ""]
    rows[1] = "Spacer().frame(width: 1, height: 1)"; rows[2] = "Spacer().frame(width: 1, height: 1)"
    regions = [dict(name="rect-red-50-white", rect=cell_rect(0, 0), tol=1, expect=over(WHITE, (255, 0, 0), 0.5)),
               dict(name="image-red-50-white", rect=cell_rect(0, 1), tol=1, expect=over(WHITE, (255, 0, 0), 0.5))]
    return witness("Witness_t0_red_50", rows), "Witness_t0_red_50()", gate(regions, REASON)


BLACK_RAMP = [0, 1, 2, 5, 25, 128, 255]
CASES = {"rect-ramp-v1": ramp_case("rect"), "image-ramp-v1": ramp_case("image"),
         "rect-black-ramp-v1": ramp_case("rect", (0, 0, 0), BLACK_RAMP, "-black"), "image-black-ramp-v1": ramp_case("image", (0, 0, 0), BLACK_RAMP, "-black"), "clear-fills-v1": clear_case(), "alpha0-rgb-v1": alpha0_case(), "red-50-v1": red50_case(), "hub-hit-area-v1": hub_hit_case()}


def main():
    want = sys.argv[1:]
    tmp = H / ".witness-tmp"; tmp.mkdir(exist_ok=True)
    for case, (src, expr, pair) in CASES.items():
        if want and not any(w in case for w in want): continue
        d = H / GROUP / case
        (d).mkdir(parents=True, exist_ok=True)
        wf = tmp / (case + ".swift"); wf.write_text(src)
        pj = tmp / (case + ".json"); pj.write_text(json.dumps(pair, indent=1))
        subprocess.check_call([sys.executable, str(H / "new-case.py"), f"{GROUP}/{case}", str(wf), expr, "--settle", "0.3", "--pair-json", str(pj)])
    import shutil; shutil.rmtree(tmp)


main()
