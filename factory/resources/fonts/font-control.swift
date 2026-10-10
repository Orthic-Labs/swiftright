import AppKit
import CoreText
import Foundation
import SwiftUI

@main
struct BundledFontControl {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fputs("usage: font-control FONT.ttf OUTPUT.png\n", stderr)
            exit(2)
        }
        let fontURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
        let imageURL = URL(fileURLWithPath: CommandLine.arguments[2]).standardizedFileURL

        var registrationError: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &registrationError)
        if !registered {
            let details = registrationError?.takeRetainedValue().localizedDescription ?? "unknown registration failure"
            throw NSError(domain: "BundledFontControl", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: details])
        }

        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first,
              let postScriptName = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else {
            throw NSError(domain: "BundledFontControl", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "font descriptor or PostScript name unavailable"])
        }

        let coreTextFont = CTFontCreateWithName(postScriptName as CFString, 18, nil)
        let metrics: [String: Double] = [
            "ascent": Double(CTFontGetAscent(coreTextFont)),
            "descent": Double(CTFontGetDescent(coreTextFont)),
            "leading": Double(CTFontGetLeading(coreTextFont)),
            "capHeight": Double(CTFontGetCapHeight(coreTextFont)),
            "xHeight": Double(CTFontGetXHeight(coreTextFont)),
            "unitsPerEm": Double(CTFontGetUnitsPerEm(coreTextFont)),
        ]

        let view = VStack(alignment: .leading, spacing: 8) {
            Text("Tinos bundled font")
                .font(.custom(postScriptName, size: 24))
            Text("Ag 0123456789 — SwiftRight")
                .font(.custom(postScriptName, size: 18))
        }
        .padding(16)
        .background(Color.white)
        .foregroundStyle(Color.black)
        .fixedSize()

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            throw NSError(domain: "BundledFontControl", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "ImageRenderer returned no CGImage"])
        }
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "BundledFontControl", code: 4,
                          userInfo: [NSLocalizedDescriptionKey: "PNG encoding failed"])
        }
        try FileManager.default.createDirectory(at: imageURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try png.write(to: imageURL, options: .atomic)

        let report: [String: Any] = [
            "status": "observed",
            "fontPath": fontURL.path,
            "registrationScope": "process",
            "registered": registered,
            "postScriptName": postScriptName,
            "fullName": CTFontCopyFullName(coreTextFont) as String,
            "metricsAt18pt": metrics,
            "imageRenderer": ["widthPixels": image.width, "heightPixels": image.height, "scale": 2],
            "pngPath": imageURL.path,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
