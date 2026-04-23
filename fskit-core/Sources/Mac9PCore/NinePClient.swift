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

    public enum NegotiatedVersion: String, Equatable {
        case v2000 = "9P2000"
        case v2000u = "9P2000.u"
        case v2000L = "9P2000.L"
    }

    public let config: Config
    public private(set) var negotiatedVersion: NegotiatedVersion?

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
        // TODO: real socket negotiation. For now pick first candidate for determinism.
        let candidates = Self.versionCandidates(requested: config.requestedVersion)
        guard let chosen = candidates.first else { throw POSIXError(.EINVAL) }
        switch chosen {
        case NegotiatedVersion.v2000L.rawValue: negotiatedVersion = .v2000L
        case NegotiatedVersion.v2000u.rawValue: negotiatedVersion = .v2000u
        case NegotiatedVersion.v2000.rawValue: negotiatedVersion = .v2000
        default: throw POSIXError(.EPROTO)
        }
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

