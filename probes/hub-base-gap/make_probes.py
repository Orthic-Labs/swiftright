#!/usr/bin/env python3
"""Regenerate Sources/<id>/Probe.swift and Package.swift for the hub-base gap check (docs/probes/hub-base-gap-check.md).
One module per probe so one failure never hides another. Package.swift keeps the @@PRODUCT_STAGE@@ token; run.ps1 / run-mac.sh substitute it."""
from pathlib import Path
HEAD = """#if os(Windows)
import SwiftRightRuntime
import Foundation
#else
import SwiftUI
#endif
import Observation

"""
P = {}
P["P01_path_stroke"] = """struct P01: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 40))
            p.addLine(to: CGPoint(x: 30, y: 10))
            p.addLine(to: CGPoint(x: 60, y: 30))
            p.closeSubpath()
        }
        .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .frame(width: 80, height: 50)
    }
}
"""
P["P02_path_addarc"] = """struct P02: View {
    var body: some View {
        Path { p in
            p.addArc(center: CGPoint(x: 30, y: 30), radius: 20, startAngle: .degrees(0), endAngle: .degrees(270), clockwise: false)
        }
        .stroke(Color.green, lineWidth: 3)
        .frame(width: 60, height: 60)
    }
}
"""
P["P03_shape_path_in"] = """struct Spark: Shape {
    var values: [Double]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        for (i, v) in values.enumerated() {
            let pt = CGPoint(x: rect.width * CGFloat(i) / CGFloat(max(values.count - 1, 1)), y: rect.height * (1 - CGFloat(v)))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        return p
    }
}
struct P03: View {
    var body: some View {
        Spark(values: [0.1, 0.5, 0.3, 0.9]).stroke(Color.red, lineWidth: 2).frame(width: 80, height: 40)
    }
}
"""
P["P04_gradient_fill"] = """struct P04: View {
    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [Color.blue, Color.clear], startPoint: .top, endPoint: .bottom))
            .frame(width: 80, height: 40)
    }
}
"""
P["P05_progress_ring"] = """struct P05: View {
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(Color.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: 60, height: 60)
    }
}
"""
P["P05b_circle_trim_stroke_width"] = """struct P05b: View {
    var body: some View { Circle().trim(from: 0, to: 0.7).stroke(Color.green, lineWidth: 6).frame(width: 60, height: 60) }
}
"""
P["P05c_rotation_effect"] = """struct P05c: View {
    var body: some View { Rectangle().fill(Color.green).frame(width: 40, height: 10).rotationEffect(.degrees(-90)) }
}
"""
P["P06_progressview"] = """struct P06: View {
    var body: some View {
        VStack {
            ProgressView(value: 0.4)
            ProgressView("Loading", value: 0.5, total: 1)
            ProgressView()
        }
    }
}
"""
P["P07_sheet_confirm"] = """struct P07: View {
    @State private var show = false
    var body: some View {
        Button("Delete") { show = true }
            .sheet(isPresented: $show) {
                VStack {
                    Text("Are you sure?")
                    Button("OK") { show = false }
                }
            }
    }
}
"""
P["P08_confirmation_dialog"] = """struct P08: View {
    @State private var show = false
    var body: some View {
        Button("Delete") { show = true }
            .confirmationDialog("Delete?", isPresented: $show, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {}
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This cannot be undone.")
            }
    }
}
"""
P["P09_searchable_list"] = """struct P09: View {
    @State private var q = ""
    var body: some View {
        List { ForEach(["a", "b", "c"], id: \\.self) { Text($0) } }
            .searchable(text: $q)
    }
}
"""
P["P09b_list_data_init"] = """struct P09b: View {
    let items = ["a", "b", "c"]
    var body: some View { List(items, id: \\.self) { Text($0) } }
}
"""
P["P10_navsplit_sidebar_selection"] = """struct P10: View {
    @State private var sel: String? = "a"
    var body: some View {
        NavigationSplitView {
            List(selection: $sel) { ForEach(["a", "b"], id: \\.self) { Text($0) } }
        } detail: {
            Text(sel ?? "none")
        }
    }
}
"""
P["P10b_list_selection_foreach"] = """struct P10b: View {
    @State private var sel: String? = "a"
    var body: some View {
        List(selection: $sel) { ForEach(["a", "b"], id: \\.self) { Text($0).tag($0) } }
    }
}
"""
P["P10c_list_data_selection_init"] = """struct P10c: View {
    @State private var sel: String? = "a"
    let items = ["a", "b"]
    var body: some View { List(items, id: \\.self, selection: $sel) { Text($0) } }
}
"""
P["P11_navstack"] = """struct P11: View {
    var body: some View {
        NavigationStack {
            NavigationLink("Open") { Text("Detail") }
                .navigationTitle("Home")
        }
    }
}
"""
P["P12_toolbar_item"] = """struct P12: View {
    var body: some View {
        NavigationStack {
            Text("x")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Button("Add") {} }
                }
        }
    }
}
"""
P["P13_task_asyncstream"] = """struct P13: View {
    @State private var n = 0
    var body: some View {
        Text("\\(n)")
            .task {
                let s = AsyncStream<Int> { c in c.yield(1); c.yield(2); c.finish() }
                for await v in s { n = v }
            }
    }
}
"""
P["P14_observable_state"] = """@Observable final class P14Model { var count = 0 }
struct P14: View {
    @State private var m = P14Model()
    var body: some View { Button("n=\\(m.count)") { m.count += 1 } }
}
"""
P["P14b_bindable"] = """@Observable final class P14bModel { var name = "" }
struct P14b: View {
    @State private var m = P14bModel()
    var body: some View {
        @Bindable var b = m
        return TextField("Name", text: $b.name)
    }
}
"""
P["P15_form_section"] = """struct P15: View {
    @State private var on = true
    var body: some View {
        Form {
            Section("General") { Toggle("Enabled", isOn: $on) }
            Section(header: Text("More")) { Text("x") }
        }
    }
}
"""
P["P16_picker"] = """struct P16: View {
    @State private var s = "a"
    var body: some View {
        Picker("Mode", selection: $s) {
            Text("A").tag("a")
            Text("B").tag("b")
        }
    }
}
"""
P["P17_slider"] = """struct P17: View {
    @State private var v = 0.5
    var body: some View { Slider(value: $v, in: 0...1) }
}
"""
P["P18_menu"] = """struct P18: View {
    var body: some View {
        Menu("Actions") {
            Button("One") {}
            Divider()
            Button("Two") {}
        }
    }
}
"""
P["P19_divider_spacer"] = """struct P19: View {
    var body: some View {
        VStack {
            HStack { Text("a"); Spacer(); Text("b") }
            Divider()
            Spacer()
        }
    }
}
"""
P["P20_lazyvstack"] = """struct P20: View {
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) { ForEach(0..<20, id: \\.self) { Text("\\($0)") } }
        }
    }
}
"""
P["P21_grid"] = """struct P21: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            GridRow { Text("a"); Text("b") }
            GridRow { Text("c"); Text("d") }
        }
    }
}
"""
P["P22_clipshape"] = """struct P22: View {
    var body: some View {
        VStack {
            Color.red.frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
            Color.blue.frame(width: 40, height: 40).clipShape(Circle())
        }
    }
}
"""
P["P23_offset"] = """struct P23: View {
    var body: some View { Text("x").offset(x: 4, y: 2) }
}
"""
P["P24_scaleeffect"] = """struct P24: View {
    var body: some View {
        VStack {
            Circle().frame(width: 20, height: 20).scaleEffect(1.2)
            Circle().frame(width: 20, height: 20).scaleEffect(x: 1.1, y: 0.9, anchor: .topLeading)
        }
    }
}
"""
P["P25_background_view"] = """struct P25: View {
    var body: some View {
        Text("x").padding(4).background(RoundedRectangle(cornerRadius: 4).fill(Color.blue))
    }
}
"""
P["P26_background_closure"] = """struct P26: View {
    var body: some View {
        Text("x").padding(4).background { RoundedRectangle(cornerRadius: 4).fill(Color.blue) }
    }
}
"""
P["P27_onhover"] = """struct P27: View {
    @State private var hot = false
    var body: some View {
        Text(hot ? "hot" : "cold").onHover { hot = $0 }
    }
}
"""
root = Path(__file__).parent
for name, body in P.items():
    d = root / "Sources" / name
    d.mkdir(parents=True, exist_ok=True)
    (d / "Probe.swift").write_text(HEAD + body)
targets = ",\n".join(f'    .target(name: "{n}", dependencies: [.product(name: "SwiftRightRuntime", package: "fresh-runtime")])' for n in P)
(root / "Package.swift").write_text(f"""// swift-tools-version:6.0
import PackageDescription
// Generated by make_probes.py. One library target per candidate API; the runtime is the staged fresh-runtime (token replaced by run.ps1).
let package = Package(name: "HubBaseGap",
  dependencies: [.package(name: "fresh-runtime", path: "@@PRODUCT_STAGE@@\\\\probes\\\\sr0-s\\\\fresh-runtime")],
  targets: [
{targets}
  ], swiftLanguageModes: [.v5])
""")
(root / "targets.txt").write_text("\n".join(P) + "\n")
print(len(P), "probes")
