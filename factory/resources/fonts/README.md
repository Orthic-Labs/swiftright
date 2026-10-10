# Bundled Tinos font resource

`Tinos-Regular.ttf` is an unmodified static font file from Google Fonts' Tinos
directory. Its source metadata identifies the Tinos project commit and SIL Open
Font License 1.1; the matching upstream `OFL.txt` is included beside it.
`resource.json` records exact local hashes, upstream URLs, Git blob identity, and
candidate qualification evidence.

`font-control.swift` registers the file with CoreText using `.process`, reads
PostScript name and metrics, and renders a PNG through SwiftUI `ImageRenderer`.
It does not install the font or request system font permissions. The captured
font load/render result is one macOS candidate run. Windows DirectWrite private
font collection behavior remains held for native Windows verification.

To rerun the macOS control without writing build products into the checkout:

```sh
mkdir -p /tmp/swiftright-font-qualification
SWIFT_MODULECACHE_PATH=/tmp/swiftright-font-qualification/module-cache \
CLANG_MODULE_CACHE_PATH=/tmp/swiftright-font-qualification/clang-cache \
swiftc -parse-as-library -framework AppKit -framework CoreText -framework SwiftUI \
  factory/resources/fonts/font-control.swift \
  -o /tmp/swiftright-font-qualification/font-control
/tmp/swiftright-font-qualification/font-control \
  "$PWD/factory/resources/fonts/Tinos-Regular.ttf" \
  "$PWD/factory/resources/fonts/evidence/tinos-render.png"
```
