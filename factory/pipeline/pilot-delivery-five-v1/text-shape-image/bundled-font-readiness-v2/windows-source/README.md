# Windows Tinos provider probe (source only)

`FontProbe.cpp` records one owned window `GetClientRect`, process-private `FR_PRIVATE` registration result, exact private DirectWrite family/PostScript identity, supplied Tinos byte hash, & read-only `GetSystemFontCollection` family presence. It does not alter renderer, ABI, or system fonts.

`resources/directwrite-private-font.cpp` is existing isolated `IDWriteFontCollection` evidence. Its private collection is distinct from renderer path in `factory/native/windows/RendererHostAdditive.swift.in`: host passes only `fontFamily` into ABI `MeasureRequest`; no renderer font-byte registration hook exists. `systemCollectionFamilyPresent` therefore remains diagnostic, never qualification.

Root may compile/run probe only after attaching existing owned Windows RSS/job supervision. Arguments:

```text
FontProbe.exe <staged-Tinos-Regular.ttf> Tinos Tinos-Regular <owned-HWND-as-hex> sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61
```

Required output joins: `clientRect`, `resourceSha256Provided`, `privateCollectionFamily`, `privateCollectionPostScript`, `privateIdentity`, `systemCollectionFamilyPresent`, native text layout/run/glyph paint, screenshot, & UIA. A successful private identity is provider evidence only; renderer parity stays held until same-source capture.
