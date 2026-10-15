import XCTest
import SwiftRightHost

/// Round 5 block 29: `Image(systemName:)` at the environment font (not resizable), for the Pulse hub's symbols.
/// Expected numbers are Mac measurements (factory/tools/symbol-metrics/symbol-sizes.sh, macOS 27).
@MainActor
final class FontSizedSymbolTests: XCTestCase {
    static let hubSymbols = ["arrow.clockwise", "arrow.down", "arrow.up", "arrow.up.arrow.down", "checkmark", "checkmark.shield", "chevron.down",
        "chevron.right", "chevron.up", "circle.lefthalf.filled", "clock.arrow.circlepath", "doc", "doc.on.doc", "exclamationmark.triangle",
        "exclamationmark.triangle.fill", "externaldrive", "folder", "folder.badge.plus", "gauge.with.dots.needle.33percent", "gearshape",
        "hourglass", "info.circle", "info.circle.fill", "internaldrive", "magnifyingglass", "message", "minus", "minus.square.fill", "network",
        "pencil", "person.crop.circle", "plus", "sidebar.left", "sparkles", "square.dashed", "square.grid.2x2", "square.grid.3x3", "switch.2",
        "trash", "tray", "xmark", "xmark.circle", "xmark.circle.fill", "xmark.octagon.fill", "app.dashed",
        "paintpalette", "bell", "checkmark.circle", "checkmark.circle.fill", "checkmark.square.fill", "link", "waveform.path.ecg", "cpu", "memorychip", "terminal", "textbox"]

    private func registry(scale: Double) throws -> SystemImageRegistry {
        let r = try SystemImageRegistry(images: FakeImages(), rasterizer: FakeGlyphs(), log: { _ in })
        r.scale = scale
        return r
    }

    func testEveryHubSymbolIsInTheTableWithAProviderGlyphAndFontSizedLayout() throws {
        let t = try SystemImageTable.standard()
        XCTAssertEqual(Self.hubSymbols.count, 56)
        XCTAssertLessThanOrEqual(t.symbols.count, Int(t.providerPolicy.maxSymbols))
        for name in Self.hubSymbols {
            let s = try XCTUnwrap(t.symbols[name], name)
            XCTAssertEqual(s.provider, "Segoe Fluent Icons", name)
            XCTAssertNotNil(UInt32(s.glyph, radix: 16), name)
            XCTAssertTrue(s.layout?.supportsFontSizes ?? false, name)
            XCTAssertNotNil(s.layout?.fontLayout(pointSize: 13, scale: 1)?.measured, name)
            XCTAssertNotNil(s.layout?.fontLayout(pointSize: 28, scale: 2.5)?.measured, name)
        }
    }

    func testIntrinsicSizesAreTheMacViewFramesAtTheBodyAndExplicitSizes() throws {
        let r = try registry(scale: 2.5)
        // 2x class, measured at scale 2.5: pixel frames /2.5.
        XCTAssertEqual(r.fontIntrinsicSize(for: .system("gearshape"), font: nil), LayoutSize(width: 16, height: 16))     // 40 x 40 px
        XCTAssertEqual(r.fontIntrinsicSize(for: .system("doc"), font: nil), LayoutSize(width: 14, height: 16))           // 35 x 40 px
        XCTAssertEqual(r.fontIntrinsicSize(for: .system("gearshape"), font: Font.system(size: 28, weight: .regular)), LayoutSize(width: 34.4, height: 34.4))   // 86 px
        XCTAssertEqual(r.fontIntrinsicSize(for: .system("gearshape"), font: .body), r.fontIntrinsicSize(for: .system("gearshape"), font: nil))
        r.scale = 1   // 1x class, measured at scale 1
        XCTAssertEqual(r.fontIntrinsicSize(for: .system("chevron.right"), font: nil), LayoutSize(width: 10, height: 14))
        XCTAssertEqual(r.fontIntrinsicSize(for: .system("doc"), font: nil), LayoutSize(width: 15, height: 16))
        XCTAssertEqual(r.fontIntrinsicSize(for: .system("gearshape"), font: .callout), LayoutSize(width: 15, height: 15))   // callout is the 12 pt system font
        XCTAssertNil(r.fontIntrinsicSize(for: .system("gearshape"), font: .headline))      // semibold: not measured
        XCTAssertNil(r.fontIntrinsicSize(for: .system("gearshape"), font: Font.system(size: 13, weight: .bold)))
        XCTAssertNil(r.fontIntrinsicSize(for: .system("gearshape"), font: Font.custom("Menlo", size: 13)))
        XCTAssertNil(r.fontIntrinsicSize(for: .system("no.such.symbol"), font: nil))
    }

