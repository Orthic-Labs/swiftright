import AppKit
import SwiftUI
let S: CGFloat = 2.5
final class OW: NSWindow {
    @objc(hasKeyAppearance) func hk() -> Bool { true }
    override var backingScaleFactor: CGFloat { S }
    override var canBecomeKey: Bool { true }
}
@MainActor func tableOf(_ v: NSView) -> NSTableView? { if let t = v as? NSTableView { return t }; for s in v.subviews { if let f = tableOf(s) { return f } }; return nil }
@MainActor func shot(_ name: String, _ v: AnyView, steps: (NSTableView, NSWindow) -> Void = { _, _ in }) {
    let host = NSHostingView(rootView: AnyView(ZStack { v }.frame(width: 320, height: 240).background(Color.white)))
    host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
    let w = OW(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    w.appearance = NSAppearance(named: .aqua); w.contentView = host
    host.layoutSubtreeIfNeeded(); RunLoop.current.run(until: Date().addingTimeInterval(0.4)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    if let tv = tableOf(host) { steps(tv, w); RunLoop.current.run(until: Date().addingTimeInterval(0.3)); host.layoutSubtreeIfNeeded(); host.displayIfNeeded() 
        print(name, "rows", tv.numberOfRows, (0..<tv.numberOfRows).map { "\(tv.rect(ofRow: $0).origin.y)+\(tv.rect(ofRow: $0).height)" }.joined(separator: " "), "style", tv.style.rawValue, "sel", Array(tv.selectedRowIndexes)) }
    let fit = NSHostingView(rootView: v).fittingSize
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = host.bounds.size
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!; host.displayIgnoringOpacity(host.bounds, in: ctx)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "out3/\(name).png"))
    print(name, "fitting", fit)
}
func key(_ w: NSWindow, _ code: UInt16, _ ch: Int) -> NSEvent { NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, characters: String(UnicodeScalar(ch)!), charactersIgnoringModifiers: String(UnicodeScalar(ch)!), isARepeat: false, keyCode: code)! }
@MainActor func down(_ tv: NSTableView, _ w: NSWindow) { _ = w.makeFirstResponder(tv); tv.keyDown(with: key(w, 125, Int(NSDownArrowFunctionKey))) }
struct Rows<S: View>: View { let sel: Binding<Int?>; let content: S; var body: some View { List(selection: sel) { content } } }
struct Five: View { @State var sel: Int? = nil; var body: some View { List(selection: $sel) { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").tag(i) } }.frame(width: 200, height: 150) } }
struct Unframed: View { @State var sel: Int? = nil; var body: some View { List(selection: $sel) { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").tag(i) } } } }
struct NoSel: View { var body: some View { List { ForEach(0..<5, id: \.self) { i in Text("Row \(i)") } }.frame(width: 200, height: 150) } }
struct Tall: View { var body: some View { List { Rectangle().fill(Color.red).frame(width: 30, height: 10); Rectangle().fill(Color.red).frame(width: 30, height: 40); Rectangle().fill(Color.red).frame(width: 30, height: 24) }.frame(width: 200, height: 150) } }
struct Many: View { @State var sel: Int? = nil; var body: some View { List(selection: $sel) { ForEach(0..<20, id: \.self) { i in Text("Row \(i)").tag(i) } }.frame(width: 200, height: 150) } }
struct Plain: View { var body: some View { List { ForEach(0..<5, id: \.self) { i in Text("Row \(i)") } }.listStyle(.plain).frame(width: 200, height: 150) } }
struct Sidebar: View { var body: some View { List { ForEach(0..<5, id: \.self) { i in Text("Row \(i)") } }.listStyle(.sidebar).frame(width: 200, height: 150) } }
struct Inset: View { var body: some View { List { ForEach(0..<5, id: \.self) { i in Text("Row \(i)") } }.listStyle(.inset).frame(width: 200, height: 150) } }
struct Mixed: View { @State var sel: Set<Int> = []; var body: some View { List(selection: $sel) { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").tag(i) } }.frame(width: 200, height: 150) } }
struct Empty: View { var body: some View { List { }.frame(width: 200, height: 150) } }
struct OneRow: View { var body: some View { List { Text("Only") }.frame(width: 200, height: 150) } }
struct Dis: View { @State var sel: Int? = 1; var body: some View { List(selection: $sel) { ForEach(0..<5, id: \.self) { i in Text("Row \(i)").tag(i) } }.frame(width: 200, height: 150).disabled(true) } }
@main struct P { @MainActor static func main() {
    _ = NSApplication.shared
    shot("five", AnyView(Five()))
    shot("five-sel2", AnyView(Five()), steps: { tv, w in down(tv, w); down(tv, w); down(tv, w) })
    shot("unframed", AnyView(Unframed()))
    shot("nosel", AnyView(NoSel()))
    shot("tall", AnyView(Tall()))
    shot("many", AnyView(Many()), steps: { tv, w in down(tv, w) })
    shot("plain", AnyView(Plain()))
    shot("sidebar", AnyView(Sidebar()))
    shot("inset", AnyView(Inset()))
    shot("multi-sel", AnyView(Mixed()), steps: { tv, w in down(tv, w); tv.selectRowIndexes([1,3], byExtendingSelection: false) })
    shot("empty", AnyView(Empty()))
    shot("onerow", AnyView(OneRow()))
    shot("sel-last", AnyView(Five()), steps: { tv, w in tv.selectRowIndexes([4], byExtendingSelection: false) })
    shot("disabled-sel", AnyView(Dis()))
}}
