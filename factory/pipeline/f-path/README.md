# F-path block (sr1-decisions, 20 Oct 2026)

Vector paths (Path builders, StrokeStyle, FillStyle, Shape.trim, inset, capsule, custom shapes) are rasterised on the host and drawn through the existing image primitive. Delivery 1 has no ABI change; the decision is in `docs/sr1-decisions.md` ("F-path delivery 1 is host-rasterised" and "F-path pixel gate"). The Mac spike and its measurements are in [SPIKE-RESULT.md](SPIKE-RESULT.md).

## Cases (`swiftui.path/`)

| Case | Gate | Covers |
|---|---|---|
| `ring-trim-round-v1` | stroke | trim 0.62 with round caps |
| `ring-trim-dashed-butt-v1` | stroke + dashGeometry | trimmed dashes, butt caps |
| `ring-track-dashed-v1` | stroke + dashGeometry | full dashed track at 70% opacity |
| `ring-trim-tiny-v1` | stroke | trim 0.02 (tiny arc, round caps) |
| `ring-trim-zero-v1` | stroke | trim 0 draws nothing |
| `path-fill-nonzero-v1` | fill | pentagram, non-zero rule |
| `path-fill-evenodd-v1` | fill | pentagram, even-odd rule |
| `path-joins-v1` | stroke | miter (within and past the limit), round, bevel joins |
| `path-curves-v1` | stroke | quad, cubic, arc and ellipse subpaths |
| `stroke-hairline-v1` | stroke | 0.4, 0.5 and 1 pt hairlines |
| `dash-phase-v1` | stroke | dash [6, 3] with phase 2 on a line (no dashGeometry: not a ring) |
| `neg-butt-cap-v1` | stroke, expectFail | Windows witness uses `.butt`, the Mac `.round` |
| `neg-trim-060-v1` | stroke, expectFail | Windows trims to 0.60, the Mac to 0.62 |

Every case has the same `CaptureHost.swift`, `FactoryViewport.swift`, `main.swift` and `Package.swift` as the pill reference (`blocks-26-34/swiftui.continuous-shape-large/pill-v1`); only the witness file, its type name (`Witness_fp_<name>`) and `pair.json` differ. The witnesses are the SwiftUI reference views of `probes/sr0-s/fresh-runtime/Tools/PathParitySpike/Sources/PathParitySpike/SwiftUIReference.swift`.

## Gates (`pair.json`, read by `factory/tools/pair.py`)

- Fills: `edgeAATolerance {levels 32, maxOverPixels 4}`.
- Strokes: `edgeAATolerance {levels 160, maxOverFraction 0.01, maxMeanAbs 6}`.
- Dashed rings: `dashGeometry {center [400, 300], radius 67.5, maxAngleDeg 1.5}`, the ring centre and centreline radius in the 800x600 capture (the witness is centred in the 320x240 viewport at scale 2.5).
- Negative controls: `"expectFail": true`; the run passes only when the pixel gate fails.
- Every tolerance carries a reason that cites the spike.

Outside the 1 px edge band the gate stays exact.

## Run

`ci-list.txt` lists the 13 case directories (one per line, `factory/...` repository-relative). Local tests: `python3 factory/tools/test_pair_edge_stats.py`.
