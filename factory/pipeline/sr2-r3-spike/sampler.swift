import SwiftUI
import AppKit

nonisolated(unsafe) var done = false
let specs: [(String, Animation)] = [
    ("default", .default),
    ("spring(duration:0.5,bounce:0)", .spring(duration: 0.5, bounce: 0)),
    ("spring(duration:0.35,bounce:0)", .spring(duration: 0.35, bounce: 0)),
    ("spring(duration:0.5,bounce:0.3)", .spring(duration: 0.5, bounce: 0.3)),
    ("spring(duration:0.5,bounce:-0.3)", .spring(duration: 0.5, bounce: -0.3)),
    ("spring(response:0.4,dampingFraction:0.7)", .spring(response: 0.4, dampingFraction: 0.7)),
    ("spring(response:0.55,dampingFraction:0.825)", .spring(response: 0.55, dampingFraction: 0.825)),
    ("snappy", .snappy), ("bouncy", .bouncy), ("smooth", .smooth),
    ("interpolatingSpring(stiffness:170,damping:15)", .interpolatingSpring(stiffness: 170, damping: 15)),
]
struct Sampler: CustomAnimation {
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        guard !done, let fresh = context as? AnimationContext<Double> else { return nil }
        done = true
        var lines: [String] = []
        for (name, a) in specs {
            for step in [0.0125, 0.001, 0.1] {
                var c = fresh; var vals: [String] = []
                var t = 0.0
                while t <= 2.0 + 1e-9 {
                    if let v = a.animate(value: 1.0, time: t, context: &c) { vals.append(String(format: "%.7f", v)) } else { vals.append("null"); break }
                    t += step
                }
                lines.append("{\"name\":\"\(name)\",\"step\":\(step),\"v\":[\(vals.joined(separator: ","))]}")
            }
            // hold test: dense 0.25 ms around 0..0.02 from fresh
            var c = fresh; var vals: [String] = []
            for i in 0...80 { if let v = a.animate(value: 1.0, time: Double(i) * 0.00025, context: &c) { vals.append(String(format: "%.7f", v)) } }
            lines.append("{\"name\":\"\(name)\",\"step\":0.00025,\"v\":[\(vals.joined(separator: ","))]}")
        }
        try! (lines.joined(separator: "\n") + "\n").write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return nil
    }
}
struct Bar: Shape {
    var amount: Double
    var animatableData: Double { get { amount } set { amount = newValue } }
    func path(in r: CGRect) -> Path { Path(CGRect(x: 0, y: 0, width: 10 + amount, height: 10)) }
}
struct Probe: View {
    @State var on = false
    var body: some View {
        Bar(amount: on ? 10 : 0).fill(Color.red)
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { withAnimation(Animation(Sampler())) { on = true } } }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 20), styleMask: [.borderless], backing: .buffered, defer: false)
w.alphaValue = 0; w.ignoresMouseEvents = true; w.level = .normal
w.contentView = NSHostingView(rootView: Probe())
w.orderBack(nil)
DispatchQueue.main.asyncAfter(deadline: .now() + 10) { FileHandle.standardError.write("timeout\n".data(using: .utf8)!); exit(2) }
app.run()
