#!/bin/sh
# Creates (or re-stamps) every blocks-6-10 case: Witness.swift (the single source for both platforms), the Windows package host and the Mac host.
# Run from this directory. Witness text lives here, once per case.
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
toggle_hidden() { # <initial> <modifier suffix> <type> [style]
  cat <<SW
struct $3: View {
    @State private var enabled = $1
    var body: some View {
        Toggle("Enabled", isOn: \$enabled).labelsHidden().toggleStyle(.${4:-switch})$2
    }
}
SW
}
mk swiftui.toggle/switch-on-v1  Witness_toggle_switch_on  "$(toggle_hidden true '' Witness_toggle_switch_on)"
mk swiftui.toggle/switch-off-v1 Witness_toggle_switch_off "$(toggle_hidden false '' Witness_toggle_switch_off)"
mk swiftui.toggle/switch-labelled-on-v1 Witness_toggle_labelled_on "struct Witness_toggle_labelled_on: View {
    @State private var enabled = true
    var body: some View {
        Toggle(\"Enabled\", isOn: \$enabled).toggleStyle(.switch)
    }
}"
mk swiftui.disabled/toggle-on-disabled-v1  Witness_disabled_toggle_on  "$(toggle_hidden true '.disabled(true)' Witness_disabled_toggle_on)"
mk swiftui.disabled/toggle-off-disabled-v1 Witness_disabled_toggle_off "$(toggle_hidden false '.disabled(true)' Witness_disabled_toggle_off)"
mk swiftui.toggle/checkbox-on-v1  Witness_toggle_automatic_on  "$(toggle_hidden true '' Witness_toggle_automatic_on automatic)"
mk swiftui.toggle/checkbox-off-v1 Witness_toggle_automatic_off "$(toggle_hidden false '' Witness_toggle_automatic_off automatic)"
mk swiftui.toggle/checkbox-labelled-on-v1 Witness_toggle_checkbox_labelled_on "struct Witness_toggle_checkbox_labelled_on: View {
    @State private var enabled = true
    var body: some View {
        Toggle(\"Enabled\", isOn: \$enabled).toggleStyle(.automatic)
    }
}"
mk swiftui.disabled/checkbox-on-disabled-v1  Witness_disabled_automatic_on  "$(toggle_hidden true '.disabled(true)' Witness_disabled_automatic_on automatic)"
mk swiftui.disabled/checkbox-off-disabled-v1 Witness_disabled_automatic_off "$(toggle_hidden false '.disabled(true)' Witness_disabled_automatic_off automatic)"
