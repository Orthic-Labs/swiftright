# swiftui.rectangle.fill-frame

**Status:** blocked  
**Manifest cases:** 0 pass / 0 fail / 1 blocked / 0 invalidated / 1 total  
**Inventory:** inventory · **Progress:** recipe  
**Symbols:** s:SwiftUI.Rectangle  
**Capabilities:** unspecified  
**Evidence label:** synthetic/spec-example

| Manifest case | Status | Mac reference & channel counts | Windows reference & channel counts | Diff / channel values |
|---|---|---|---|---|
| spec-example.rectangle.case | blocked | spec-example.rectangle.capture-macos [sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc] · layout=1, paint=0, hit-testing=0, accessibility-provider=0, accessibility-external=0, focus=0, text=0, events-state=0, animation=0, presentation=0 | spec-example.rectangle.capture-windows [sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd] · layout=1, paint=0, hit-testing=0, accessibility-provider=0, accessibility-external=0, focus=0, text=0, events-state=0, animation=0, presentation=0 | layout: blocked · sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff; paint: held / no verdict channel; hit-testing: held / no verdict channel; accessibility-provider: held / no verdict channel; accessibility-external: held / no verdict channel; focus: held / no verdict channel; text: held / no verdict channel; events-state: held / no verdict channel; animation: held / no verdict channel; presentation: held / no verdict channel |

Empty capture arrays mean no observation for that channel; they never count as equal values. Missing captures & channels are held. Only paired, non-synthetic captures with records can support a passing verdict.
