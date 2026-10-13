#!/bin/sh
# Lane B (text input) cases: blocks 12-15. Same stamping as make-cases.sh (Witness.swift once per case, Windows package + Mac host).
set -e
cd "$(dirname "$0")"
W=../pilot-delivery-five-v1/shared-windows-host/stamp-case.py; M=shared-mac-host/stamp-mac.py
HEADER='#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif
'
mk() { # <case-dir> <witness-type> <body>
  d=$1; mkdir -p "$d/package/Sources/FactoryProbe"
  printf '%s\n%s\n' "$HEADER" "$3" > "$d/package/Sources/FactoryProbe/Witness.swift"
  python3 $W "$d" --witness "$2()" >/dev/null
  python3 $M "$d" --witness "$2()" >/dev/null
  echo "stamped $d"
}

# --- block 12 swiftui.binding
mk swiftui.binding/derived-toggle-v1 Witness_binding_derived "struct Witness_binding_derived: View {
    @State private var count = 3
    @State private var flag = false
    var body: some View {
        let derived = Binding<Bool>(get: { count > 0 }, set: { count = \$0 ? 1 : 0 })
        VStack(alignment: .leading, spacing: 8) {
            Toggle(\"Derived\", isOn: derived).labelsHidden().toggleStyle(.switch)
            Toggle(\"Projected\", isOn: \$flag).labelsHidden().toggleStyle(.switch)
            HStack(spacing: 8) {
                Rectangle().fill(count == 3 ? Color.green : Color.red).frame(width: 20, height: 20)
                Text(\"count: \\(count)\").frame(height: 20, alignment: .topLeading)
            }
        }
    }
}"
mk swiftui.binding/constant-v1 Witness_binding_constant "struct Witness_binding_constant: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(\"On\", isOn: .constant(true)).labelsHidden().toggleStyle(.switch)
            Toggle(\"Off\", isOn: .constant(false)).labelsHidden().toggleStyle(.switch)
        }
    }
}"
mk swiftui.binding/setter-transaction-v1 Witness_binding_transaction "struct Witness_binding_transaction: View {
    // Each square is one observation from the binding setter: green = true. Row 1: the setter saw an animation; row 2: it saw disablesAnimations.
    static func facts() -> [[Bool]] {
        var seen: [Transaction] = []
        let b = Binding<Int>(get: { 0 }, set: { _, t in seen.append(t) })
        b.wrappedValue = 1
        var t = Transaction(animation: .linear(duration: 0.1)); t.disablesAnimations = true
        b.transaction(t).wrappedValue = 2
        b.animation(.easeIn(duration: 0.2)).wrappedValue = 3
        b.animation().wrappedValue = 4
        b.transaction(Transaction(animation: .linear(duration: 0.1))).transaction(Transaction()).wrappedValue = 5
        let constant = Binding.constant(7)
        constant.wrappedValue = 9
        return [seen.map { \$0.animation != nil } + [constant.wrappedValue == 7], seen.map { \$0.disablesAnimations } + [seen.count == 5]]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<2, id: \\.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<6, id: \\.self) { column in
                        Rectangle().fill(Self.facts()[row][column] ? Color.green : Color.red).frame(width: 20, height: 20)
                    }
                }
            }
        }
    }
}"
