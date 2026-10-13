# swiftui.binding: measured SwiftUI facts (macOS 27, SR1 round 3 lane B)

Measured with an offscreen `NSHostingView` in a borderless window ordered to (-30000, -30000) in an accessory-policy app, synthetic `NSEvent` clicks sent with `NSWindow.sendEvent`. No screen, no focus, no TCC.

| Fact | Value |
|---|---|
| `Binding(get:set:)` with a one-argument setter | works as before |
| `Binding(get:set:)` with a `(Value, Transaction)` setter | the setter gets the transaction **the binding carries**: `Transaction()` (animation nil, `disablesAnimations` false) by default |
| Setter called inside `withAnimation(.easeIn) { }` or `withTransaction(Transaction(animation: nil)) { }` | still sees animation nil: the ambient transaction is not passed |
| `binding.transaction(t)` | the setter sees `t` (animation, `disablesAnimations`) |
| `binding.animation(a)` / `binding.animation()` | the setter sees `Transaction(animation: a)` / `.default` |
| `binding.transaction(t1).transaction(t2)` | `t2` replaces `t1` (no merge) |
| `Binding.constant(v)` | writes are ignored, reads return `v`; a `Toggle(isOn: .constant(true))` keeps its state when clicked |
| derived `Binding(get: { count > 0 }, set: { count = $0 ? 1 : 0 })` on a Toggle | a click flips the derived value and writes `count` through the setter |
| `$state` (State.projectedValue) | a plain read/write binding on the State |

Product: `Transaction`, the two `Binding.init(get:set:)` overloads, `Binding.constant`, `.transaction(_:)`, `.animation(_:)` (`State.swift`); tests `BindingTransactionTests`.
Cases: `derived-toggle-v1` (two switches, a swatch that encodes `count == 3`, a text), `constant-v1` (on and off), `setter-transaction-v1` (twelve squares, each one setter observation).
