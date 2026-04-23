import Foundation

enum NinePWireCodec {
    static func encodeMessage(type: NineP.MsgType, tag: UInt16, body: Data) -> Data {
        var w = NinePDataCodec.Writer()
        // size (u32) placeholder
        w.u32(0)
        w.u8(type.rawValue)
        w.u16(tag)
        w.bytes(body)
        var msg = w.data
        let size = UInt32(msg.count)
        // patch size
        msg[0] = UInt8(truncatingIfNeeded: size)
        msg[1] = UInt8(truncatingIfNeeded: size >> 8)
        msg[2] = UInt8(truncatingIfNeeded: size >> 16)
        msg[3] = UInt8(truncatingIfNeeded: size >> 24)
        return msg
    }

    static func decodeHeader(_ msg: Data) throws -> (size: UInt32, type: NineP.MsgType, tag: UInt16, body: Data) {
        var r = NinePDataCodec.Reader(msg)
        let size = try r.u32()
        guard size == msg.count else { throw POSIXError(.EBADMSG) }
        guard let type = NineP.MsgType(rawValue: try r.u8()) else { throw POSIXError(.EPROTO) }
        let tag = try r.u16()
        let body = Data(msg[r.idx...])
        return (size, type, tag, body)
    }

    static func encodeQid(_ q: NineP.Qid) -> Data {
        var w = NinePDataCodec.Writer()
        w.u8(q.type)
        w.u32(q.vers)
        w.u64(q.path)
        return w.data
    }

    static func decodeQid(_ r: inout NinePDataCodec.Reader) throws -> NineP.Qid {
        NineP.Qid(type: try r.u8(), vers: try r.u32(), path: try r.u64())
    }

    static func decodeStat(_ statData: Data) throws -> NineP.Stat {
        // stat format starts with 2-byte size (not including itself)
        var r = NinePDataCodec.Reader(statData)
        _ = try r.u16() // size
        _ = try r.u16() // type
        _ = try r.u32() // dev
        let qid = try decodeQid(&r)
        let mode = try r.u32()
        let atime = try r.u32()
        let mtime = try r.u32()
        let length = try r.u64()
        let name = try r.string()
        let uid = try r.string()
        let gid = try r.string()
        let muid = try r.string()
        return NineP.Stat(qid: qid, mode: mode, atime: atime, mtime: mtime, length: length, name: name, uid: uid, gid: gid, muid: muid)
    }

    static func splitDirReadIntoStats(_ data: Data) throws -> [NineP.Stat] {
        var stats: [NineP.Stat] = []
        var idx = data.startIndex
        while idx < data.endIndex {
            guard data.count - idx >= 2 else { throw POSIXError(.EBADMSG) }
            let sz = Int(UInt16(data[idx]) | (UInt16(data[data.index(after: idx)]) << 8))
            let total = 2 + sz
            guard data.count - idx >= total else { throw POSIXError(.EBADMSG) }
            let slice = Data(data[idx ..< data.index(idx, offsetBy: total)])
            stats.append(try decodeStat(slice))
            idx = data.index(idx, offsetBy: total)
        }
        return stats
    }
}

