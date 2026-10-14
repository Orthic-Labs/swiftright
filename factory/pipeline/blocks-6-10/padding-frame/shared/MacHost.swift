import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Mac capture host for the padding-frame block: offscreen ImageRenderer at scale 2.5 of the case witness centred in a 320x240 pt white
// canvas (800x600 px), the same viewport the Windows host captures. Flags: --plain --scale S --png FILE (pair.py "png mode").
func value(_ key: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

@main
struct CaptureHost {
    @MainActor static func main() throws {
        let scale = Double(value("--scale") ?? "2.5") ?? 2.5
        let content = ZStack(alignment: .center) { @@WITNESS@@.environment(\.colorScheme, .light) }
            .frame(width: 320, height: 240, alignment: .center).background(Color.white)
        ScalePin.reportRenderer(scale: scale)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.cgImage, let path = value("--png"),
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw NSError(domain: "PaddingFrameHost", code: 1, userInfo: [NSLocalizedDescriptionKey: "no image or --png missing"])
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "PaddingFrameHost", code: 2) }
        print("OBSERVED \(image.width)x\(image.height)")
    }
}
