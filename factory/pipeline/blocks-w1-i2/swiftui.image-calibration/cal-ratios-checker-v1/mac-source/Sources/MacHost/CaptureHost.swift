import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Mac capture host for wave 1 block I2 (images). WHY NOT the blocks-11-16 NSHostingView host: measured (docs/sr1-decisions.md G50), the NSHostingView bitmap path
// (displayIgnoringOpacity / cacheDisplay / layer.render) draws every Image.Interpolation level with the same bilinear filter, so `.none` at 3x is smooth and the four levels are
// byte-identical; ImageRenderer (SwiftUI's own renderer) honours the levels (`.none` is nearest, `.low` = `.medium`, `.high` differs). This host renders the witness with ImageRenderer
// at the capture scale into an 800 x 600 px opaque bitmap, white behind the witness. No window, nothing on any screen, no permission asked.
// usage: host --plain --scale 2.5 --png FILE

func value(_ key: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

@MainActor
func capture(_ witness: AnyView, width: CGFloat, height: CGFloat, to path: String) throws {
    let scale = Double(value("--scale") ?? "2.5") ?? 2.5
    ScalePin.reportRenderer(scale: scale)
    let root = ZStack(alignment: .center) { witness }
        .frame(width: width, height: height, alignment: .center)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    let renderer = ImageRenderer(content: root)
    renderer.scale = CGFloat(scale)
    renderer.isOpaque = true
    guard let cg = renderer.cgImage else { throw NSError(domain: "MacHost", code: 1) }
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw NSError(domain: "MacHost", code: 2) }
    CGImageDestinationAddImage(dest, cg, nil)
    guard CGImageDestinationFinalize(dest) else { throw NSError(domain: "MacHost", code: 3) }
    print("MAC_CAPTURE \(cg.width)x\(cg.height) scale=\(scale) renderer=ImageRenderer colorSpace=\(cg.colorSpace?.name as String? ?? "none") png=\(path)")
}

@main
struct MacCaptureHost {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        guard let png = value("--png") else { throw NSError(domain: "MacHost", code: 3, userInfo: [NSLocalizedDescriptionKey: "--png missing"]) }
        try capture(AnyView(Witness_i2_cal_checker()), width: 320, height: 240, to: png)
    }
}
