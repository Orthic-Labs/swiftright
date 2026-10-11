# Paired padding settled v1

Prepared source-bound report for exact gate-seeded Mac padding evidence & fresh Windows settled-repeat evidence.

Mac input is immutable existing archive `factory/native/macos/evidence/20261010-gate-seeded/swiftui.padding-frame.recipe.gate-seeded.ca4e13f820f5d258`: 20 independent runs, case `84951ddf…`, source `b969817f…`, witness `860fa789…`, Apple Swift 6.4 / arm64-apple-macosx27.0. Raw offscreen reference is 96×40 @1; compositor is 96×72; witness AX text is 23×16.

Windows input defaults to `factory/native/windows/padding-settled-capture-v4/actual-repeat-r1`; `--windows-root` supports exact fetched archive path. Each run must bind case/source/native observation/UIA/pixel records & report 800×600 @240 dpi. Compile pins are Swift 6.4 Windows x86_64, compiler `1e406093…`, renderer `e280f4a9…`, runtime tree `c9ce2fb6…`.

Semantic output maps only `AXStaticText` to `ControlType.Text`, preserving exact labels & provider raw bytes. Timing retains Mac monotonic clock JSON & Windows process timestamps separately; cross-platform timing comparison is unavailable. Native parity, pixel parity, provider readback, goldens & promotion remain held.

Run after Windows20 fetch:

```sh
python3 factory/pipeline/paired-padding-settled-v1/report.py --windows-root factory/native/windows/padding-settled-capture-v4/actual-repeat-r1
```

Pure source/case/qualification control checks run with `--fault-controls` once Windows archive exists.
