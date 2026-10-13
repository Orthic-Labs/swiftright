# Tinos Font.custom paint canary

`FontCustomPaintCanary.cpp` is factory-owned DirectWrite evidence for exact bundled `Tinos-Regular.ttf` bytes. It creates an isolated DirectWrite font set from caller path, requires family `Tinos` & PostScript `Tinos-Regular`, shapes witness text through exact face glyph indices/advances, paints matching `DWRITE_TEXTURE_CLEARTYPE_3x1` coverage into RGBA, rejects clipped/empty canvas coverage, & emits metrics plus output dimensions.

Canary output proves exact resource provider paint only. It emits `rendererSelection=unproven` & `bridgeMeasurementSelection=unproven`; no renderer, bridge, runtime, or ABI source changes are implied. Existing Swift host packet remains required for `Font.custom("Tinos-Regular", size: 18)` bridge measurement/capture.

Root supplies measured resource path & hash, compiles with bounded `cl.exe` environment, then supervises execution under existing 1 GiB Job Object. Example source invocation:

```text
FontCustomPaintCanary.exe <staged-Tinos-Regular.ttf> sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61 <stage>\\tinos.rgba.bin <stage>\\tinos.metadata.json 18
```

Expected metadata includes `designUnitsPerEm`, ascent/descent/lineGap, glyph count, RGBA byte count, exact family/PostScript identity, & both held selection fields. Root must hash RGBA/metadata/EXE & join those receipts with existing `windows-host/package` compile, bridge measure, native paint, screenshot, & UIA channels. No font installation or default-font fallback occurs.

Appending `--fault-empty-coverage` is a negative control: canary zeroes all alpha after rasterization & must fail `empty-coverage`; default invocation requires `nonZeroAlphaPixels > 0`. This exercises output validation, not a report-only status.
