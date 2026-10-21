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
        "paintpalette", "bell", "checkmark.circle", "checkmark.circle.fill", "checkmark.square.fill", "link", "waveform.path.ecg", "cpu", "memorychip", "terminal", "textbox", "paperplane", "wrench", "square"]

    private func registry(scale: Double) throws -> SystemImageRegistry {
        let r = try SystemImageRegistry(images: FakeImages(), rasterizer: FakeGlyphs(), log: { _ in })
        r.scale = scale
        return r
    }

    func testEveryHubSymbolIsInTheTableWithAProviderGlyphAndFontSizedLayout() throws {
        let t = try SystemImageTable.standard()
        XCTAssertEqual(Self.hubSymbols.count, 59)
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
        XCTAssertEqual(r.fontIntrinsicSize(for: .system("gearshape"), font: .headline), LayoutSize(width: 17, height: 17))   // headline = 13 pt bold, measured
        XCTAssertNil(r.fontIntrinsicSize(for: .system("gearshape"), font: Font.system(size: 13, weight: .medium)))   // medium: not measured
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
        XCTAssertThrowsError(try emit(Image(systemName: "chevron.right").font(Font.system(size: 13, weight: .medium)))) { XCTAssertTrue("\($0)".contains("not measured")) }
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


@MainActor
final class FontWeightSymbolTests: XCTestCase {
    func testFontSpecResolvesTheHubFontsAndRefusesTheRest() {
        typealias R = SystemImageRegistry
        XCTAssertEqual(R.fontSpec(nil)?.size, 13); XCTAssertEqual(R.fontSpec(nil)?.weight, "regular")
        // theme.type.*.font = Font.system(size:weight:)
        for (size, weight, w) in [(22.0, "semibold", Font.Weight.semibold), (15, "bold", .bold), (13.5, "regular", .regular), (12.5, "semibold", .semibold), (11, "semibold", .semibold)] {
            let spec = R.fontSpec(Font.system(size: CGFloat(size), weight: w))
            XCTAssertEqual(spec?.size, size); XCTAssertEqual(spec?.weight, weight)
        }
        XCTAssertEqual(R.fontSpec(.headline)?.weight, "bold"); XCTAssertEqual(R.fontSpec(.headline)?.size, 13)
        XCTAssertEqual(R.fontSpec(Font.body.weight(.bold))?.weight, "bold")
        XCTAssertEqual(R.fontSpec(.callout)?.size, 12)
        XCTAssertNil(R.fontSpec(Font.system(size: 13, weight: .medium)))
        XCTAssertNil(R.fontSpec(Font.system(size: 13, weight: .heavy)))
        XCTAssertNil(R.fontSpec(Font.custom("X", size: 13)))
        XCTAssertNil(R.fontSpec(Font.system(size: 13, weight: .regular, design: .rounded)))
    }

    func testEverySymbolHasSemiboldAndBoldRowsAndTheyDifferFromRegular() throws {
        let t = try SystemImageTable.standard()
        var heavier = 0
        for name in FontSizedSymbolTests.hubSymbols {
            let l = try XCTUnwrap(t.symbols[name]?.layout, name)
            XCTAssertTrue(l.fontWeights.isSuperset(of: ["regular", "semibold", "bold"]), name)
            for size in [11.0, 11.5, 12.0, 12.5, 13.0, 13.5, 15.0, 22.0, 28.0] {
                for w in ["semibold", "bold"] { XCTAssertNotNil(l.fontLayout(pointSize: size, weight: w, scale: 2.5)?.measured, "\(name) \(size) \(w)") }
            }
            if l.fontLayout(pointSize: 13, weight: "semibold", scale: 2.5)?.framePt != l.fontLayout(pointSize: 13, weight: "regular", scale: 2.5)?.framePt
                || l.fontLayout(pointSize: 13, weight: "semibold", scale: 2.5)?.inkFractions != l.fontLayout(pointSize: 13, weight: "regular", scale: 2.5)?.inkFractions { heavier += 1 }
        }
        XCTAssertGreaterThan(heavier, 30, "semibold must not be the regular table renamed")
    }

    func testSemiboldFramesAndRasterFollowTheWeightRows() throws {
        let reg = try SystemImageRegistry(images: FakeImages(), rasterizer: FakeGlyphs(), log: { _ in })
        reg.scale = 2.5
        let ref = ImageReference.system("gearshape")
        let semi = Font.system(size: 12, weight: .semibold)
        let frame = try XCTUnwrap(reg.fontIntrinsicSize(for: ref, font: semi))
        let l = try XCTUnwrap(reg.table.symbols["gearshape"]?.layout?.fontLayout(pointSize: 12, weight: "semibold", scale: 2.5))
        XCTAssertEqual(frame, LayoutSize(width: CGFloat(l.framePt[0]), height: CGFloat(l.framePt[1])))
        let r = try reg.raster(for: ref, tint: 0x0088ffff, width: UInt32((Double(frame.width) * 2.5).rounded()), height: UInt32((Double(frame.height) * 2.5).rounded()), fontSize: 12, weight: "semibold")
        XCTAssertEqual(r.deviceInkMatched, "true"); XCTAssertEqual(r.inkBoxSource, "measured-font-size")
        let m = try XCTUnwrap(l.measured)
        XCTAssertEqual(r.macInkBox, "\(m.inkPx[0]),\(m.inkPx[1]),\(m.inkPx[2]),\(m.inkPx[3])")
    }

    func testPainterPaintsSemiboldAndRefusesMedium() throws {
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
        for weight in [Font.Weight.semibold, .bold, .regular] {
            let e = try emit(Image(systemName: "checkmark").font(Font.system(size: 11, weight: weight)).foregroundStyle(Color.blue))
            guard case .image = try XCTUnwrap(e.primitives.first) else { return XCTFail() }
        }
        XCTAssertThrowsError(try emit(Image(systemName: "checkmark").font(Font.system(size: 11, weight: .medium)))) { XCTAssertTrue("\($0)".contains("not measured")) }
        // a theme font reaches the Image through an ancestor
        XCTAssertNoThrow(try emit(HStack { Image(systemName: "checkmark") }.font(Font.system(size: 12.5, weight: .semibold))))
    }
}


final class FillSymbolMappingTests: XCTestCase {
    /// A `.fill` symbol with a mark knocked out must map to a Segoe glyph that has the mark (contact sheet, round 5 block 29): CheckboxFill (E73B) and
    /// CheckboxIndeterminate (E73C) are a bare filled square and a bare line.
    func testFilledSymbolsMapToGlyphsThatKeepTheirInnerMark() throws {
        let t = try SystemImageTable.standard()
        let expected = ["checkmark.square.fill": "E73D", "checkmark.circle.fill": "EC61", "info.circle.fill": "F167", "xmark.circle.fill": "EB90",
                        "exclamationmark.triangle.fill": "F736", "xmark.octagon.fill": "EB90", "minus.square.fill": "F16D", "xmark.circle": "EA39"]
        for (name, glyph) in expected { XCTAssertEqual(t.symbols[name]?.glyph, glyph, name) }
        // E73B is right only for square.fill, which is a bare filled square with no mark (#73).
        for (name, s) in t.symbols where name != "square.fill" { XCTAssertFalse(["E73B", "E73C"].contains(s.glyph), name) }
        XCTAssertEqual(t.symbols["square.fill"]?.glyph, "E73B")
    }
}
