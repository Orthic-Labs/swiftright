import AppKit
import SwiftUI

let S: CGFloat = 2.5
final class OW: NSWindow {
    @objc(hasKeyAppearance) func hk() -> Bool { true }
    override var backingScaleFactor: CGFloat { S }
}
@MainActor func shot(_ name: String, _ v: AnyView, dir: String, dark: Bool = false) {
    let root = ZStack { v }.frame(width: 320, height: 240).background(dark ? Color(white: 0.118) : Color.white).environment(\.colorScheme, dark ? .dark : .light)
    let host = NSHostingView(rootView: AnyView(root))
    host.frame = NSRect(x: 0, y: 0, width: 320, height: 240)
    let w = OW(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    if dark { w.appearance = NSAppearance(named: .darkAqua) } else { w.appearance = NSAppearance(named: .aqua) }
    w.contentView = host
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
    let fit = NSHostingView(rootView: v).fittingSize
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = host.bounds.size
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    host.displayIgnoringOpacity(host.bounds, in: ctx)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
    print("\(name) fitting \(fit.width) x \(fit.height)")
}
@main struct P { @MainActor static func main() {
    _ = NSApplication.shared
    let dir = CommandLine.arguments[1]
    shot("bordered", AnyView(Button("Run") {}.buttonStyle(.bordered)), dir: dir)
    shot("borderedProminent", AnyView(Button("Run") {}.buttonStyle(.borderedProminent)), dir: dir)
    shot("borderless", AnyView(Button("Run") {}.buttonStyle(.borderless)), dir: dir)
    shot("plain", AnyView(Button("Run") {}.buttonStyle(.plain)), dir: dir)
    shot("automatic", AnyView(Button("Run") {}), dir: dir)
    shot("bordered-dis", AnyView(Button("Run") {}.disabled(true)), dir: dir)
    shot("borderless-dis", AnyView(Button("Run") {}.buttonStyle(.borderless).disabled(true)), dir: dir)
    shot("plain-dis", AnyView(Button("Run") {}.buttonStyle(.plain).disabled(true)), dir: dir)
    shot("prominent-dis", AnyView(Button("Run") {}.buttonStyle(.borderedProminent).disabled(true)), dir: dir)
    shot("destructive", AnyView(Button("Run", role: .destructive) {}), dir: dir)
    shot("destructive-prom", AnyView(Button("Run", role: .destructive) {}.buttonStyle(.borderedProminent)), dir: dir)
    shot("destructive-borderless", AnyView(Button("Run", role: .destructive) {}.buttonStyle(.borderless)), dir: dir)
    shot("cancel-role", AnyView(Button("Run", role: .cancel) {}), dir: dir)
    shot("default-action", AnyView(Button("Run") {}.keyboardShortcut(.defaultAction)), dir: dir)
    shot("shortcut-cmdr", AnyView(Button("Run") {}.keyboardShortcut("r")), dir: dir)
    shot("cancel-action", AnyView(Button("Run") {}.keyboardShortcut(.cancelAction)), dir: dir)
    shot("bordered-dark", AnyView(Button("Run") {}), dir: dir, dark: true)
    shot("prominent-dark", AnyView(Button("Run") {}.buttonStyle(.borderedProminent)), dir: dir, dark: true)
    shot("label-view", AnyView(Button(action: {}) { Rectangle().fill(Color.red).frame(width: 30, height: 10) }.buttonStyle(.borderedProminent)), dir: dir)
    shot("label-view-borderless", AnyView(Button(action: {}) { Rectangle().fill(Color.red).frame(width: 30, height: 10) }.buttonStyle(.borderless)), dir: dir)
    shot("label-view-plain", AnyView(Button(action: {}) { Rectangle().fill(Color.red).frame(width: 30, height: 10) }.buttonStyle(.plain)), dir: dir)
    shot("label-view-bordered", AnyView(Button(action: {}) { Rectangle().fill(Color.red).frame(width: 30, height: 10) }.buttonStyle(.bordered)), dir: dir)
    shot("tint-prominent", AnyView(Button("Run") {}.buttonStyle(.borderedProminent).tint(.green)), dir: dir)
    shot("tint-bordered", AnyView(Button("Run") {}.buttonStyle(.bordered).tint(.green)), dir: dir)
    shot("text-colour-borderless", AnyView(Button("Run") {}.buttonStyle(.borderless).foregroundStyle(.red)), dir: dir)
    shot("controlsize-large", AnyView(Button("Run") {}.controlSize(.large)), dir: dir)
    shot("controlsize-small", AnyView(Button("Run") {}.controlSize(.small)), dir: dir)
}}
