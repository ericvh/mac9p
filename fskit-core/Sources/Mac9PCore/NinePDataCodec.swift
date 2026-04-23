import Foundation

enum NinePDataCodec {
    struct Reader {
        var data: Data
        var idx: Data.Index = 0

        init(_ data: Data) { self.data = data; self.idx = data.startIndex }

        mutating func need(_ n: Int) throws {
            guard data.count - idx >= n else { throw POSIXError(.EBADMSG) }
        }

        mutating func u8() throws -> UInt8 {
            try need(1)
            let v = data[idx]
            idx = data.index(after: idx)
            return v
        }

        mutating func u16() throws -> UInt16 {
            let b0 = UInt16(try u8())
            let b1 = UInt16(try u8())
            return b0 | (b1 << 8)
        }

        mutating func u32() throws -> UInt32 {
            let b0 = UInt32(try u8())
            let b1 = UInt32(try u8())
            let b2 = UInt32(try u8())
            let b3 = UInt32(try u8())
            return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
        }

        mutating func u64() throws -> UInt64 {
            let lo = UInt64(try u32())
            let hi = UInt64(try u32())
            return lo | (hi << 32)
        }

        mutating func bytes(_ n: Int) throws -> Data {
            try need(n)
            let out = data[idx ..< data.index(idx, offsetBy: n)]
            idx = data.index(idx, offsetBy: n)
            return Data(out)
        }

        mutating func string() throws -> String {
            let n = Int(try u16())
            let b = try bytes(n)
            guard let s = String(data: b, encoding: .utf8) else { throw POSIXError(.EBADMSG) }
            return s
        }
    }

    struct Writer {
        var data = Data()
        mutating func u8(_ v: UInt8) { data.append(v) }
        mutating func u16(_ v: UInt16) { u8(UInt8(truncatingIfNeeded: v)); u8(UInt8(truncatingIfNeeded: v >> 8)) }
        mutating func u32(_ v: UInt32) {
            u8(UInt8(truncatingIfNeeded: v))
            u8(UInt8(truncatingIfNeeded: v >> 8))
            u8(UInt8(truncatingIfNeeded: v >> 16))
            u8(UInt8(truncatingIfNeeded: v >> 24))
        }
        mutating func u64(_ v: UInt64) { u32(UInt32(truncatingIfNeeded: v)); u32(UInt32(truncatingIfNeeded: v >> 32)) }
        mutating func bytes(_ d: Data) { data.append(d) }
        mutating func string(_ s: String) {
            let b = s.data(using: .utf8) ?? Data()
            u16(UInt16(b.count))
            bytes(b)
        }
    }
}

