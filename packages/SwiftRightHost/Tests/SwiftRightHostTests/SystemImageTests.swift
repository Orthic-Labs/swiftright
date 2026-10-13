import XCTest
import SwiftRightHost

@MainActor
final class SystemImageTests: XCTestCase {
    func testEmbeddedTableEqualsTheAssetFile() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Assets/SystemImageAssets.json")
        let onDisk = try SystemImageTable.decode(Data(contentsOf: file))
        let embedded = try SystemImageTable.standard()
        XCTAssertEqual(Set(onDisk.symbols.keys), Set(embedded.symbols.keys))
        XCTAssertEqual(onDisk.symbols["star.fill"]?.glyph, embedded.symbols["star.fill"]?.glyph)
        XCTAssertEqual(onDisk.symbols["star.fill"]?.layout?.inkOverrides?.count, embedded.symbols["star.fill"]?.layout?.inkOverrides?.count)
        // Byte-level: the generated source carries exactly the JSON file.
        let generated = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/SwiftRightHost/SystemImageTableData.swift"), encoding: .utf8)
        XCTAssertTrue(generated.contains(try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .newlines)), "run scripts/embed-assets.py")
    }

    func testStarFillIsInTheShippedTableWithItsSubstituteProviderDeclared() throws {
        let t = try SystemImageTable.standard()
        let star = try XCTUnwrap(t.symbols["star.fill"])
        XCTAssertEqual(star.provider, "Segoe Fluent Icons"); XCTAssertEqual(star.glyph, "E735")
        XCTAssertEqual(t.providerPolicy.parity, "substitute-provider-unverified")
        XCTAssertEqual(star.layout?.intrinsicSize, [17, 16])
    }

    func testRejectsAnInvalidTable() throws {
        XCTAssertThrowsError(try SystemImageTable.decode(Data("{}".utf8)))
        var json = try String(contentsOfFile: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Assets/SystemImageAssets.json").path, encoding: .utf8)
        json = json.replacingOccurrences(of: "\"substitute-provider-unverified\"", with: "\"verified\"")
        XCTAssertThrowsError(try SystemImageTable.decode(Data(json.utf8))) { XCTAssertEqual($0 as? SystemImageTable.TableError, .providerPolicyMismatch) }
    }

    func testLayoutHooksFollowTheScaleClass() throws {
        let reg = try SystemImageRegistry(images: FakeImages(), rasterizer: FakeGlyphs(), log: { _ in })
        let star = ImageReference.system("star.fill")
        XCTAssertEqual(reg.intrinsicSize(for: star), LayoutSize(width: 17, height: 16))
        reg.scale = 1; XCTAssertEqual(reg.fitIntrinsicSize(for: star), LayoutSize(width: 15, height: 14))
        reg.scale = 2.5; XCTAssertEqual(reg.fitIntrinsicSize(for: star), LayoutSize(width: 29, height: 28))
        XCTAssertEqual(reg.intrinsicSize(for: .system("no.such.symbol")), .zero)
        XCTAssertNil(reg.fitIntrinsicSize(for: .system("no.such.symbol")))
        XCTAssertFalse(reg.supports(.named("star.fill")))
    }

    func testGraphResolvesImageFrameThroughTheInstalledHooks() throws {
        // 32 pt resizable().scaledToFit() at scale 2.5: aspect-fit of the 2x-class fit box 29x28 in 80 px.
        let reg = try SystemImageRegistry(images: FakeImages(), rasterizer: FakeGlyphs(), log: { _ in })
        reg.scale = 2.5
        let graph = Graph(Image(systemName: "star.fill").resizable().scaledToFit().frame(width: 32, height: 32), scale: 2.5)
        reg.install(on: graph)
        graph.rootProposal = ProposedViewSize(width: 100, height: 100)
        graph.flush()
        let image = try XCTUnwrap(flatten(try XCTUnwrap(graph.snapshot())).first { $0.kind == "Image" })
        XCTAssertEqual(image.pixelFrame.width, 80); XCTAssertEqual(image.pixelFrame.height, 78)   // 80 x 28/29 = 77.2, edges snapped to whole pixels
    }

    func testRasterIsCachedPerReferenceTintAndSizeAndReleasedAtTeardown() throws {
        let images = FakeImages(), glyphs = FakeGlyphs()
        let reg = try SystemImageRegistry(images: images, rasterizer: glyphs, log: { _ in })
        reg.scale = 2.5
        let star = ImageReference.system("star.fill")
        let a = try reg.handle(for: star, tint: 0xffcc00ff, width: 80, height: 77)
        let b = try reg.handle(for: star, tint: 0xffcc00ff, width: 80, height: 77)
        XCTAssertEqual(a, b); XCTAssertEqual(images.registered.count, 1)
        let c = try reg.handle(for: star, tint: 0xffcc00ff, width: 40, height: 38)
        XCTAssertNotEqual(a, c); XCTAssertEqual(images.registered.count, 2)
        // Canvas = frame + 4 px inset on each side; the glyph is requested oversampled (8x) and the face is the declared provider.
        let entry = try XCTUnwrap(images.registered[a.raw]); XCTAssertEqual(entry.width, 88); XCTAssertEqual(entry.height, 85)
        XCTAssertEqual(glyphs.requests.first?.family, "Segoe Fluent Icons"); XCTAssertEqual(glyphs.requests.first?.glyph, 0xE735)
        XCTAssertEqual(glyphs.requests.first?.w, 88 * 8)       // the table asks for an 8x oversampled outline
        reg.releaseAll(); XCTAssertEqual(images.live, [])
    }

    func testInkOverrideIsReportedAsAMeasurementNotARule() throws {
        let reg = try SystemImageRegistry(images: FakeImages(), rasterizer: FakeGlyphs(), log: { _ in })
        reg.scale = 1
        let layout = try XCTUnwrap(reg.table.symbols["star.fill"]?.layout)
        let hit = try XCTUnwrap(layout.deviceInkBox(scale: 1, widthPx: 18, heightPx: 16))
        XCTAssertEqual(hit.source, "measured-override")
        let model = try XCTUnwrap(layout.deviceInkBox(scale: 1, widthPx: 33, heightPx: 31))
        XCTAssertEqual(model.source, "scale-class-model")
    }

    func testAFaceThatIsNotTheDeclaredProviderIsRefused() throws {
        let glyphs = FakeGlyphs(); glyphs.face = "Segoe UI"
        let reg = try SystemImageRegistry(images: FakeImages(), rasterizer: glyphs, log: { _ in })
        reg.scale = 2.5
        XCTAssertThrowsError(try reg.handle(for: .system("star.fill"), tint: 0xffcc00ff, width: 80, height: 77)) {
            XCTAssertEqual($0 as? SystemImageError, .fontSelectionFailed)
        }
        XCTAssertThrowsError(try reg.handle(for: .system("nope"), tint: 0, width: 8, height: 8)) { XCTAssertEqual($0 as? SystemImageError, .providerEntryMissing("nope")) }
        XCTAssertThrowsError(try reg.handle(for: .system("star.fill"), tint: 0, width: 0, height: 8)) { XCTAssertEqual($0 as? SystemImageError, .targetSizeInvalid) }
    }
}
