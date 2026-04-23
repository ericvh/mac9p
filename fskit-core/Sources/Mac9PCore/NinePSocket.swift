import Foundation
import Darwin

final class NinePSocket {
    private var fd: Int32 = -1

    func connect(host: String, port: Int) throws {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )

        var res: UnsafeMutablePointer<addrinfo>?
        let err = getaddrinfo(host, String(port), &hints, &res)
        guard err == 0, let head = res else { throw POSIXError(.EHOSTUNREACH) }
        defer { freeaddrinfo(head) }

        var lastErr: Int32 = ECONNREFUSED
        var p: UnsafeMutablePointer<addrinfo>? = head
        while let ai = p {
            let s = socket(ai.pointee.ai_family, ai.pointee.ai_socktype, ai.pointee.ai_protocol)
            if s < 0 {
                lastErr = errno
                p = ai.pointee.ai_next
                continue
            }
            if Darwin.connect(s, ai.pointee.ai_addr, ai.pointee.ai_addrlen) == 0 {
                fd = s
                return
            }
            lastErr = errno
            close(s)
            p = ai.pointee.ai_next
        }
        throw POSIXError(POSIXError.Code(rawValue: lastErr) ?? .ECONNREFUSED)
    }

    func closeSocket() {
        if fd >= 0 { _ = Darwin.close(fd); fd = -1 }
    }

    func sendAll(_ data: Data) throws {
        try data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            var sent = 0
            while sent < buf.count {
                let n = Darwin.send(fd, buf.baseAddress!.advanced(by: sent), buf.count - sent, 0)
                if n < 0 { throw POSIXError(POSIXError.Code(rawValue: errno) ?? .EIO) }
                sent += n
            }
        }
    }

    func recvExactly(_ n: Int) throws -> Data {
        var out = Data(count: n)
        try out.withUnsafeMutableBytes { (buf: UnsafeMutableRawBufferPointer) in
            var got = 0
            while got < buf.count {
                let r = Darwin.recv(fd, buf.baseAddress!.advanced(by: got), buf.count - got, 0)
                if r == 0 { throw POSIXError(.ECONNRESET) }
                if r < 0 { throw POSIXError(POSIXError.Code(rawValue: errno) ?? .EIO) }
                got += r
            }
        }
        return out
    }

    func recvMessage() throws -> Data {
        let hdr = try recvExactly(4)
        let size = Int(UInt32(hdr[0]) | (UInt32(hdr[1]) << 8) | (UInt32(hdr[2]) << 16) | (UInt32(hdr[3]) << 24))
        guard size >= 7 else { throw POSIXError(.EBADMSG) }
        let rest = try recvExactly(size - 4)
        return hdr + rest
    }
}

