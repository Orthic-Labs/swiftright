# Bundled-font readiness v3 — exact Tinos source packets

Current pinned runtime `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b` exposes `Font.custom`, `Font.Metadata` (`familyName`, `pointSize`, `weight`, `isCustom`), `TextMeasureRequest.fontMetadata` & `lineLimit`; `LayoutEngine` forwards metadata & limit. This proves metadata shape only.

Current ABI 0.6 `MeasureRequest` accepts `fontFamily`, `weight`, `fontSize`, `lineHeight`, `scale` & `maxWidth`; no font-byte registration or `lineLimit`. Current host template `factory/native/windows/RendererHostAdditive.swift.in` passes family into ABI but rejects `m.isCustom` & uses `size * 1.5` line height. No renderer source hook for private font bytes is present in factory-owned inputs.

Exact resource: `resources/Tinos-Regular.ttf`, 521588 bytes, SHA-256 `60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61`, family `Tinos`, PostScript `Tinos-Regular`, OFL 1.1. Existing `resources/directwrite-private-font.cpp` builds an isolated private `IDWriteFontCollection`; its collection is distinct from `GetSystemFontCollection`, so it does not establish renderer font selection.

Mac source packet `mac-source/` is complete source only. It retains exact accepted `Font.custom("Tinos-Regular", size: 18)` witness, fixed 320x240 top-leading host, process-only `CTFontManagerRegisterFontsForURL`, hash/PostScript/descriptor checks, no prompts, & provider observables. Root must compile/capture with 1 GiB process-group RSS supervision; TextRenderer glyph-font resolution remains held.

Windows source packet `windows-source/` is diagnostic only. Concrete host package `windows-host/` copies current Text retention/geometry & binds exact Tinos metadata. `FontProbe.cpp` records `GetClientRect`, `FR_PRIVATE` result, exact private DirectWrite family/PostScript, supplied resource hash & read-only system collection family presence. A private identity pass cannot qualify renderer parity. Root may build/run packets only with existing bounded Windows job/RSS supervision & required compile/source, native layout, text run/glyph paint, screenshot & UIA joins.

Root commands after source review:

```sh
sh mac-source/tools/prepare-mac-source.sh /Volumes/D/claude/swiftright /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/<fresh-stage>
sh mac-source/tools/compile-mac-source.sh <stage>/tinos-mac-source /Users/adrdsouza/Library/Caches/SwiftRightFactory/sr1/<fresh-app>.app
```

Run app with `--font-resource <stage>/tinos-mac-source/Resources/Tinos-Regular.ttf --font-hash sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61 --font-postscript Tinos-Regular`; root owns capture. Keep candidate outside five until fresh root receipts pass.
