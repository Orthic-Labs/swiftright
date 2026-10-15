import Foundation

/// RFC 1950 (zlib) / RFC 1951 (deflate) decoder written in Swift, so the Windows host needs no zlib. Used by the PNG decoder.
/// Strict: a bad header, bad block, bad back-reference, a truncated stream, output over `limit` or a wrong Adler-32 throws.
enum Inflate {
    enum Failure: Error, Equatable {
        case header, truncated, block, huffman, distance, overflow, checksum
    }

    private struct Huffman {
        var count = [UInt16](repeating: 0, count: 16)
        var symbol: [UInt16]

        /// Nil when the lengths over-subscribe the code (an invalid set); incomplete codes are accepted (a lone distance code).
        init?(lengths: [UInt8]) {
            symbol = [UInt16](repeating: 0, count: lengths.count)
            for length in lengths { count[Int(length)] += 1 }
            var left = 1
            for len in 1..<16 {
                left <<= 1
                left -= Int(count[len])
                if left < 0 { return nil }
            }
            var offsets = [Int](repeating: 0, count: 16)
            for len in 1..<15 { offsets[len + 1] = offsets[len] + Int(count[len]) }
            for (sym, length) in lengths.enumerated() where length != 0 {
                symbol[offsets[Int(length)]] = UInt16(sym)
                offsets[Int(length)] += 1
            }
        }
    }

    private static let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
    private static let clOrder: [Int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    private static let fixedTables: (Huffman, Huffman) = {
        var l = [UInt8](repeating: 8, count: 288)
        for i in 144..<256 { l[i] = 9 }
        for i in 256..<280 { l[i] = 7 }
        return (Huffman(lengths: l)!, Huffman(lengths: [UInt8](repeating: 5, count: 30))!)
    }()

    private struct Reader {
        let data: [UInt8]
        var pos: Int
        var end: Int
        var bitBuf: UInt32 = 0
        var bitCount = 0

        mutating func bits(_ n: Int) throws -> Int {
            while bitCount < n {
                guard pos < end else { throw Failure.truncated }
                bitBuf |= UInt32(data[pos]) << UInt32(bitCount)
                pos += 1
                bitCount += 8
            }
            let value = Int(bitBuf & ((1 << UInt32(n)) - 1))
            bitBuf >>= UInt32(n)
            bitCount -= n
            return value
        }

        mutating func decode(_ h: Huffman) throws -> Int {
            var code = 0, first = 0, index = 0
            for len in 1..<16 {
                code |= try bits(1)
                let count = Int(h.count[len])
                if code - count < first { return Int(h.symbol[index + (code - first)]) }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw Failure.huffman
        }
    }

    /// Decodes a zlib stream (`data[range]`). `limit` bounds the output size.
    static func zlibDecompress(_ data: [UInt8], limit: Int) throws -> [UInt8] {
        guard data.count >= 6 else { throw Failure.truncated }
        let cmf = Int(data[0]), flg = Int(data[1])
        guard cmf & 0x0f == 8, cmf >> 4 <= 7, (cmf << 8 | flg) % 31 == 0, flg & 0x20 == 0 else { throw Failure.header }
        var reader = Reader(data: data, pos: 2, end: data.count - 4)
        var out = [UInt8]()
        out.reserveCapacity(min(limit, 1 << 24))
        var final = false
        while !final {
            final = try reader.bits(1) == 1
            switch try reader.bits(2) {
            case 0:
                reader.bitBuf = 0; reader.bitCount = 0
                guard reader.pos + 4 <= reader.end else { throw Failure.truncated }
                let len = Int(data[reader.pos]) | Int(data[reader.pos + 1]) << 8
                let nlen = Int(data[reader.pos + 2]) | Int(data[reader.pos + 3]) << 8
                guard len == (~nlen & 0xffff) else { throw Failure.block }
                reader.pos += 4
                guard reader.pos + len <= reader.end else { throw Failure.truncated }
                guard out.count + len <= limit else { throw Failure.overflow }
                out.append(contentsOf: data[reader.pos..<reader.pos + len])
                reader.pos += len
            case 1:
                try codes(&reader, &out, fixedTables.0, fixedTables.1, limit)
            case 2:
                let nlen = try reader.bits(5) + 257, ndist = try reader.bits(5) + 1, ncode = try reader.bits(4) + 4
                guard nlen <= 286, ndist <= 30 else { throw Failure.block }
                var cl = [UInt8](repeating: 0, count: 19)
                for i in 0..<ncode { cl[clOrder[i]] = UInt8(try reader.bits(3)) }
                guard let clTable = Huffman(lengths: cl) else { throw Failure.huffman }
                var lengths = [UInt8](repeating: 0, count: nlen + ndist)
                var i = 0
                while i < nlen + ndist {
                    let sym = try reader.decode(clTable)
                    if sym < 16 { lengths[i] = UInt8(sym); i += 1; continue }
                    var value: UInt8 = 0, repeatCount: Int
                    switch sym {
                    case 16:
                        guard i > 0 else { throw Failure.block }
                        value = lengths[i - 1]; repeatCount = 3 + (try reader.bits(2))
                    case 17: repeatCount = 3 + (try reader.bits(3))
                    default: repeatCount = 11 + (try reader.bits(7))
                    }
                    guard i + repeatCount <= nlen + ndist else { throw Failure.block }
                    for _ in 0..<repeatCount { lengths[i] = value; i += 1 }
                }
                guard lengths[256] != 0 else { throw Failure.block }
                guard let lit = Huffman(lengths: Array(lengths[0..<nlen])),
                      let dist = Huffman(lengths: Array(lengths[nlen...])) else { throw Failure.huffman }
                try codes(&reader, &out, lit, dist, limit)
            default:
                throw Failure.block
            }
        }
        let t = data.count - 4
        let expected = UInt32(data[t]) << 24 | UInt32(data[t + 1]) << 16 | UInt32(data[t + 2]) << 8 | UInt32(data[t + 3])
        guard adler32(out) == expected else { throw Failure.checksum }
        return out
    }

    private static func codes(_ reader: inout Reader, _ out: inout [UInt8], _ lit: Huffman, _ dist: Huffman, _ limit: Int) throws {
        while true {
            let sym = try reader.decode(lit)
            if sym < 256 {
                guard out.count < limit else { throw Failure.overflow }
                out.append(UInt8(sym))
            } else if sym == 256 {
                return
            } else {
                let s = sym - 257
                guard s < 29 else { throw Failure.block }
                let length = lengthBase[s] + (try reader.bits(lengthExtra[s]))
                let ds = try reader.decode(dist)
                guard ds < 30 else { throw Failure.block }
                let distance = distBase[ds] + (try reader.bits(distExtra[ds]))
                guard distance <= out.count else { throw Failure.distance }
                guard out.count + length <= limit else { throw Failure.overflow }
                var from = out.count - distance
                for _ in 0..<length { out.append(out[from]); from += 1 }
            }
        }
    }

    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        var i = 0
        while i < bytes.count {
            let end = min(i + 5552, bytes.count)
            while i < end { a &+= UInt32(bytes[i]); b &+= a; i += 1 }
            a %= 65521; b %= 65521
        }
        return b << 16 | a
    }

    static func crc32(_ bytes: ArraySlice<UInt8>) -> UInt32 {
        var crc: UInt32 = 0xffff_ffff
        for byte in bytes { crc = crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8) }
        return ~crc
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xedb8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }
}
