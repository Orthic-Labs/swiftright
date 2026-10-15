#!/usr/bin/env python3
"""usage: patch_host.py <SwiftRightHost/Sources/SwiftRightHost dir of the COPIED stage> : probe-only relaxation of the host's text policy.
Product policy (BridgeTextMeasurer.swift:83-100): only the body font and bundled Font.custom families are measured; anything else
(Font.system(size:weight:), the text styles, a Font.custom that is not bundled) and any lineLimit other than 1 throws TextMeasureError.
P1 TextMeasureError.description recursed into itself (`"TextMeasure: \\(self)"`): the first failure overflowed the stack. Fixed by a switch.
P2 system(size,weight) and the text styles measure in the body family (Segoe UI) at that size; an unbundled Font.custom (Tanker) falls back
   to the body family at its point size; lineLimit n != 1 wraps without a cap. Approximations: no bundled face, so glyph shapes and widths differ."""
import sys, re, pathlib
d = pathlib.Path(sys.argv[1]); p = d / 'BridgeTextMeasurer.swift'; s = p.read_text()
s = s.replace('public var description: String { "TextMeasure: \\(self)" }', '''public var description: String {
        switch self {
        case .unsupportedFont(let v): return "TextMeasure: unsupportedFont(\\(v))"
        case .unsupportedLineLimit(let v): return "TextMeasure: unsupportedLineLimit(\\(v))"
        case .customFontNotBundled(let v): return "TextMeasure: customFontNotBundled(\\(v))"
        case .customFontMetricsUnavailable(let v): return "TextMeasure: customFontMetricsUnavailable(\\(v))"
        case .invalidPointSize: return "TextMeasure: invalidPointSize"
        case .measurementCacheBound: return "TextMeasure: measurementCacheBound"
        case .sourceTooLong: return "TextMeasure: sourceTooLong"
        case .invalidWidth: return "TextMeasure: invalidWidth"
        case .multilineWithoutBound: return "TextMeasure: multilineWithoutBound"
        case .noCandidateFits: return "TextMeasure: noCandidateFits"
        }
    }''')
old_start = s.index("        if let limit = request.lineLimit, limit != 1 { throw TextMeasureError.unsupportedLineLimit(limit) }")
old_end = s.index("        guard metadata.isCustom, let name = metadata.familyName")
new = '''        // PROBE P2: no lineLimit refusal (n != 1 wraps without a cap).
        let maxWidth = Float(request.proposedWidth ?? 0) * scale
        func probeWeight(_ w: String) -> UInt32 { switch w { case "medium": return 500; case "semibold": return 600; case "bold": return 700; default: return 400 } }
        func probeRequest(size: Float, weight: UInt32) -> MeasureRequest {
            let ratio = body.lineHeightDIP / body.fontSizeDIP
            return MeasureRequest(text: request.text, fontFamily: body.family, weight: weight, color: textColor,
                                  fontSize: size, lineHeight: (size * ratio).rounded(), scale: scale, maxWidth: maxWidth)
        }
        let styles: [String: (Float, UInt32)] = ["largeTitle": (26, 400), "title": (22, 400), "title2": (17, 400), "title3": (15, 400),
            "headline": (13, 700), "subheadline": (11, 400), "callout": (12, 400), "footnote": (10, 400), "caption": (10, 400), "caption2": (10, 400)]
        if request.fontMetadata == nil, request.fontID.hasPrefix("textStyle."), let style = styles[String(request.fontID.dropFirst(10))] {
            return probeRequest(size: style.0, weight: style.1)
        }
        if request.fontMetadata == nil, request.fontID.hasPrefix("system("), request.fontID.hasSuffix(")") {
            let parts = request.fontID.dropFirst(7).dropLast().split(separator: ",")
            if parts.count == 2, let size = Float(parts[0]) { return probeRequest(size: size, weight: probeWeight(String(parts[1]))) }
        }
        guard let metadata = request.fontMetadata else {
            guard request.fontID == "body" || request.fontID == "textStyle.body" else { throw TextMeasureError.unsupportedFont(request.fontID) }
            return MeasureRequest(text: request.text, fontFamily: body.family, weight: body.weight, color: textColor,
                                  fontSize: body.fontSizeDIP, lineHeight: body.lineHeightDIP, scale: scale, maxWidth: maxWidth)
        }
        if let size = metadata.pointSize.map(Float.init), size.isFinite, size > 0, size <= 512,
           !(metadata.isCustom && metadata.familyName.flatMap({ fonts?.providerFamily(forCustomName: $0) }) != nil) {
            // PROBE P2: a system font by size, or an unbundled Font.custom, measures in the body family.
            return probeRequest(size: size, weight: probeWeight(metadata.weight?.rawValue ?? "regular"))
        }
'''
s = s[:old_start] + new + s[old_end:]
p.write_text(s)
print("patched")

