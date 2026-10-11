# One padding settled-metrics build

Source package copied from `padding-settled-metrics-v1`; Witness.swift & all Swift host files unchanged. Only Package.swift dependency paths & plan guards rebound. No prospective r09 dependency remains. Runtime is rolling `.factory-work\runtime-stage\runtime`; owned canonical bridge copy from0a745ab/header862997c is `.factory-work\inputs\SwiftRightBridge`; renderer is `.factory-work\inputs\renderer\swiftright_render.dll`, exact SHAe280f4a9fd9eca0a7b2657f72f8c322a537cee7b4c85999f6cbf7eb1f39ccc93.

Root transfer plan: copy packet into `D:\Claude\swiftright\.factory-work\hosts\padding-settled`; copy `dependencies/SwiftRightBridge` Package+Sources into owned bridge path. Do not copy renderer from unpinned origin; root already owns exact DLL inputs. All active outputs remain ignored. No remote action performed here.

Root-owned build commands after source review:

```powershell
$root='D:\Claude\swiftright\.factory-work\hosts\padding-settled'
& "$root\preflight.ps1" -Phase Compile
& "$root\run-controls.ps1"
& "$root\parse-stream-controls.ps1" -Output "$root\stream-parse.json"
& "$root\run-stream-controls.ps1"
& "$root\test-stream-admission.ps1" -OutputRoot "$root\stream-admission-faults"
& "$root\build-hosts-v2.ps1" -Package "$root\package"
```

One fresh `package/build-settled-r1` build only. Prospective compileRequest pins exact tool/cwd/release/gui/target/output & raw source bindings. Admitted retained-kernel/bounded stream helpers reused. Record includes actual produced executable/runtime-module hashes. No capture/repeat dispatcher in this packet.

Future native controller must invoke `preflight.ps1 -Phase Launch -CompileReceiptSha256 <actual> -ExeSha256 <actual>` immediately before child/DLL/window start; it requires actual compile success/kernel0/terminal streams/source/exe/context joins & rechecks exact renderer bytes last. This is required external loader guard dependency for metrics source; caller still needs independently admitted desktop-lock/CBT/owned-HWND/foreground/capture controls. No native/parity/closure grant.
