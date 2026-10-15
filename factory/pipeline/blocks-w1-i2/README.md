# Wave 1 block I2: image layout, scaling and interpolation

Design: `docs/foundations-images-fonts.md` 1.3, 1.4 and 4 (I2). Decisions: `docs/sr1-decisions.md` G50-G59.

| File | What |
| --- | --- |
| `i2gen.py` | Deterministic, integer-only synthetic images (photo, lineart, text, alpha, checker); the same functions are pasted into every witness as Swift (`SWIFT_GEN`), so Mac (CGImage) and Windows (RGBAImage) build byte-identical pixels. |
| `make_cases.py` | Creates the cases: `swiftui.image-calibration/*` (Mac-only captures that feed the fit; the CALIBRATION image set) and `swiftui.image-layout/*` (Mac/Windows pairs; the GATING image set). Each case has `layout.json` (every cell: family, seed, source size, level, ratio, size, origin) and, for gate cases, `pair.json` with `resampleGate`. |
| `shared-mac-host/` | The Mac capture host: SwiftUI `ImageRenderer` at scale 2.5 (NOT the NSHostingView host: it draws every `Image.Interpolation` level the same, G50). |
| `resample_model.py`, `i2fit.py` | The offline fit (numpy; run with a venv python): candidate filters, placement rule, `fit-result.json` (the recorded fit), `fit-raw.json` (every candidate on every calibration cell), the Swift test vectors (`i2fit.py vectors`). |
| `tolerances.json` | The named tolerances, rounded up once from the calibration maxima (Windows pipeline against the Mac on the calibration set). |
| `pair_images.py` | Runs many cases with ONE Windows build (one executable target per case); `run_i2.py` is the one-case-per-build alternative through `pair.py`. |
| `stage_control.py` | Stages a deliberately wrong resampler for a negative control (nearest-high, straight-alpha, translate-1px, swap-rb); the product never carries a control. |
| `factory/tools/pair_resample_report.py` | The gate: frame and edges, exact cells, resampled cells within the named tolerance. |
| `evidence/` | Run summaries and reports. |

Reproduce: `python3 make_cases.py`; Mac calibration captures `python3 factory/tools/pair.py swiftui.image-calibration/<case> --skip-windows --runs 3`; fit `i2fit.py final <calibration case dirs>`;
Windows `python3 factory/tools/stage-product.py` then `python3 pair_images.py <stage> cal|gate --n N`.
