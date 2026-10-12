# Stack default-font policy diagnosis

Status: host policy mismatch; pinned runtime does not emit a wrong point size.

Evidence:

- Witness is bare `Text("+")`: `factory/pipeline/pilot-delivery-five-v1/stack-layout/stack-overlay-centered-execution-v7/package/Sources/FactoryProbe/Witness.swift`. No `.font`, `.system(size:)`, or custom metadata is supplied.
- Pinned runtime `LayoutEngine.measureText` falls back to `Font(id: "body")`, then forwards `fontID`, nil `fontMetadata`, proposed width, scale, & line limit in `TextMeasureRequest`: `.factory-work/text-production-reader-r4/windows-archive/runtime/Sources/SwiftRightRuntime/LayoutEngine.swift:482-496`.
- `TextMeasureRequest` documents nil `proposedWidth` as no wrap; it carries no default point-size field: `.factory-work/text-production-reader-r4/windows-archive/runtime/Sources/SwiftRightRuntime/TextMeasurement.swift:3-20`.
- Runtime `Font.body` is only identifier `textStyle.body`; no 16-point or 24-DIP default exists in pinned `Controls.swift:321`. Runtime therefore delegates legacy body font selection to `TextMeasurer`.
- Stack v7 Windows host accepts only `fontID == "body"`, nil metadata, nil line limit, then unconditionally sends `fontFamily: "Segoe UI"`, `fontSize: 16`, `lineHeight: 24` through ABI 0.6: `stack-overlay-centered-execution-v7/package/Sources/FactoryProbe/main.swift:19-29`.
- Actual Windows record reports `FACTORY_MEASURE text=+ proposedDIP=48.0 widthPX=27.363281 heightPX=60.0 lines=1 scale=2.5`, equal to `10.9453125 × 24` DIP: `root-execution/stack-overlay-native-capture-r2/actual-native-r1/files/native/count1-r1/native-01/host.stdout.txt:3`.
- Actual Mac typography record reports bare `+` line rect `8.1123046875 × 16` DIP, run ascent `12.568359375`, descent `2.7421875`, leading `0.689453125`, with provider metadata unavailable through public `TextRenderer`: `root-execution/stack-overlay-typography-v6-mac-r1/observation.json`.

Attribution: runtime correctly preserves legacy body identity & nil metadata; Windows host fills missing provider policy with fixed Segoe UI 16/24. This host choice yields observed 24-DIP line height versus Mac 16-DIP line rect & wider glyph. Centering or coordinate changes cannot correct typography. Smallest legitimate correction is shared factory host default-font resolution using measured Windows default family, point size, weight, & line metrics through existing ABI; preserve explicit metadata paths & fail closed when provider selection is not observed. No runtime, renderer, witness, or coordinate edit is justified by current evidence.
