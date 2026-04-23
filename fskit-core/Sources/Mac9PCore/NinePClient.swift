import Foundation

public final class NinePClient {
    public struct Config: Sendable, Equatable {
        public var host: String
        public var port: Int
        public var user: String?
        public var aname: String?
        public var requestedVersion: String?

        /// Parse a mount string like `9p://user@host:564/?vers=9P2000.u`.
        ///
        /// Note: `Foundation.URL` refuses schemes that start with a digit (like `9p`),
        /// so we parse the string directly instead of relying on `URL(string:)`.
        public static func from(mountString s: String) throws -> Config {
            guard s.hasPrefix("9p://") else { throw POSIXError(.EINVAL) }
            let rest = s.dropFirst("9p://".count)

            let authorityAndPath = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            guard let authority = authorityAndPath.first, !authority.isEmpty else { throw POSIXError(.EINVAL) }

            let pathAndQuery = authorityAndPath.count > 1 ? String(authorityAndPath[1]) : ""
            let query: String? = {
                guard let qmark = pathAndQuery.firstIndex(of: "?") else { return nil }
                return String(pathAndQuery[pathAndQuery.index(after: qmark)...])
            }()

            let userHostPort = String(authority)
            let (userPart, hostPortPart): (String?, String) = {
                if let at = userHostPort.firstIndex(of: "@") {
                    return (String(userHostPort[..<at]), String(userHostPort[userHostPort.index(after: at)...]))
                }
                return (nil, userHostPort)
            }()

            let (host, port): (String, Int) = {
                if let colon = hostPortPart.lastIndex(of: ":") {
                    let h = String(hostPortPart[..<colon])
                    let p = String(hostPortPart[hostPortPart.index(after: colon)...])
                    if let pi = Int(p), !h.isEmpty { return (h, pi) }
                }
                return (hostPortPart, 564)
            }()

            guard !host.isEmpty else { throw POSIXError(.EINVAL) }

            var requestedVersion: String?
            if let query {
                for pair in query.split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1)
                    guard kv.count == 2 else { continue }
                    let k = String(kv[0])
                    let v = String(kv[1])
                    if k == "vers" || k == "version" {
                        requestedVersion = v
                        break
                    }
                }
            }

            // We ignore password-in-URL; treat the entire user part as the username.
            let user = userPart

