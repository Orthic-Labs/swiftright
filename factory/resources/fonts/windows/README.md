# Private DirectWrite font qualification

This control loads vendored `Tinos-Regular.ttf` into an isolated DirectWrite factory's custom font set and collection. `IDWriteFontSetBuilder2::AddFontFile` references one absolute local font path; `CreateFontCollectionFromFontSet` creates a collection scoped to this process. The control also queried the system font collection read-only: it did not contain Tinos on BOGUS-DELL. No font was installed and no global font registration was performed.

The measured face resolved to family `Tinos` and PostScript name `Tinos-Regular`. DirectWrite reported 2,048 units per em, ascent 1,825, descent 443, line gap 87, and glyph advance sum 19,116 for `Tinos font metrics`. An 18-DIP text layout measured 131.344 × 20.698 DIP. Raw input bytes matched vendored resource hash `sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61`.

`private-collection-result.json` records candidate qualification and hashes. Review remains pending. This demonstrates DirectWrite private collection loading and metrics; Windows SwiftUI `Font.custom` integration remains held until staged SwiftRightUI exposes that API. No glyph-raster image was captured by this control.

The implementation follows Microsoft DirectWrite documentation for [custom font collections](https://learn.microsoft.com/en-us/windows/win32/DirectWrite/custom-font-collections), [custom font sets](https://learn.microsoft.com/en-us/windows/win32/directwrite/custom-font-sets-win10), [`IDWriteFontSetBuilder2::AddFontFile`](https://learn.microsoft.com/en-us/windows/win32/api/dwrite_3/nf-dwrite_3-idwritefontsetbuilder2-addfontfile), and [`IDWriteFactory3::CreateFontCollectionFromFontSet`](https://learn.microsoft.com/en-us/windows/win32/api/dwrite_3/nf-dwrite_3-idwritefactory3-createfontcollectionfromfontset).

The helper was compiled with installed MSVC 14.51.36231 x64 and run headlessly on BOGUS-DELL (Windows 10.0.26300.0). Source: `directwrite-private-font.cpp`; build command: `build-directwrite-private-font.cmd`.
