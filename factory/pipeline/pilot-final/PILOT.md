# Actual pilot evidence

Fixed denominator: 81 cases; 10 primaries. Native captures: 200. Parity held.

| Block | Mac | Windows | Windows compile | Qualification |
|---|---:|---:|---|---|
| swiftui.custom-layout | 20 | 0 | failure | unqualified |
| swiftui.disabled | 20 | 0 | success | unqualified |
| swiftui.image | 20 | 0 | failure | unqualified |
| swiftui.padding-frame | 20 | 0 | failure | unqualified |
| swiftui.preference-key | 20 | 0 | failure | unqualified |
| swiftui.scroll-view | 20 | 0 | failure | unqualified |
| swiftui.shapes.fill-stroke | 20 | 0 | failure | unqualified |
| swiftui.stack-overlay | 20 | 0 | failure | unqualified |
| swiftui.text.bundled-font | 20 | 0 | failure | unqualified |
| swiftui.toggle | 20 | 0 | failure | unqualified |

Raw capture archives: [collection.json](collection.json). Full diagnostics & compile refs: [pilot-summary.json](pilot-summary.json).

Windows actual native replay count: 0.

- swiftui.custom-layout: unchanged shared witness rejected by staged SwiftRightRuntime APIs
- swiftui.disabled: desktop.lock remained cross09 for bounded six-minute wait
- swiftui.image: unchanged shared witness rejected by staged SwiftRightRuntime APIs
- swiftui.padding-frame: unchanged shared witness rejected by staged SwiftRightRuntime APIs
- swiftui.preference-key: unchanged shared witness rejected by staged SwiftRightRuntime APIs
- swiftui.scroll-view: unchanged shared witness rejected by staged SwiftRightRuntime APIs
- swiftui.shapes.fill-stroke: unchanged shared witness rejected by staged SwiftRightRuntime APIs
- swiftui.stack-overlay: unchanged shared witness rejected by staged SwiftRightRuntime APIs
- swiftui.text.bundled-font: unchanged shared witness rejected by staged SwiftRightRuntime APIs
- swiftui.toggle: unchanged shared witness rejected by staged SwiftRightRuntime APIs

Plain/offscreen/compositor/background captures remain unqualified. F10 requires fresh seeded captures, repeat qualification, Windows replay, trusted callbacks & SR0 closure.