            return Config(host: host, port: port, user: user, aname: nil, requestedVersion: requestedVersion)
        }

        public static func from(url: URL) throws -> Config {
            try from(mountString: url.absoluteString)
        }
    }

    public let config: Config
    public private(set) var negotiatedVersion: NineP.Version?
    private let sock = NinePSocket()
    private var nextTag: UInt16 = 1
    private var nextFid: UInt32 = 1

    private var rootFid: UInt32?

    public init(config: Config) {
        self.config = config
    }

    public static func versionCandidates(requested: String?) -> [String] {
        if let requested, !requested.isEmpty {
            return Array(LinkedHashSet([requested, "9P2000.L", "9P2000.u", "9P2000"]))
        }
        return ["9P2000.L", "9P2000.u", "9P2000"]
    }

    public func connectAndNegotiate() throws {
        try sock.connect(host: config.host, port: config.port)

        // Negotiate by trying candidates until accepted.
        let candidates = Self.versionCandidates(requested: config.requestedVersion)
        var lastErr: Error?
        for v in candidates {
            do {
                let (msize, chosen) = try rpcTversion(msize: 64 * 1024, version: v)
                _ = msize
                guard let ver = NineP.Version(rawValue: chosen) else { throw POSIXError(.EPROTO) }
                negotiatedVersion = ver
                return
            } catch {
                lastErr = error
            }
        }
        throw lastErr ?? POSIXError(.EPROTO)
    }

    public func disconnect() {
        sock.closeSocket()
    }

    // MARK: - Read-only MVP operations (attach/walk/open/read/readdir/stat)

    public func attach() throws {
        let uname = config.user ?? "none"
        let aname = config.aname ?? ""
        let fid = allocFid()
        // We do no-auth MVP; afid = NOFID (0xFFFFFFFF).
        let (qid) = try rpcTattach(fid: fid, afid: 0xFFFF_FFFF, uname: uname, aname: aname, unamenum: 0)
        _ = qid
        rootFid = fid
    }

    public func walk(from fid: UInt32, newfid: UInt32, names: [String]) throws -> [NineP.Qid] {
        try rpcTwalk(fid: fid, newfid: newfid, names: names)
    }

    public func open(fid: UInt32, mode: UInt8) throws -> (qid: NineP.Qid, iounit: UInt32) {
        try rpcTopen(fid: fid, mode: mode)
    }

    public func read(fid: UInt32, offset: UInt64, count: UInt32) throws -> Data {
        try rpcTread(fid: fid, offset: offset, count: count)
    }

    public func stat(fid: UInt32) throws -> NineP.Stat {
        let raw = try rpcTstat(fid: fid)
        return try NinePWireCodec.decodeStat(raw)
    }

    public func readDir(fid: UInt32) throws -> [NineP.Stat] {
        // Classic 9P directory reads: read repeatedly until empty.
        var offset: UInt64 = 0
        var all = Data()
        while true {
            let chunk = try read(fid: fid, offset: offset, count: 8192)
            if chunk.isEmpty { break }
            all.append(chunk)
            offset += UInt64(chunk.count)
            if chunk.count < 8192 { break }
        }
        return try NinePWireCodec.splitDirReadIntoStats(all)
    }

    public func clunk(fid: UInt32) throws {
        _ = try rpcTclunk(fid: fid)
    }

    // MARK: - Internal RPC helpers

    private func allocTag() -> UInt16 { defer { nextTag &+= 1 }; return nextTag }
    private func allocFid() -> UInt32 { defer { nextFid &+= 1 }; return nextFid }

    private func rpc(_ type: NineP.MsgType, body: Data) throws -> (rtype: NineP.MsgType, tag: UInt16, body: Data) {
        let tag = allocTag()
        let msg = NinePWireCodec.encodeMessage(type: type, tag: tag, body: body)
        try sock.sendAll(msg)
        let rx = try sock.recvMessage()
        let (_, rtype, rtag, rbody) = try NinePWireCodec.decodeHeader(rx)
        guard rtag == tag || rtag == 0xFFFF else { throw POSIXError(.EPROTO) }
        if rtype == .rerror {
            var rr = NinePDataCodec.Reader(rbody)
            let ename = try rr.string()
            throw NSError(domain: "NineP", code: Int(EPROTO), userInfo: [NSLocalizedDescriptionKey: ename])
        }
        return (rtype, rtag, rbody)
    }

    private func rpcTversion(msize: UInt32, version: String) throws -> (msize: UInt32, version: String) {
        var w = NinePDataCodec.Writer()
        w.u32(msize)
        w.string(version)
        let (rtype, _, body) = try rpc(.tversion, body: w.data)
        guard rtype == .rversion else { throw POSIXError(.EPROTO) }
        var r = NinePDataCodec.Reader(body)
        let rMsize = try r.u32()
        let rVer = try r.string()
        return (rMsize, rVer)
    }

    private func rpcTattach(fid: UInt32, afid: UInt32, uname: String, aname: String, unamenum: UInt32) throws -> NineP.Qid {
        var w = NinePDataCodec.Writer()
        w.u32(fid)
        w.u32(afid)
        w.string(uname)
        w.string(aname)
        // We always send unamenum (server may ignore if not dotu); harmless for MVP.
        w.u32(unamenum)
        let (rtype, _, body) = try rpc(.tattach, body: w.data)
        guard rtype == .rattach else { throw POSIXError(.EPROTO) }
        var r = NinePDataCodec.Reader(body)
        return try NinePWireCodec.decodeQid(&r)
    }

    private func rpcTwalk(fid: UInt32, newfid: UInt32, names: [String]) throws -> [NineP.Qid] {
        var w = NinePDataCodec.Writer()
        w.u32(fid)
        w.u32(newfid)
        w.u16(UInt16(names.count))
        for n in names { w.string(n) }
        let (rtype, _, body) = try rpc(.twalk, body: w.data)
        guard rtype == .rwalk else { throw POSIXError(.EPROTO) }
        var r = NinePDataCodec.Reader(body)
        let nwqid = Int(try r.u16())
        var q: [NineP.Qid] = []
        q.reserveCapacity(nwqid)
        for _ in 0..<nwqid { q.append(try NinePWireCodec.decodeQid(&r)) }
        return q
    }

    private func rpcTopen(fid: UInt32, mode: UInt8) throws -> (NineP.Qid, UInt32) {
        var w = NinePDataCodec.Writer()
        w.u32(fid)
        w.u8(mode)
        let (rtype, _, body) = try rpc(.topen, body: w.data)
        guard rtype == .ropen else { throw POSIXError(.EPROTO) }
        var r = NinePDataCodec.Reader(body)
        let qid = try NinePWireCodec.decodeQid(&r)
        let iounit = try r.u32()
        return (qid, iounit)
    }

    private func rpcTread(fid: UInt32, offset: UInt64, count: UInt32) throws -> Data {
        var w = NinePDataCodec.Writer()
        w.u32(fid)
        w.u64(offset)
        w.u32(count)
        let (rtype, _, body) = try rpc(.tread, body: w.data)
        guard rtype == .rread else { throw POSIXError(.EPROTO) }
        var r = NinePDataCodec.Reader(body)
        let n = Int(try r.u32())
        return try r.bytes(n)
    }

    private func rpcTclunk(fid: UInt32) throws -> Void {
        var w = NinePDataCodec.Writer()
        w.u32(fid)
        let (rtype, _, _) = try rpc(.tclunk, body: w.data)
        guard rtype == .rclunk else { throw POSIXError(.EPROTO) }
    }

    private func rpcTstat(fid: UInt32) throws -> Data {
        var w = NinePDataCodec.Writer()
        w.u32(fid)
        let (rtype, _, body) = try rpc(.tstat, body: w.data)
        guard rtype == .rstat else { throw POSIXError(.EPROTO) }
        var r = NinePDataCodec.Reader(body)
        let nstat = Int(try r.u16())
        return try r.bytes(nstat)
    }
}

/// Tiny insertion-ordered set helper so tests can check stable ordering.
private struct LinkedHashSet<Element: Hashable>: Sequence {
    private var seen: Set<Element> = []
    private var ordered: [Element] = []

    init(_ elements: [Element]) {
        for e in elements {
            if seen.insert(e).inserted {
                ordered.append(e)
            }
        }
    }

    func makeIterator() -> Array<Element>.Iterator { ordered.makeIterator() }
}

