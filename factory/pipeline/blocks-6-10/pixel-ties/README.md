# Block swiftui.pixel-ties (cross-cutting: device-pixel rounding at exact half pixels)

At scale 2.5 an odd number of points is an exact half device pixel (1 pt = 2.5 px). SwiftUI rounds such an edge by a value-dependent rule; the padding-frame and scroll lanes avoided those edges. These cases do not avoid them: every case puts edges on exact half pixels in x and y, through different layout paths, and compares the Mac capture (SwiftUI) with the Windows capture (runtime) pixel for pixel.

| Case | Ties it lands on |
|---|---|
| `ruler-v1` | 159 rows of a blue lead (2i + 1 pt) and a 1 pt red mark: x ties from 1 pt to 317 pt (every run of the rule), y ties at every odd row edge up to 159 pt; origin (0, 0) |
| `centered-origin-v1` | a 298 x 218 pt root centred at (11, 11) pt = 27.5 px (the origin itself is a tie), a diagonal of 3 pt squares stepping 12 x 8 pt, root far edges 309 pt and 229 pt (ties), corner pins through padding and `frame(alignment:)` |
| `layout-v1` | odd spacing, odd padding, `frame(alignment:)` with an odd centring offset, `VStack`/`HStack` of odd-length bars, inside a 300 x 200 pt root at (10, 20) pt |

Hosts are the padding-frame hosts (`../padding-frame/shared/make-case.py`: Mac `ImageRenderer` at 2.5, Windows runtime centring through a `ZStack` in a viewport-sized frame, so edges are snapped as absolute positions). Run: `python3 factory/tools/pair.py factory/pipeline/blocks-6-10/pixel-ties/<case> --runs 20 --sandbox --stage <stage> --renderer D:\Claude\swiftright\.factory-work\inputs\renderer-0.7-baseline-22ad719b\swiftright_render.dll`.

## The rule (measured)

An edge at `x` points lands on device pixel `floor((x + pl / 2) / pl)` with `pl = 1 / scale`, every operation in `Double`. Implementation: `DevicePixelSnap.pixel(_:scale:)` (probes/sr0-s/fresh-runtime), used by `snapToPixelGrid`, `pixelRect` and the continuous-shape painter. At scale 2.5 the ties come out: 1 pt down; 3, 5, 7 pt up; 9 to 25 pt down; 27 to 127 pt up; 129 to 409 pt down; 411 pt and beyond up.

Why it looks arbitrary: the reciprocal `1 / 2.5` is not exact in binary, so `(x + pl / 2) / pl` for an exact tie lands on the half pixel or one ulp below it depending on the mantissa of the value; the sign of that error changes in runs of 16x in magnitude.

Evidence (probe sources: `factory/pipeline/blocks-6-10/pixel-ties/probe/`): a filled Color at every tie position, measured first and last covered pixel per row.

* Fit: 2,400 tie probes (scales 1.25, 1.5, 2.5, 3, 5; whole-point ties and inexact-point ties) and all odd whole points 1 to 799 at 2.5: 0 mismatches.
* Held out (not used to fit): 10,600 tie probes: `NSHostingView.cacheDisplay` and `ImageRenderer`, scales 0.75, 1.1, 1.75, 2.25, 2.75, 3.5, 6, 7, x and y, padding / center / overlay / stack paths, whole points up to 3,000 (7,500 px): 0 mismatches except 11 on the inexact centring path (below). 600 random non-tie edges per scale: 0 mismatches.
* Path independence: the decision depends only on the final absolute `Double` position (stacks, padding, offsets, overlays and nested containers all give the same sweep).
* Limit: ties built by inexact arithmetic (0.1 steps, halving an inexact length, centring a fractional size) carry ulp noise from SwiftUI's own layout sums; the rule is exact on those only if the runtime computes the same `Double` (for the `((2a + w) - w) / 2` path the rule matches 800 of 800 once that arithmetic is applied; with the idealised `a` it misses 11). Whole-point and dyadic layouts (the usual case) are exact.

Probe: `probe/main.swift` (offscreen, no window shown; build `/usr/bin/xcrun swiftc -O main.swift -o probe` on the internal disk and run the scripts from the build directory; `--mode renderer|hosting|cg`, `--path hstack|padding|offset|center|overlay|shape|hgeo...`, `--scale S`, `--vert`). `gen.py` sweeps the tie at every pixel, `ints.py` every odd whole point, `validate.py` is the held-out battery, `held_geo.py` compares against the positions SwiftUI reports through `GeometryReader`, `models.py` scores a candidate rule against the stored sweeps (`g_<scale>.txt`: U = up, d = down, character n is the tie at pixel n + 0.5).

**Host rule.** SwiftUI snaps absolute edges, so a host must centre the tree through the runtime (a `ZStack` in a viewport-sized frame, as these cases and the Mac hosts do), never by translating the finished tree (`--centered`): a layout snapped relative to a translated root rounds ties by the wrong value (measured: custom-layout 9 pt tie became 113 pt absolute, Windows 282 vs Mac 283). The 13 delivered cases that used `--centered` were re-stamped this way (`main.swift` only); `new-case.py` still defaults to `--centered` and should be switched.