    func testUnmeasuredSizesAreInterpolatedAndSaidSo() throws {
        let t = try SystemImageTable.standard()
        let layout = try XCTUnwrap(t.symbols["gearshape"]?.layout)
        let l19 = try XCTUnwrap(layout.fontLayout(pointSize: 19, scale: 1))
        XCTAssertFalse(l19.isMeasured); XCTAssertNil(l19.measured)
        let a = try XCTUnwrap(layout.fontLayout(pointSize: 18, scale: 1)), b = try XCTUnwrap(layout.fontLayout(pointSize: 20, scale: 1))
        XCTAssertEqual(l19.framePt[0], (a.framePt[0] + b.framePt[0]) / 2, accuracy: 1e-9)
        let box = try XCTUnwrap(layout.fontDeviceInkBox(pointSize: 19, scale: 1, widthPx: 24, heightPx: 24))
        XCTAssertEqual(box.source, "font-size-interpolated")
        XCTAssertEqual(try XCTUnwrap(layout.fontDeviceInkBox(pointSize: 13, scale: 1, widthPx: 16, heightPx: 16)).source, "measured-font-size")
    }

    func testRasterLandsOnTheMeasuredMacInkBox() throws {
        let r = try registry(scale: 2.5)
        let ref = ImageReference.system("gearshape")
        let at13 = try r.raster(for: ref, tint: 0x112233ff, width: 40, height: 40, fontSize: 13)
        XCTAssertEqual(at13.macInkBox, "3,4,36,37"); XCTAssertEqual(at13.halfCoverageBox, "3,4,36,37"); XCTAssertEqual(at13.deviceInkMatched, "true")
        XCTAssertEqual(at13.inkBoxSource, "measured-font-size")
        let at28 = try r.raster(for: ref, tint: 0x112233ff, width: 86, height: 86, fontSize: 28)
        XCTAssertEqual(at28.macInkBox, "6,7,79,80"); XCTAssertEqual(at28.deviceInkMatched, "true")
        // The tint is the glyph colour.
        XCTAssertEqual(Array(at13.rgba[(20 * 48 + 20) * 4 ..< (20 * 48 + 20) * 4 + 3]), [0x11, 0x22, 0x33])
        // A frame one pixel off the measured one (edge snapping) uses the measured ink fractions, not an override.
        let off = try r.raster(for: ref, tint: 0x112233ff, width: 41, height: 40, fontSize: 13)
        XCTAssertEqual(off.inkBoxSource, "font-size-fractions")
    }

    func testGraphLaysOutAFontSizedSymbolInsideAFixedWidthFrame() throws {
        // The hub sidebar row: Image(systemName:).frame(width: 16) at the body font, scale 2.5.
        let reg = try registry(scale: 2.5)
        let graph = Graph(HStack(spacing: 0) { Image(systemName: "doc").frame(width: 20); Image(systemName: "gearshape").font(Font.system(size: 28, weight: .regular)) }, scale: 2.5)
        reg.install(on: graph)
        graph.rootProposal = ProposedViewSize(width: 200, height: 100)
        graph.flush()
        let images = flatten(try XCTUnwrap(graph.snapshot())).filter { $0.kind == "Image" }
        XCTAssertEqual(images.count, 2)
        XCTAssertTrue((34...35).contains(images[0].pixelFrame.width)); XCTAssertEqual(images[0].pixelFrame.height, 40)   // doc at 13 pt: 14 x 16 pt = 35 x 40 px, centred at x = 3 pt so an edge snaps either way
        XCTAssertEqual(images[1].pixelFrame.width, 86); XCTAssertEqual(images[1].pixelFrame.height, 86)   // gearshape at 28 pt: 34.4 pt
    }

