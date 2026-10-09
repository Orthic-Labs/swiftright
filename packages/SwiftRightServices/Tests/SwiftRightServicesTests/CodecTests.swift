import XCTest
@testable import SwiftRightServices

/// Pure codec tests: no process is launched, so these run identically on macOS and Windows.
final class CodecTests: XCTestCase {
    private func decodeAll(_ framing: EngineFraming, limit: Int, chunks: [Data]) throws -> [EngineFrameDecoder.Output] {
        var decoder = EngineFrameDecoder(framing: framing, limit: limit)
        var outputs: [EngineFrameDecoder.Output] = []
        for chunk in chunks { outputs += try decoder.feed(chunk) }
        return outputs
    }

    func testJSONLinesSkipsBlankLinesAndStripsCR() throws {
        let input = Data("\r\n\n{\"type\":\"ready\"}\r\n".utf8)
        let outputs = try decodeAll(.jsonLines, limit: 64, chunks: [input])
        XCTAssertEqual(outputs, [.body(Data("{\"type\":\"ready\"}".utf8))])
    }

    func testJSONLinesReassemblesAcrossChunkBoundaries() throws {
        let bytes = Array("{\"type\":\"ready\"}\n".utf8)
        let chunks = bytes.map { Data([$0]) }
        let outputs = try decodeAll(.jsonLines, limit: 64, chunks: chunks)
        XCTAssertEqual(outputs, [.body(Data("{\"type\":\"ready\"}".utf8))])
    }

    func testOversizedLineIsDrainedWithItsRequestIDAndStreamResyncs() throws {
        let long = String(repeating: "y", count: 200)
        let oversized = Data("{\"type\":\"response\",\"id\":5,\"ok\":true,\"result\":\"\(long)\"}\n".utf8)
        let ready = Data("{\"type\":\"ready\"}\n".utf8)
        // Feed byte by byte so the discard path runs across many chunks.
        let chunks = (oversized + ready).map { Data([$0]) }
        let outputs = try decodeAll(.jsonLines, limit: 64, chunks: chunks)
        XCTAssertEqual(outputs.count, 2)
        XCTAssertEqual(outputs[0], .oversized(requestID: 5, bytes: oversized.count - 1))
        XCTAssertEqual(outputs[1], .body(Data("{\"type\":\"ready\"}".utf8)))
    }

    func testLengthPrefixedRoundTripCarriesNewlinesInsideBody() throws {
        let body = Data("{\"type\":\"event\",\"event\":{\"text\":\"a\\nb\"}}".utf8)
        let framed = try EngineWire.frame(body, framing: .lengthPrefixed, limit: 1024)
        XCTAssertEqual(Array(framed.prefix(4)), [0, 0, 0, UInt8(body.count)])
        let outputs = try decodeAll(.lengthPrefixed, limit: 1024, chunks: [framed])
        XCTAssertEqual(outputs, [.body(body)])
    }

    func testLengthPrefixedZeroLengthIsFatal() {
        XCTAssertThrowsError(try decodeAll(.lengthPrefixed, limit: 64, chunks: [Data([0, 0, 0, 0])])) { error in
            guard case EngineError.malformedFrame = error else { return XCTFail("\(error)") }
        }
    }

    func testLengthPrefixedOverLimitIsFatalWithoutReadingBody() {
        XCTAssertThrowsError(try decodeAll(.lengthPrefixed, limit: 8, chunks: [Data([0, 0, 0, 9])])) { error in
            XCTAssertEqual(error as? EngineError, .frameTooLarge(limit: 8, requestID: nil))
        }
    }

    func testEncodeRejectsOversizedBodyWithoutOutput() {
        XCTAssertThrowsError(try EngineWire.frame(Data(count: 10), framing: .jsonLines, limit: 9)) { error in
            XCTAssertEqual(error as? EngineError, .frameTooLarge(limit: 9, requestID: nil))
        }
    }

    func testPeekRequestIDReadsLeadingIDOnly() {
        XCTAssertEqual(EngineFrameDecoder.peekRequestID(Array("{\"type\":\"response\",\"id\": 42,".utf8)), 42)
        XCTAssertNil(EngineFrameDecoder.peekRequestID(Array("{\"type\":\"ready\"}".utf8)))
    }

    func testInboundParsingMapsEnvelopeFields() {
        XCTAssertEqual(EngineInbound.parse(Data("{\"type\":\"hello\",\"engine\":\"x\",\"version\":\"2\",\"contract_version\":1,\"extra\":true}".utf8)),
                       .hello(EngineHello(engine: "x", version: "2", contractVersion: 1)))
        XCTAssertEqual(EngineInbound.parse(Data("{\"type\":\"hello\"}".utf8)),
                       .hello(EngineHello(engine: "", version: "", contractVersion: 0)))
        XCTAssertEqual(EngineInbound.parse(Data("{\"type\":\"future_thing\"}".utf8)), .ignored)
        XCTAssertNil(EngineInbound.parse(Data("{\"type\":\"response\",\"ok\":true}".utf8)), "response without id is malformed")
        XCTAssertNil(EngineInbound.parse(Data("not json".utf8)))
        XCTAssertEqual(EngineInbound.parse(Data("{\"type\":\"response\",\"id\":3,\"ok\":false,\"error\":{\"code\":\"c\"}}".utf8)),
                       .response(id: 3, ok: false, result: nil, error: WireError(code: "c", message: "", retryable: false)))
    }

    func testEngineJSONKeepsIntegersExact() throws {
        let value = try EngineJSON(encoding: Numbers(big: 9_007_199_254_740_993, pi: 3.5))
        XCTAssertEqual(value, .object(["big": .integer(9_007_199_254_740_993), "pi": .number(3.5)]))
        let decoded: Numbers = try value.decode()
        XCTAssertEqual(decoded.big, 9_007_199_254_740_993)
    }
}

private struct Numbers: Codable, Equatable {
    var big: Int64
    var pi: Double
}

private struct Payload: Codable, Equatable {
    var name: String
    var count: Int
}

extension CodecTests {
    func testPayloadMappingRoundTripsCodableStructs() throws {
        let original = Payload(name: "a", count: 2)
        let json = try EngineJSON(encoding: original)
        XCTAssertEqual(json, .object(["name": .string("a"), "count": .integer(2)]))
        XCTAssertEqual(try json.decode(Payload.self), original)
    }
}
