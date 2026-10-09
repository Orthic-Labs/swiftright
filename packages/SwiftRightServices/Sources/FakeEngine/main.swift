import Foundation

// FakeEngine: an independent Swift peer for SwiftRightServices tests. It speaks the RightKit
// framed-sidecar wire envelope (rightkit-framed-sidecar src/wire.rs) and does NOT import the
// client library, so it checks the client against the wire contract, not against itself.
//
// Options: --contract N  --framing jsonl|lp  --engine-version V  --silent  --stubborn
// Methods: echo, sleep{ms,value}, hang, crash (exit 3), error (ok:false), emit (progress +
//          unsolicited events), big{bytes} (oversized response), bye (exit 0).
// Stdin EOF or a bye frame exits 0.

struct PeerOptions {
    var contract = 1
    var framing = "jsonl"
    var version = "0.1.0"
    var silent = false
    var stubborn = false
}

func parseOptions(_ args: [String]) -> PeerOptions {
    var options = PeerOptions()
    var index = 1
    while index < args.count {
        switch args[index] {
        case "--contract": options.contract = Int(args[index + 1]) ?? 1; index += 1
        case "--framing": options.framing = args[index + 1]; index += 1
        case "--engine-version": options.version = args[index + 1]; index += 1
        case "--silent": options.silent = true
        case "--stubborn": options.stubborn = true
        default: break
        }
        index += 1
    }
    return options
}

func intValue(_ value: Any?) -> Int? {
    if let number = value as? NSNumber { return number.intValue }
    return value as? Int
}

final class FakePeer: @unchecked Sendable {
    let options: PeerOptions
    let out = DispatchQueue(label: "fake.engine.out")

    init(options: PeerOptions) {
        self.options = options
    }

    func write(_ object: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
        writeBody(body)
    }

    /// Writes a pre-encoded body. Used where field order matters: serde emits `type` then `id`
    /// first (wire.rs:56-57), which the client's leading-id peek depends on for oversized frames.
    func writeBody(_ body: Data) {
        var frame = Data()
        if options.framing == "lp" {
            var length = UInt32(body.count).bigEndian
            frame.append(Data(bytes: &length, count: 4))
            frame.append(body)
        } else {
            frame.append(body)
            frame.append(0x0A)
        }
        let bytes = frame
        out.async {
            try? FileHandle.standardOutput.write(contentsOf: bytes)
        }
    }

    func flushAndExit(_ status: Int32) -> Never {
        out.sync {}
        exit(status)
    }

    func respond(_ id: Int, result: Any) {
        write(["type": "response", "id": id, "ok": true, "result": result])
    }

    func handle(_ frame: [String: Any]) {
        guard let type = frame["type"] as? String else { return }
        if type == "bye" { flushAndExit(0) }
        guard type == "request", let id = intValue(frame["id"]), let method = frame["method"] as? String else { return }
        let params = frame["params"] ?? NSNull()
        switch method {
        case "echo":
            respond(id, result: params)
        case "sleep":
            let dictionary = params as? [String: Any] ?? [:]
            let ms = intValue(dictionary["ms"]) ?? 0
            let value = intValue(dictionary["value"]) ?? 0
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(ms)) {
                self.respond(id, result: ["value": value])
            }
        case "hang":
            break
        case "crash":
            flushAndExit(3)
        case "error":
            write(["type": "response", "id": id, "ok": false,
                   "error": ["code": "bad_input", "message": "nope", "retryable": true]])
        case "emit":
            write(["type": "event", "id": id, "event": ["step": 1]])
            write(["type": "event", "session_id": "s1", "event": ["note": "hi"]])
            respond(id, result: "done")
        case "big":
            let dictionary = params as? [String: Any] ?? [:]
            let bytes = intValue(dictionary["bytes"]) ?? 0
            let text = #"{"type":"response","id":\#(id),"ok":true,"result":{"blob":""# + String(repeating: "x", count: bytes) + #""}}"#
            writeBody(Data(text.utf8))
        default:
            write(["type": "response", "id": id, "ok": false,
                   "error": ["code": "unknown_method", "message": method, "retryable": false]])
        }
    }

    func run() {
        if options.silent {
            while true { Thread.sleep(forTimeInterval: 60) }
        }
        write(["type": "hello", "engine": "fake", "version": options.version,
               "contract_version": options.contract])
        write(["type": "ready"])
        if options.stubborn {
            while true { Thread.sleep(forTimeInterval: 60) }
        }
        var buffer: [UInt8] = []
        while true {
            let chunk = FileHandle.standardInput.availableData
            guard !chunk.isEmpty else {
                flushAndExit(0)
            }
            buffer.append(contentsOf: chunk)
            if options.framing == "lp" {
                while buffer.count >= 4 {
                    let length = Int(UInt32(buffer[0]) << 24 | UInt32(buffer[1]) << 16
                        | UInt32(buffer[2]) << 8 | UInt32(buffer[3]))
                    guard buffer.count >= 4 + length else { break }
                    let body = Data(buffer[4..<(4 + length)])
                    buffer.removeFirst(4 + length)
                    if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                        handle(object)
                    }
                }
            } else {
                while let newline = buffer.firstIndex(of: 0x0A) {
                    var line = Array(buffer[0..<newline])
                    buffer.removeSubrange(0...newline)
                    if line.last == 0x0D { line.removeLast() }
                    if line.isEmpty { continue }
                    if let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] {
                        handle(object)
                    }
                }
            }
        }
    }
}

FakePeer(options: parseOptions(CommandLine.arguments)).run()