    func testPainterPaintsFontSizedSymbolsAndRefusesWhatWasNotMeasured() throws {
        let images = FakeImages()
        let reg = try SystemImageRegistry(images: images, rasterizer: FakeGlyphs(), log: { _ in })
        reg.scale = 2.5
        let painter = ResolvedNodePainter(images: images, scale: 2.5, text: nil, systemImages: reg, log: { _ in })
        func emit<V: View>(_ view: V) throws -> NodeEmission {
            let graph = Graph(view, scale: 2.5); reg.install(on: graph)
            graph.rootProposal = ProposedViewSize(width: 100, height: 100); graph.flush()
            painter.beginCommit(); defer { painter.endCommit(committed: true) }
            let n = try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "Image" })
            return try painter.emit(n, id: 1, bounds: Rect(x: Float(n.pixelFrame.x), y: Float(n.pixelFrame.y), w: Float(n.pixelFrame.width), h: Float(n.pixelFrame.height)))
        }
        let ok = try emit(Image(systemName: "chevron.right").foregroundStyle(Color.gray))
        guard case .image = try XCTUnwrap(ok.primitives.first) else { return XCTFail("a font-sized symbol must be an image primitive") }
        XCTAssertThrowsError(try emit(Image(systemName: "chevron.right").font(Font.system(size: 13, weight: .bold)))) { XCTAssertTrue("\($0)".contains("not measured")) }
        XCTAssertThrowsError(try emit(Image(systemName: "star.fill").resizable().frame(width: 10, height: 10)))   // resizable without scaledToFit
        XCTAssertThrowsError(try emit(Image(systemName: "chevron.right").resizable().scaledToFit().frame(width: 10, height: 10))) {
            XCTAssertTrue("\($0)".contains("no measured resizable layout"))    // only star.fill has the resizable fit data
        }
    }
}

@MainActor
final class FontSizedSymbolRasterSweepTests: XCTestCase {
    /// Every hub symbol rasterises at the measured sizes at both scale classes without throwing; the produced half-coverage box is the Mac box.
    func testEverySymbolRasterisesAtTheBodyAndExplicitSizes() throws {
        for scale in [1.0, 2.5] {
            let reg = try SystemImageRegistry(images: FakeImages(), rasterizer: FakeGlyphs(), log: { _ in })
            reg.scale = scale
            for name in FontSizedSymbolTests.hubSymbols {
                for size in [13.0, 28.0] {
                    let ref = ImageReference.system(name)
                    let frame = try XCTUnwrap(reg.fontIntrinsicSize(for: ref, font: Font.system(size: CGFloat(size), weight: .regular)), name)
                    let r: SystemImageRaster
                    do { r = try reg.raster(for: ref, tint: 0x0088ffff, width: UInt32((Double(frame.width) * scale).rounded()), height: UInt32((Double(frame.height) * scale).rounded()), fontSize: size) }
                    catch { XCTFail("\(name) \(size) @\(scale): \(error) frame \(frame) ink \(String(describing: reg.table.symbols[name]?.layout?.fontLayout(pointSize: size, scale: scale)?.measured))"); continue }
                    XCTAssertEqual(r.deviceInkMatched, "true", "\(name) \(size) @\(scale): \(r.macInkBox) vs \(r.halfCoverageBox)")
                }
            }
        }
    }
}

@MainActor
final class SystemImageErrorTextTests: XCTestCase {
    func testErrorDescriptionDoesNotRecurse() {
        XCTAssertEqual("\(SystemImageError.emptyCoverage)", "SystemImage: emptyCoverage")
        XCTAssertEqual("\(SystemImageError.providerEntryMissing("x"))", "SystemImage: providerEntryMissing(x)")
    }
}

@MainActor
final class FontSizedSymbolInsetTests: XCTestCase {
    func testCanvasMarginGrowsForInkThatOverflowsTheFrameByMoreThanTheDefault() throws {
        let reg = try SystemImageRegistry(images: FakeImages(), rasterizer: FakeGlyphs(), log: { _ in })
        reg.scale = 2.5
        let ref = ImageReference.system("folder.badge.plus")
        // measured: 28 pt at scale 2.5 is a 96 x 81 px frame with ink to x = 101 (5 px past the frame)
        XCTAssertEqual(reg.canvasInset(for: ref, fontSize: 28, width: 96, height: 81), 6)
        XCTAssertEqual(reg.canvasInset(for: ref, fontSize: 13, width: 40, height: 33), Float(SystemImageRegistry.overflowInset))
        XCTAssertNoThrow(try reg.raster(for: ref, tint: 1, width: 96, height: 81, fontSize: 28))
    }
}
