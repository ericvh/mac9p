import Foundation
import Darwin
@testable import Mac9PCore

/// Minimal 9P2000 mock server for readonly MVP tests (BSD sockets).
final class Mock9PServer {
    private var listenFD: Int32 = -1
    private var acceptThread: Thread?
    private(set) var port: UInt16 = 0

    // file tree: / (dir) contains hello.txt
    private let helloContent = Data("hello\n".utf8)

    private struct Node {
        enum Kind { case dir, file }
        var kind: Kind
        var name: String
        var qid: NineP.Qid
    }

    private let root = Node(kind: .dir, name: "/", qid: .init(type: 0x80, vers: 1, path: 1))
    private let hello = Node(kind: .file, name: "hello.txt", qid: .init(type: 0x00, vers: 1, path: 2))

    private var fidToNode: [UInt32: Node] = [:]

    init() throws {
        listenFD = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard listenFD >= 0 else { throw POSIXError(.EIO) }

        var yes: Int32 = 1
        _ = setsockopt(listenFD, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(0).bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let bindRes = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                Darwin.bind(listenFD, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindRes == 0 else { throw POSIXError(POSIXError.Code(rawValue: errno) ?? .EIO) }

        guard listen(listenFD, 4) == 0 else { throw POSIXError(.EIO) }

        // Discover assigned port
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        var bound = sockaddr_in()
        let gs = withUnsafeMutablePointer(to: &bound) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                getsockname(listenFD, sa, &len)
            }
        }
        guard gs == 0 else { throw POSIXError(.EIO) }
        port = UInt16(bigEndian: bound.sin_port)

        acceptThread = Thread { [weak self] in
            self?.acceptLoop()
        }
        acceptThread?.start()
    }

    func stop() {
        if listenFD >= 0 { _ = Darwin.close(listenFD); listenFD = -1 }
    }

    private func acceptLoop() {
        while listenFD >= 0 {
            var addr = sockaddr()
            var len: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
            let cfd = Darwin.accept(listenFD, &addr, &len)
            if cfd < 0 { break }
            Thread { [weak self] in
                self?.serveClient(fd: cfd)
                _ = Darwin.close(cfd)
            }.start()
        }
    }

    private func recvExact(fd: Int32, n: Int) -> Data? {
        var out = Data(count: n)
        let ok: Bool = out.withUnsafeMutableBytes { buf in
            var got = 0
            while got < n {
                let r = Darwin.recv(fd, buf.baseAddress!.advanced(by: got), n - got, 0)
                if r <= 0 { return false }
                got += r
            }
            return true
        }
        return ok ? out : nil
    }

