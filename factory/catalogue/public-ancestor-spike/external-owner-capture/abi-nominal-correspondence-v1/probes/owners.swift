import SwiftUI
let attributed: Any.Type = SwiftUICore.AttributedTextFormatting.self
let transferable: Any.Type = SwiftUICore.AttributedTextFormatting.Transferable.self
@available(macOS, unavailable)
func unavailableOwners<each C>(_ marker: repeat (each C).Type) {
  let custom: Any.Type = (any SwiftUICore.CustomHoverEffect).self
  let hoverContent: Any.Type = (any SwiftUICore.HoverEffectContent).self
  let tuple: SwiftUICore.TupleContent<repeat each C>.Type = SwiftUICore.TupleContent<repeat each C>.self
  let lineStyle: Any.Type = SwiftUICore.Text.LineStyle.self
  _ = (custom, hoverContent, tuple, lineStyle)
}
