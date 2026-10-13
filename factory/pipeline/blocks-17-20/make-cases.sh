#!/bin/sh
# Creates (or re-stamps) every blocks-17-20 case: Witness.swift (the single source for both platforms), the Windows package host and the Mac host.
# Run from this directory. Witness text lives here, once per case.
set -e
cd "$(dirname "$0")"
HEADER='#if os(Windows)
import SwiftRightRuntime
#else
import SwiftUI
#endif
'
mk() { # <case-dir> <witness-type> <body> [new-case.py flags...]
  d=$1; t=$2; b=$3; shift 3
  f=$(mktemp); printf '%s\n%s\n' "$HEADER" "$b" > "$f"
  python3 new-case.py "$d" "$f" "$t()" "$@" >/dev/null
  rm -f "$f"; echo "stamped $d"
}
DARK="--appearance darkAqua --scheme dark"

# ---- block 20 (swiftui.color-scheme) ----
toggle_dark() { # <type> <initial> <style> <modifier>
  cat <<SW
struct $1: View {
    @State private var enabled = $2
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            Toggle("Enabled", isOn: \$enabled).labelsHidden().toggleStyle(.$3)$4
        }
        .frame(width: 320, height: 240)
        .environment(\\.colorScheme, .dark)
    }
}
SW
}
mk swiftui.color-scheme/switch-on-dark-v1  Witness_cs_switch_on_dark  "$(toggle_dark Witness_cs_switch_on_dark true switch)" $DARK
mk swiftui.color-scheme/switch-off-dark-v1 Witness_cs_switch_off_dark "$(toggle_dark Witness_cs_switch_off_dark false switch)" $DARK
mk swiftui.color-scheme/checkbox-on-dark-v1  Witness_cs_checkbox_on_dark  "$(toggle_dark Witness_cs_checkbox_on_dark true automatic)" $DARK
mk swiftui.color-scheme/checkbox-off-dark-v1 Witness_cs_checkbox_off_dark "$(toggle_dark Witness_cs_checkbox_off_dark false automatic)" $DARK
mk swiftui.color-scheme/switch-on-dark-disabled-v1  Witness_cs_switch_on_dark_disabled  "$(toggle_dark Witness_cs_switch_on_dark_disabled true switch '.disabled(true)')" $DARK
mk swiftui.color-scheme/switch-off-dark-disabled-v1 Witness_cs_switch_off_dark_disabled "$(toggle_dark Witness_cs_switch_off_dark_disabled false switch '.disabled(true)')" $DARK
mk swiftui.color-scheme/checkbox-on-dark-disabled-v1  Witness_cs_checkbox_on_dark_disabled  "$(toggle_dark Witness_cs_checkbox_on_dark_disabled true automatic '.disabled(true)')" $DARK
mk swiftui.color-scheme/checkbox-off-dark-disabled-v1 Witness_cs_checkbox_off_dark_disabled "$(toggle_dark Witness_cs_checkbox_off_dark_disabled false automatic '.disabled(true)')" $DARK
