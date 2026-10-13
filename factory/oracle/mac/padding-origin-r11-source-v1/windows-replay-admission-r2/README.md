# Fresh Windows r11 source-bound compile packet

`source-bound-windows-r11-v2.json` binds fresh Mac r11 case/manifest/source to exact donor host source, compiler, renderer, runtime 21-source tree, bridge headers/modules, & actual producer closure. `prepare-fresh-windows-r11.ps1` is root-run source staging & compile control. It rejects source-root/path drift, every hash/byte mismatch, donor/fresh case tokens in Swift, reused executable policy, and nonfresh destination. It performs no capture/native/lock action.

Current map SHA256 is `sha256:5e18d1b8da3f7903526ca4316e7661f2d90d753098a1cc3d3d5d98d0e3c86994`.

Root invocation after transporting this packet to Dell:

```powershell
& .\prepare-fresh-windows-r11.ps1 `
  -FreshPacketRoot 'D:\Claude\swiftright\factory\oracle\mac\padding-origin-r11-source-v1\windows-replay-admission-r2' `
  -SourcePackageRoot 'D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package' `
  -RuntimeSourceRoot 'D:\Claude\swiftright\.factory-work\runtime-stage\runtime' `
  -BridgeSourceRoot 'D:\Claude\swiftright\.factory-work\inputs\SwiftRightBridge' `
  -CompilerPath 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe' `
  -RendererPath 'D:\Claude\swiftright\.factory-work\inputs\renderer\swiftright_render.dll' `
  -SwiftPath 'C:\Users\adrds\AppData\Local\Programs\Swift\Toolchains\6.4.0+Asserts\usr\bin\swift.exe' `
  -DestinationRoot 'D:\Claude\swiftright\.factory-work\hosts\padding-window-diagnosis\package-r11-fresh' `
  -SourceMapSha256 'sha256:5e18d1b8da3f7903526ca4316e7661f2d90d753098a1cc3d3d5d98d0e3c86994'
```

Map records donor receipt `sha256:1847f82af0c1d02452d816ca5051787e865afb5be50147d57065c0c37f93e4cf`, donor runtime commit `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`, runtime tree `sha256:c9ce2fb6d4e45c4bb452f91895909bc0179d6f9c97a946628a684ff8d163337e`, compiler `sha256:1e406093ba7ca843cfcfab9b6efc72c23bb67a621f2925802196d5891e642d1a`, renderer `sha256:e280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93`.

`Witness.swift` has no donor/fresh case ID or case hash. Fresh manifest is staged separately, preserving source equivalence while requiring fresh executable receipt. Build receipt remains candidate-only until root validates output hash, source closure, & fresh metadata joins.
