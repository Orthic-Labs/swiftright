# Windows Tinos host package (source only)

`package/` copies current measured Text host geometry/retention, then binds exact `Font.custom("Tinos-Regular", size: 18)` witness to `FactoryBundledFontMetadataAdapter`. Host derives provider line metrics from staged Tinos `head`/`hhea` tables beside EXE; optional metric flags remain diagnostic overrides, with source units logged. No default font or invented line height is used.

Adapter preserves requested PostScript name `Tinos-Regular` for runtime metadata, then sends DirectWrite family `Tinos` to ABI `MeasureRequest.fontFamily` after private registration.

Before `Bridge.load` or `bridge.run`, host calls `AddFontResourceExW(..., FR_PRIVATE, ...)`, validates TTF extension/size/SHA-256 bytes, prints resource SHA/family/PostScript metadata, & unregisters through `defer` after window shutdown. Registration is process-private provider evidence; renderer glyph-family selection remains `rendererSelection=unproven`.

Resource: `package/Resources/Tinos-Regular.ttf`, 521588 bytes, SHA-256 `sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61`. Root must independently hash staged resource before launch.

Root-owned bounded compile request:

```text
swift.exe build --package-path D:\Claude\swiftright\.factory-work\hosts\bundled-font-readiness-v2\windows-host\package --scratch-path D:\Claude\swiftright\.factory-work\hosts\bundled-font-readiness-v2\windows-host\package\build-tinos-r2\scratch -c release --jobs 1 -Xswiftc -j1 -Xswiftc -num-threads -Xswiftc 1
```

Copy exact resource beside fresh `FactoryProbe.exe`, then launch with `--tinos-font <staged-Tinos-Regular.ttf> (metric flags optional diagnostic overrides)`. Root owns 1 GiB RSS/job supervision, native capture, & all qualification receipts.

Paint-canary source is staged with same retained-handle Job Object helper. Root invocation for fresh revision:

```text
python3 factory/pipeline/pilot-delivery-five-v1/text-shape-image/bundled-font-readiness-v2/windows-host/tools/stage-bundled-font-v1.py --revision 2 --remote --run-canary --timeout 300
```

This archives compile, executable, positive RGBA/metadata/receipt, & expected failing `--fault-empty-coverage` receipt under stage transport archive. Renderer selection remains unproven.


## MSVC VCTIP admission

Paint canary compile records Microsoft Build Tools VSCEIP registry state read-only as diagnostic (Microsoft Learn: https://learn.microsoft.com/en-us/visualstudio/ide/visual-studio-experience-improvement-program): `OptIn=0` may appear under documented `HKLM\SOFTWARE\Policies\Microsoft\VisualStudio\SQM`, `HKLM\SOFTWARE\Wow6432Node\Microsoft\VSCommon\17.0\SQM`, or `HKLM\SOFTWARE\Microsoft\VSCommon\17.0\SQM`. It never mutates or gates on host-wide telemetry preference. `VSCMD_SKIP_SENDTELEMETRY=1` is set before & after `vcvars64.bat`; after original compiler exit 0 & sealed streams, only one exact pinned `vctip.exe` Job descendant may be stopped through retained handle. Wrong path, nonmembership, ambiguous child, or missing retained handle fails closed.
