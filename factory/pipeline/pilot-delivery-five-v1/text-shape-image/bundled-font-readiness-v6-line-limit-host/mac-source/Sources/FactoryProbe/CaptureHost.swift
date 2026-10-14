import AppKit
import CoreGraphics
import CoreText
import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Mac reference host for the Tinos bundled-font witness (pair.py png mode):
//   host --plain --scale 2.5 --png FILE [--font-resource PATH]
// Renders the unchanged witness at 320x240 DIP, top-leading, white background, as an 800x600 PNG at scale 2.5.
// Tinos is registered process-scope through CoreText from the SAME bytes the Windows renderer registers
// (SHA-256 pinned below). The font file is read from the internal-disk cache, never from /Volumes/D at run time.

let tinosSHA256 = "sha256:60a0e8ef0c04dd5dd69ffe91025fa2ae5836cbd35600a82ba031977557e2cb61"
let tinosPostScript = "Tinos-Regular"

func value(_ key: String) -> String? {
    guard let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[i + 1]
}

@MainActor
func content() -> AnyView {
    AnyView(ZStack(alignment: .topLeading) { Witness_tinos_bundled_text_pilot().environment(\.colorScheme, .light) }
        .frame(width: 320, height: 240, alignment: .topLeading).background(Color.white))
}

@main
struct CaptureHost {
    @MainActor static func main() throws {
        let fontPath = value("--font-resource")
            ?? (NSHomeDirectory() + "/Library/Caches/SwiftRightFactory/sr1/Tinos-Regular.ttf")
        let url = URL(fileURLWithPath: fontPath).standardizedFileURL.resolvingSymlinksInPath()
        let data = try Data(contentsOf: url)
        let hash = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == tinosSHA256 else { throw NSError(domain: "TinosHash", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(hash) at \(url.path)"]) }
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) else {
            throw error?.takeRetainedValue() as Error? ?? NSError(domain: "TinosRegister", code: 2)
        }
        defer { CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil) }
        let font = CTFontCreateWithName(tinosPostScript as CFString, 18, nil)
        guard CTFontCopyPostScriptName(font) as String == tinosPostScript,
              let descriptorURL = CTFontDescriptorCopyAttribute(CTFontCopyFontDescriptor(font), kCTFontURLAttribute) as? URL,
              descriptorURL.standardizedFileURL.resolvingSymlinksInPath() == url else {
            throw NSError(domain: "TinosResolve", code: 3)
        }
        let scale = Double(value("--scale") ?? "1") ?? 1
        ScalePin.reportRenderer(scale: scale)
        let renderer = ImageRenderer(content: content())
        renderer.scale = scale
        guard let image = renderer.cgImage, let path = value("--png") else { throw NSError(domain: "TinosRender", code: 4) }
        guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw NSError(domain: "TinosRender", code: 5) }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw NSError(domain: "TinosRender", code: 6) }
        print("TINOS_MAC font=\(tinosPostScript) hash=\(hash) descriptor=\(descriptorURL.path) image=\(image.width)x\(image.height) scale=\(scale)")
    }
}
