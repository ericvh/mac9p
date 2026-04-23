import Foundation

/// Async 9P client with tag-based reply multiplexing.
///
/// Design:
/// - A single reader task continuously reads messages from the socket.
/// - Requests allocate a unique tag and register a continuation in `inflight`.
/// - Responses are matched by tag and resume the appropriate waiter.
///
/// This allows multiple concurrent operations to share one connection safely.
public actor NinePAsyncClient {
    public let config: NinePClient.Config
    public private(set) var negotiatedVersion: NineP.Version?

    private let sock = NinePSocket()
    private var readerTask: Task<Void, Never>?

    private var nextTag: UInt16 = 1
    private var nextFid: UInt32 = 1

    private var rootFid: UInt32?

    private struct Inflight {
        let expectedType: NineP.MsgType
        let continuation: CheckedContinuation<Data, Error>
    }
    private var inflight: [UInt16: Inflight] = [:]

    public init(config: NinePClient.Config) {
        self.config = config
    }

    deinit {
        readerTask?.cancel()
        sock.closeSocket()
    }

    // MARK: - Connection lifecycle

    public func connectAndNegotiate() async throws {
        try sock.connect(host: config.host, port: config.port)
        startReaderIfNeeded()

        let candidates = NinePClient.versionCandidates(requested: config.requestedVersion)
        var lastErr: Error?
        for v in candidates {
            do {
                let (msize, chosen) = try await rpcTversion(msize: 64 * 1024, version: v)
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
        readerTask?.cancel()
        readerTask = nil
        sock.closeSocket()

        // Fail all inflight waiters.
        let err = POSIXError(.ECONNRESET)
        for (tag, entry) in inflight {
            inflight[tag] = nil
            entry.continuation.resume(throwing: err)
        }
    }

    private func startReaderIfNeeded() {
        guard readerTask == nil else { return }
        let socket = sock
        readerTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    let msg = try socket.recvMessage()
                    await self.handleIncoming(msg)
                } catch {
                    await self.failAllInflight(error)
                    return
                }
            }
        }
    }

    private func failAllInflight(_ error: Error) {
        for (tag, entry) in inflight {
            inflight[tag] = nil
            entry.continuation.resume(throwing: error)
        }
    }

    private func handleIncoming(_ msg: Data) async {
        do {
            let (_, rtype, tag, body) = try NinePWireCodec.decodeHeader(msg)

            if rtype == .rerror {
                var rr = NinePDataCodec.Reader(body)
                let ename = (try? rr.string()) ?? "9P error"
                let err = NSError(domain: "NineP", code: Int(EPROTO), userInfo: [NSLocalizedDescriptionKey: ename])
                if let entry = inflight.removeValue(forKey: tag) {
                    entry.continuation.resume(throwing: err)
                }
                return
            }

            guard let entry = inflight.removeValue(forKey: tag) else {
                // Unknown tag; ignore.
                return
            }
            guard rtype == entry.expectedType else {
                entry.continuation.resume(throwing: POSIXError(.EPROTO))
                return
            }
            entry.continuation.resume(returning: body)
        } catch {
            failAllInflight(error)
        }
    }

    // MARK: - Read-only MVP operations

    public func attach() async throws {
        let uname = config.user ?? "none"
        let aname = config.aname ?? ""
        let fid = allocFid()
        let _ = try await rpcTattach(fid: fid, afid: 0xFFFF_FFFF, uname: uname, aname: aname, unamenum: 0)
        rootFid = fid
    }

    public func root() throws -> UInt32 {
        guard let r = rootFid else { throw POSIXError(.EINVAL) }
        return r
    }

    /// Allocate a new fid value for use in walk/open operations.
    public func allocateFid() -> UInt32 {
        allocFid()
    }

    public func walk(from fid: UInt32, newfid: UInt32, names: [String]) async throws -> [NineP.Qid] {
        try await rpcTwalk(fid: fid, newfid: newfid, names: names)
    }

    public func open(fid: UInt32, mode: UInt8) async throws -> (qid: NineP.Qid, iounit: UInt32) {
        try await rpcTopen(fid: fid, mode: mode)
    }

    public func read(fid: UInt32, offset: UInt64, count: UInt32) async throws -> Data {
        try await rpcTread(fid: fid, offset: offset, count: count)
    }

    public func stat(fid: UInt32) async throws -> NineP.Stat {
        let raw = try await rpcTstat(fid: fid)
        return try NinePWireCodec.decodeStat(raw)
    }

    public func readDir(fid: UInt32) async throws -> [NineP.Stat] {
        var offset: UInt64 = 0
        var all = Data()
        while true {
            let chunk = try await read(fid: fid, offset: offset, count: 8192)
            if chunk.isEmpty { break }
            all.append(chunk)
            offset += UInt64(chunk.count)
            if chunk.count < 8192 { break }
        }
        return try NinePWireCodec.splitDirReadIntoStats(all)
    }

    public func clunk(fid: UInt32) async throws {
        _ = try await rpcTclunk(fid: fid)
    }

    // MARK: - Internal RPC

    private func allocTag() -> UInt16 {
        // Tags are 16-bit; skip 0xFFFF (NOTAG).
        while true {
            let t = nextTag
            nextTag &+= 1
            if t != 0xFFFF, inflight[t] == nil { return t }
        }
    }

    private func allocFid() -> UInt32 { defer { nextFid &+= 1 }; return nextFid }

    private func rpcAsync(tType: NineP.MsgType, rType: NineP.MsgType, body: Data) async throws -> Data {
        let tag = allocTag()
        let msg = NinePWireCodec.encodeMessage(type: tType, tag: tag, body: body)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                inflight[tag] = Inflight(expectedType: rType, continuation: cont)
                do {
                    try sock.sendAll(msg)
                } catch {
                    inflight[tag] = nil
                    cont.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { [weak self] in
                await self?.cancel(tag: tag)
            }
        }
    }

    private func cancel(tag: UInt16) {
        if let entry = inflight.removeValue(forKey: tag) {
            entry.continuation.resume(throwing: CancellationError())
        }
    }

    private func rpcTversion(msize: UInt32, version: String) async throws -> (msize: UInt32, version: String) {
        var w = NinePDataCodec.Writer()
        w.u32(msize)
        w.string(version)
        let body = try await rpcAsync(tType: .tversion, rType: .rversion, body: w.data)
        var r = NinePDataCodec.Reader(body)
        return (try r.u32(), try r.string())
    }

    private func rpcTattach(fid: UInt32, afid: UInt32, uname: String, aname: String, unamenum: UInt32) async throws -> NineP.Qid {
        var w = NinePDataCodec.Writer()
        w.u32(fid)
        w.u32(afid)
        w.string(uname)
        w.string(aname)
        w.u32(unamenum)
        let body = try await rpcAsync(tType: .tattach, rType: .rattach, body: w.data)
        var r = NinePDataCodec.Reader(body)
        return try NinePWireCodec.decodeQid(&r)
    }

    private func rpcTwalk(fid: UInt32, newfid: UInt32, names: [String]) async throws -> [NineP.Qid] {
        var w = NinePDataCodec.Writer()
        w.u32(fid)
        w.u32(newfid)
        w.u16(UInt16(names.count))
        for n in names { w.string(n) }
        let body = try await rpcAsync(tType: .twalk, rType: .rwalk, body: w.data)
        var r = NinePDataCodec.Reader(body)
        let nwqid = Int(try r.u16())
        return try (0..<nwqid).map { _ in try NinePWireCodec.decodeQid(&r) }
    }

    private func rpcTopen(fid: UInt32, mode: UInt8) async throws -> (NineP.Qid, UInt32) {
        var w = NinePDataCodec.Writer()
        w.u32(fid)
        w.u8(mode)
        let body = try await rpcAsync(tType: .topen, rType: .ropen, body: w.data)
        var r = NinePDataCodec.Reader(body)
        return (try NinePWireCodec.decodeQid(&r), try r.u32())
    }

    private func rpcTread(fid: UInt32, offset: UInt64, count: UInt32) async throws -> Data {
        var w = NinePDataCodec.Writer()
        w.u32(fid)
        w.u64(offset)
        w.u32(count)
        let body = try await rpcAsync(tType: .tread, rType: .rread, body: w.data)
        var r = NinePDataCodec.Reader(body)
        let n = Int(try r.u32())
        return try r.bytes(n)
    }

    private func rpcTclunk(fid: UInt32) async throws {
        var w = NinePDataCodec.Writer()
        w.u32(fid)
        _ = try await rpcAsync(tType: .tclunk, rType: .rclunk, body: w.data)
    }

    private func rpcTstat(fid: UInt32) async throws -> Data {
        var w = NinePDataCodec.Writer()
        w.u32(fid)
        let body = try await rpcAsync(tType: .tstat, rType: .rstat, body: w.data)
        var r = NinePDataCodec.Reader(body)
        let n = Int(try r.u16())
        return try r.bytes(n)
    }
}