    private func sendAll(fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { buf in
            var sent = 0
            while sent < buf.count {
                let n = Darwin.send(fd, buf.baseAddress!.advanced(by: sent), buf.count - sent, 0)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    private func serveClient(fd: Int32) {
        while true {
            guard let hdr = recvExact(fd: fd, n: 4) else { return }
            let size = Int(UInt32(hdr[0]) | (UInt32(hdr[1]) << 8) | (UInt32(hdr[2]) << 16) | (UInt32(hdr[3]) << 24))
            guard size >= 7, let rest = recvExact(fd: fd, n: size - 4) else { return }
            let msg = hdr + rest
            do {
                let (_, t, tag, body) = try NinePWireCodec.decodeHeader(msg)
                let reply = try dispatch(type: t, tag: tag, body: body)
                guard sendAll(fd: fd, data: reply) else { return }
            } catch {
                return
            }
        }
    }

    private func dispatch(type: NineP.MsgType, tag: UInt16, body: Data) throws -> Data {
        switch type {
        case .tversion:
            var r = NinePDataCodec.Reader(body)
            let msize = try r.u32()
            _ = try r.string()
            var w = NinePDataCodec.Writer()
            w.u32(msize)
            w.string(NineP.Version.v2000.rawValue)
            return NinePWireCodec.encodeMessage(type: .rversion, tag: tag, body: w.data)
        case .tattach:
            var r = NinePDataCodec.Reader(body)
            let fid = try r.u32()
            _ = try r.u32() // afid
            _ = try r.string() // uname
            _ = try r.string() // aname
            _ = try? r.u32() // unamenum (optional-ish)
            fidToNode[fid] = root
            var w = NinePDataCodec.Writer()
            w.bytes(NinePWireCodec.encodeQid(root.qid))
            return NinePWireCodec.encodeMessage(type: .rattach, tag: tag, body: w.data)
        case .twalk:
            var r = NinePDataCodec.Reader(body)
            let fid = try r.u32()
            let newfid = try r.u32()
            let nwname = Int(try r.u16())
            let names = (0..<nwname).map { _ in (try? r.string()) ?? "" }
            guard let start = fidToNode[fid] else { throw POSIXError(.ENOENT) }
            if nwname == 0 {
                fidToNode[newfid] = start
                var w = NinePDataCodec.Writer()
                w.u16(0)
                return NinePWireCodec.encodeMessage(type: .rwalk, tag: tag, body: w.data)
            }
            if start.kind == .dir, names == ["hello.txt"] {
                fidToNode[newfid] = hello
                var w = NinePDataCodec.Writer()
                w.u16(1)
                w.bytes(NinePWireCodec.encodeQid(hello.qid))
                return NinePWireCodec.encodeMessage(type: .rwalk, tag: tag, body: w.data)
            }
            return rerror(tag: tag, ename: "file does not exist")
        case .topen:
            var r = NinePDataCodec.Reader(body)
            let fid = try r.u32()
            _ = try r.u8()
            guard let node = fidToNode[fid] else { return rerror(tag: tag, ename: "unknown fid") }
            var w = NinePDataCodec.Writer()
            w.bytes(NinePWireCodec.encodeQid(node.qid))
            w.u32(0)
            return NinePWireCodec.encodeMessage(type: .ropen, tag: tag, body: w.data)
        case .tread:
            var r = NinePDataCodec.Reader(body)
            let fid = try r.u32()
            let offset = try r.u64()
            let count = Int(try r.u32())
            guard let node = fidToNode[fid] else { return rerror(tag: tag, ename: "unknown fid") }
            let payload: Data
            if node.kind == .file {
                let start = min(Int(offset), helloContent.count)
                let end = min(start + count, helloContent.count)
                payload = helloContent.subdata(in: start..<end)
            } else {
                // directory read: return one stat entry for hello.txt
                payload = try encodeDirListing()
            }
            var w = NinePDataCodec.Writer()
            w.u32(UInt32(payload.count))
            w.bytes(payload)
            return NinePWireCodec.encodeMessage(type: .rread, tag: tag, body: w.data)
        case .tstat:
            var r = NinePDataCodec.Reader(body)
            let fid = try r.u32()
            guard let node = fidToNode[fid] else { return rerror(tag: tag, ename: "unknown fid") }
            let stat = try encodeStat(node: node)
            var w = NinePDataCodec.Writer()
            w.u16(UInt16(stat.count))
            w.bytes(stat)
            return NinePWireCodec.encodeMessage(type: .rstat, tag: tag, body: w.data)
        case .tclunk:
            var r = NinePDataCodec.Reader(body)
            let fid = try r.u32()
            fidToNode.removeValue(forKey: fid)
            return NinePWireCodec.encodeMessage(type: .rclunk, tag: tag, body: Data())
        default:
            return rerror(tag: tag, ename: "unsupported")
        }
    }

    private func rerror(tag: UInt16, ename: String) -> Data {
        var w = NinePDataCodec.Writer()
        w.string(ename)
        return NinePWireCodec.encodeMessage(type: .rerror, tag: tag, body: w.data)
    }

    private func encodeStat(node: Node) throws -> Data {
        var w = NinePDataCodec.Writer()
        // We'll build into a buffer so we can prefix with size.
        var inner = NinePDataCodec.Writer()
        inner.u16(0) // type
        inner.u32(0) // dev
        inner.bytes(NinePWireCodec.encodeQid(node.qid))
        inner.u32(node.kind == .dir ? 0x80000000 | 0o755 : 0o644) // mode
        inner.u32(0) // atime
        inner.u32(0) // mtime
        inner.u64(UInt64(node.kind == .file ? helloContent.count : 0))
        inner.string(node.name)
        inner.string("u")
        inner.string("g")
        inner.string("m")

        w.u16(UInt16(inner.data.count))
        w.bytes(inner.data)
        return w.data
    }

    private func encodeDirListing() throws -> Data {
        // Directory read returns concatenated stat entries (each begins with 2-byte size).
        let stat = try encodeStat(node: hello)
        return stat
    }
}