# P3 (symbols): the shipped table has ONE symbol (star.fill) and the painter paints only resizable().scaledToFit() symbols; anything else throws
# HostPaintError.systemImageContractMismatch and ends the run. Probe: a symbol that cannot be painted becomes a transparent rect of its frame and the
# name is logged (PROBE_SYMBOL_SKIPPED); an unknown symbol's intrinsic size is 16x16 instead of zero so layout is not collapsed.
q = d / 'ResolvedNodePainter.swift'; t = q.read_text()
a = "[try systemImagePrimitive(node, bounds: bounds, registry: systemImages)]"
assert a in t
t = t.replace(a, "[((try? systemImagePrimitive(node, bounds: bounds, registry: systemImages)) ?? { print(\"PROBE_SYMBOL_SKIPPED \\(node.image?.name ?? \"?\")\"); return Primitive.rect(bounds, color: 0) }())]")
q.write_text(t)
r = d / 'SystemImages.swift'; u = r.read_text()
b = "guard let (_, symbol) = try? entry(for: reference) else { return .zero }\n        if let layout"
assert b in u
u = u.replace(b, "guard let (_, symbol) = try? entry(for: reference) else { return LayoutSize(width: 16, height: 16) }\n        if let layout")
r.write_text(u)
print("P3 applied")

# P4 (shapes): ContinuousRoundedGeometry.path REJECTS a corner radius above min(w,h)/(2*extent) (unsupportedRadiusExtent) because Apple's large-radius
# control points were never observed; the hub's pill radius (99) hits it and ends the run. Probe: clamp to the supported maximum (a pill is drawn
# with the largest radius the table supports, so its ends are not exactly SwiftUI's).
g = d.parents[3] / 'probes/sr0-s/fresh-runtime/Sources/SwiftRightRuntime/ContinuousRoundedGeometry.swift'; v = g.read_text()
old = '''        let requested = Double(cornerRadius)
'''
assert old in v
v = v.replace(old, '''        let requested = min(Double(cornerRadius), min(width, height) / (2 * extent))   // PROBE P4: clamp instead of rejecting
''')
g.write_text(v)
print("P4 applied")

# P5 (text runs): RetainedRunChoice.choose throws measuredRunGeometryMismatch when no measured run can have been snapped to the resolved bounds, and
# ambiguousMeasuredRun when candidates disagree. Probe: take the closest measured run (or the first candidate) and paint it, so one odd Text does not end
# the picture. Text whose bounds differ from its measurement is therefore painted at the measured size.
s = p.read_text()
a = "        guard let chosen = candidates.first else { throw HostPaintError.measuredRunGeometryMismatch(text) }\n"
b = "        guard candidates.allSatisfy({ $0.width == chosen.width && $0.height == chosen.height && $0.lines == chosen.lines && $0.firstBaseline == chosen.firstBaseline }) else {\n            throw HostPaintError.ambiguousMeasuredRun(text)\n        }\n"
assert a in s and b in s
s = s.replace(a, "        guard let chosen = candidates.first ?? entries.min(by: { abs($0.width - bounds.w) + abs($0.height - bounds.h) < abs($1.width - bounds.w) + abs($1.height - bounds.h) }) else { throw HostPaintError.measuredRunGeometryMismatch(text) }\n        if candidates.isEmpty { print(\"PROBE_RUN_MISMATCH \\(text.prefix(40))\") }\n")
s = s.replace(b, "")
p.write_text(s)
print("P5 applied")

# P6 (identifiers): node identifiers are the node's path string; the hub's tree is deep enough that they reach 402 UTF-8 bytes and swr_commit refuses
# anything over SWR_IDENTIFIER_MAX (256) with SWR_E_TOO_LARGE, so the first commit of the Overview failed. Probe: ids over 256 bytes become a
# 180-byte prefix plus an FNV-1a hash of the whole path (unique per path).
t = q.read_text()
assert "identifier: node.id" in t
t = t.replace("identifier: node.id", "identifier: probeShortID(node.id)")
t += '''

/// PROBE P6: identifiers over SWR_IDENTIFIER_MAX (256 bytes) are shortened to a prefix plus a hash of the full path.
func probeShortID(_ id: String) -> String {
    guard id.utf8.count > 256 else { return id }
    var h: UInt64 = 0xcbf29ce484222325
    for b in id.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return String(id.prefix(180)) + "~" + String(h, radix: 16)
}
'''
q.write_text(t)
print("P6 applied")

# P7 (single-line search): `.lineLimit(1)` text offered a width where not even one character plus an ellipsis fits (an intermediate layout pass of
# the hub's flexible rows) throws noCandidateFits / multilineWithoutBound, which the host treats as fatal. Probe: fall back to the plain, unconstrained
# measurement of the text (it overflows its frame instead of truncating).
s = p.read_text()
a = "            let selection = try SingleLineText.select(request.text, maxWidth: shaping.maxWidth,"
assert a in s
s = s.replace(a, "            let selection: SingleLineText.Selection<SwiftRightBridge.TextMeasurement>\n            do { selection = try SingleLineText.select(request.text, maxWidth: shaping.maxWidth,")
b = "                width: { $0.width }, lineCount: { $0.lineCount }, release: { _ = bridge.release($0.run) })\n"
assert b in s
s = s.replace(b, "                width: { $0.width }, lineCount: { $0.lineCount }, release: { _ = bridge.release($0.run) }) }\n            catch TextMeasureError.noCandidateFits { return try bridge.measure(shaping) }\n            catch TextMeasureError.multilineWithoutBound { return try bridge.measure(shaping) }\n")
p.write_text(s)
print("P7 applied")

