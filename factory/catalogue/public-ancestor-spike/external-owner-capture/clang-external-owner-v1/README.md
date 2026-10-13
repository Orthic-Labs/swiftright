# Clang external owner v1

Bounded public-owner evidence for five requested external nominal targets:

* `AppKit.NSWindow` — ObjC interface, `c:objc(cs)NSWindow`, `NSWindow.h:283`
* `CoreGraphics.CGPoint` — typedef, `c:@S@CGPoint`, `CGGeometry.h:25`
* `CoreGraphics.CGSize` — typedef, `c:@S@CGSize`, `CGGeometry.h:33`
* `CoreGraphics.CGRect` — typedef, `c:@S@CGRect`, `CGGeometry.h:51`
* `Spatial.Size3D` — `SPSize3D` typedef + exact `SPATIAL_SWIFT_NAME(Size3D)` annotation, `Structures.h:129/131`

Each row binds exact SourceKit import USR/name/line, pinned Swift typecheck, Clang AST output, SDK header bytes/line, module map `export *`, tool hashes & zero exits. Full AST streams are lossless gzip-compressed; decompressed hashes are recorded. No public status comes from graph absence, basename, substring, or synthetic flags. No aliases are inferred.

Run:

```sh
python3 capture_clang_external.py
python3 test_clang_external.py
```
