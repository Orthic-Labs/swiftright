# Custom Layout RTL width32 source packet v5

Source-only variant from v4 for recipe case `swiftui.custom-layout.recipe/case/6f604b656b080f22`. It preserves original two-child `Witness_custom_layout` algorithm, child frames 12x10 and 16x14, spacing 4, and changes only recipe inputs: `child-count=2`, `proposal-width=32`, `layout-direction=rightToLeft`. Witness SHA256 is `sha256:4986259c19269c4caf2331171de66f0c98a992821f1919eadca970e27b6131c5` for both Windows and Mac sources.

Runtime remains `37429120e7dd4e060ecf1a58a92ae3a7f4d2b12b`, renderer tuple11, ABI `0.6`, shared mapper and centered host correction copied unchanged from v4. The `.environment(\.layoutDirection, .rightToLeft)` modifier remains in original witness source. Current runtime applies environment modifiers through `Graph.evaluate`; `EnvironmentValues.layoutDirection` is available, while `WitnessMeasuredLayout` intentionally does not read it, so this recipe tuple tests delivery without host-side child reversal or injected coordinates.

Packet is source-ready only. Root must regenerate bounded compile/final requests then perform matched Mac/Windows Count1 and Count20 captures. No parity or qualification claim is made.
