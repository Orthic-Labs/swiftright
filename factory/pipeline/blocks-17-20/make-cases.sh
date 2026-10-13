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

mk swiftui.color-scheme/semantic-colours-dark-v1 Witness_cs_semantic_dark "struct Witness_cs_semantic_dark: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Rectangle().fill(.primary).frame(width: 40, height: 20)
                    Rectangle().fill(.secondary).frame(width: 40, height: 20)
                    Rectangle().fill(Color.accentColor).frame(width: 40, height: 20)
                    ZStack { Rectangle().fill(Color.red); Rectangle().fill(.background).frame(width: 24, height: 12) }.frame(width: 40, height: 20)
                }
                HStack(spacing: 4) {
                    Rectangle().fill(Color.red).frame(width: 24, height: 20)
                    Rectangle().fill(Color.orange).frame(width: 24, height: 20)
                    Rectangle().fill(Color.yellow).frame(width: 24, height: 20)
                    Rectangle().fill(Color.green).frame(width: 24, height: 20)
                    Rectangle().fill(Color.blue).frame(width: 24, height: 20)
                    Rectangle().fill(Color.purple).frame(width: 24, height: 20)
                    Rectangle().fill(Color.pink).frame(width: 24, height: 20)
                    Rectangle().fill(Color.gray).frame(width: 24, height: 20)
                }
                HStack(spacing: 4) {
                    Rectangle().fill(Color.white).frame(width: 40, height: 20)
                    Rectangle().fill(Color.black).frame(width: 40, height: 20)
                }
            }
            .padding(8)
        }
        .frame(width: 320, height: 240)
        .environment(\\.colorScheme, .dark)
    }
}" $DARK

ENVREAD='struct Witness_cs_probe: View {
    @Environment(\.colorScheme) var scheme
    var body: some View {
        Rectangle().fill(scheme == .dark ? Color.red : Color.blue).frame(width: 40, height: 20)
    }
}
'
mk swiftui.color-scheme/environment-read-v1 Witness_cs_env_read "$ENVREAD
struct Witness_cs_env_read: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            VStack(alignment: .leading, spacing: 4) {
                Witness_cs_probe()
                Witness_cs_probe().environment(\\.colorScheme, .dark)
                Witness_cs_probe().environment(\\.colorScheme, .dark).environment(\\.colorScheme, .light)
                VStack(alignment: .leading, spacing: 2) { Witness_cs_probe(); Witness_cs_probe().environment(\\.colorScheme, .light) }.environment(\\.colorScheme, .dark)
                HStack(spacing: 4) { Witness_cs_probe(); Witness_cs_probe().environment(\\.colorScheme, .dark) }
            }
            .padding(8)
        }
        .frame(width: 320, height: 240)
    }
}" --appearance aqua --scheme light

mk swiftui.color-scheme/preferred-dark-v1 Witness_cs_preferred_dark "$ENVREAD
struct Witness_cs_preferred_dark: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle().fill(.background)
            VStack(alignment: .leading, spacing: 4) {
                Witness_cs_probe()
                Rectangle().fill(.primary).frame(width: 40, height: 20)
                Rectangle().fill(Color.accentColor).frame(width: 40, height: 20)
            }
            .padding(8)
        }
        .frame(width: 320, height: 240)
        .preferredColorScheme(.dark)
    }
}" --appearance none --scheme none

# ---- block 17 (swiftui.alert): semantic only (native chrome); pixels are reported, never gate ----
# alert_case <case-dir> <witness-type> <body> <mac display index to press> <windows step: button name | ESC> [dialog count after]
alert_case() {
  d=$1; t=$2; b=$3; press=$4; how=$5
  mk "$d" "$t" "$b" --alert-host
  if [ "$how" = "ESC" ]; then act='{"op":"key","key":"Escape","target":"dialog"}'; else act="{\"op\":\"invoke\",\"target\":\"dialog\",\"name\":\"$how\"}"; fi
  cat > "$d/pair.json" <<JSON
{"semanticGate": {"fields": ["role", "name", "enabled", "default", "dialogTitle", "count", "order"], "scope": "all", "pixels": "report-only", "phases": ["open", ""], "dialogs": {"count": {"open": 1, "": 0}}},
 "macArgs": ["--press", "$press"],
 "steps": [{"op": "wait", "ms": 1200}, {"op": "dump", "label": "open"}, $act, {"op": "wait", "ms": 800}]}
JSON
}
STATUS='Rectangle().fill(done ? Color.green : Color.red).frame(width: 80, height: 40)
            Text(done ? "Done" : "Waiting")'
alert_view() { # <type> <modifier chain on the VStack>
  cat <<SW
struct $1: View {
    @State private var show = true
    @State private var done = false
    var body: some View {
        VStack(spacing: 8) {
            $STATUS
        }
        .frame(width: 320, height: 240)
$2
    }
}
SW
}
alert_case swiftui.alert/ok-v1 Witness_alert_ok "$(alert_view Witness_alert_ok '        .alert("Saved", isPresented: $show) {
            Button("OK") { done = true }
        } message: {
            Text("Your changes were saved.")
        }')" 0 OK
alert_case swiftui.alert/no-actions-v1 Witness_alert_no_actions "$(alert_view Witness_alert_no_actions '        .alert("Heads up", isPresented: $show) {
        } message: {
            Text("Nothing to choose.")
        }')" 0 OK
alert_case swiftui.alert/confirm-delete-v1 Witness_alert_confirm_delete "$(alert_view Witness_alert_confirm_delete '        .confirmationDialog("Delete item?", isPresented: $show, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { done = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }')" 0 Delete
alert_case swiftui.alert/confirm-cancel-v1 Witness_alert_confirm_cancel "$(alert_view Witness_alert_confirm_cancel '        .confirmationDialog("Delete item?", isPresented: $show, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { done = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }')" 1 Cancel
alert_case swiftui.alert/confirm-escape-v1 Witness_alert_confirm_escape "$(alert_view Witness_alert_confirm_escape '        .confirmationDialog("Delete item?", isPresented: $show, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { done = true }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This cannot be undone.")
        }')" 1 ESC
alert_case swiftui.alert/three-buttons-v1 Witness_alert_three "$(alert_view Witness_alert_three '        .alert("Choose", isPresented: $show) {
            Button("First") { }
            Button("Cancel", role: .cancel) { }
            Button("Third") { done = true }
        } message: {
            Text("Pick one.")
        }')" 2 Third
alert_case swiftui.alert/auto-cancel-v1 Witness_alert_auto_cancel "$(alert_view Witness_alert_auto_cancel '        .confirmationDialog("Share", isPresented: $show) {
            Button("Copy link") { done = true }
            Button("Email") { }
        }')" 2 Cancel