# P6b: the same shortening at the bridge marshalling point (covers every painter, not only ResolvedNodePainter).
m = d.parents[2] / 'SwiftRightBridge/Sources/SwiftRightBridge/Marshal.swift'; w = m.read_text()
assert "let identifier = arena.string(s.identifier)" in w
w = w.replace("let identifier = arena.string(s.identifier)", "let identifier = arena.string(probeBridgeShortID(s.identifier))")
w += '''

/// PROBE P6b: identifiers over SWR_IDENTIFIER_MAX (256 bytes) become a prefix plus an FNV-1a hash of the whole identifier.
func probeBridgeShortID(_ id: String) -> String {
    guard id.utf8.count > 256 else { return id }
    var h: UInt64 = 0xcbf29ce484222325
    for b in id.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
    return String(id.prefix(180)) + "~" + String(h, radix: 16)
}
'''
m.write_text(w)
print("P6b applied")

# P8 (alpha-0 fills): a rect whose colour is 0x00000000 (Color.clear, Color.black.opacity(0.001) rounds to alpha 0, transparent hit areas) is drawn BLACK by
# the renderer. Probe: marshal such a rect with alpha 1/255 so it is invisible. (Finding: transparent fills are not supported by the paint path as it stands.)
w = m.read_text()
a = "c.kind = 1; c.rect = cRect(r); c.color = color\n"
assert a in w
w = w.replace(a, "c.kind = 1; c.rect = cRect(r); c.color = (color == 0 ? 0x00000001 : color)   // PROBE P8\n")
m.write_text(w)
print("P8 applied")

# P10 text cache bound 256 -> 16384 (a settings page measures more than 256 distinct strings: measurementCacheBound ends the run).
s = p.read_text(); assert "private static let cacheBound = 256" in s
p.write_text(s.replace("private static let cacheBound = 256", "private static let cacheBound = 16384   // PROBE P10"))
# P11 continuous-shape raster work limit 2,000,000 px -> 40,000,000 (a full-window card at 2.5x is 3.4 Mpx; workLimitExceeded ends the run).
g2 = d.parents[3] / 'probes/sr0-s/fresh-runtime/Sources/SwiftRightRuntime/ContinuousRoundedRasterizer.swift'; v2 = g2.read_text()
assert "maxWorkPixels = 2_000_000" in v2
g2.write_text(v2.replace("maxWorkPixels = 2_000_000", "maxWorkPixels = 40_000_000   // PROBE P11"))
# P12 Divider in the dark appearance is refused ("not measured"); probe paints the light divider colour.
t = q.read_text(); a12 = 'guard node.style.colorScheme != .dark else { throw HostPaintError.unsupportedNode("Divider (dark appearance not measured)") }'
assert a12 in t
q.write_text(t.replace(a12, "// PROBE P12: dark Divider not measured; painted with the same rule"))
# P13 Button with opacity != 1, a foreground style on a bordered look, or an empty frame is refused; probe ignores opacity and the foreground style.
b = d / 'ButtonPainter.swift'; u = b.read_text()
a13 = "        guard node.opacity == 1 else { throw HostPaintError.unsupportedButtonPaintStyle }\n        if node.style.foreground != nil, look == .bordered { throw HostPaintError.unsupportedButtonPaintStyle }\n"
assert a13 in u
u = u.replace(a13, "        // PROBE P13: opacity and a foreground style on a Button are not refused\n")
a13b = "        guard width > 0, height > 0 else { throw HostPaintError.unsupportedButtonPaintStyle }\n"
assert a13b in u
u = u.replace(a13b, "        guard width > 0, height > 0 else { return ButtonPaintPlan(image: nil, placement: bounds, isEnabled: isEnabled, look: look, labelColor: try labelColor(of: node)) }   // PROBE P13\n")
b.write_text(u)
print("P10-P13 applied")

# P14 (shapes that cannot be rasterised): a zero-size continuous RoundedRectangle throws continuousShapeRasterInput(1), one over 4 Mpx throws pixelLimitExceeded;
# either ends the page. SwiftUI draws nothing for a zero-size shape. Probe: skip the shape and log PROBE_SHAPE_SKIPPED.
t = q.read_text()
a14 = "                let result = try ContinuousShapeRaster.primitive(images, request)\n"
assert a14 in t
t = t.replace(a14, "                guard let result = try? ContinuousShapeRaster.primitive(images, request) else {\n                    print(\"PROBE_SHAPE_SKIPPED \\(Int(request.bounds.w))x\\(Int(request.bounds.h)) r=\\(request.cornerRadiusPX)\")\n                    return NodeEmission(primitives: [], semantic: nil, flags: [], structural: false)\n                }\n")
q.write_text(t)
print("P14 applied")
