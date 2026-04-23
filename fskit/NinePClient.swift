import Foundation

/// Minimal 9P client shim for an FSKit implementation.
///
/// This is intentionally a thin interface: in a real port you would either:
/// - Reuse a mature 9P client library (preferred), or
/// - Port the existing C 9P codec into a user-space library and wrap it from Swift.
final class NinePClient {
    struct Config: Sendable {
        var host: String
        var port: Int
        var user: String?
        var aname: String?
        var requestedVersion: String?

        static func from(url: URL) throws -> Config {
            guard let host = url.host, !host.isEmpty else { throw POSIXError(.EINVAL) }
            let port = url.port ?? 564

            var requestedVersion: String?
            if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                requestedVersion = comps.queryItems?.first(where: { $0.name == "vers" || $0.name == "version" })?.value
            }

            // userinfo is "user:pass" but we do not want password-in-URL; ignore password.
            let user = url.user

            return Config(
                host: host,
                port: port,
                user: user,
                aname: nil,
                requestedVersion: requestedVersion
            )
        }
    }

    enum NegotiatedVersion: String {
        case v2000 = "9P2000"
        case v2000u = "9P2000.u"
        case v2000L = "9P2000.L"
    }

    let config: Config
    private(set) var negotiatedVersion: NegotiatedVersion?

    init(config: Config) {
        self.config = config
    }

    func connectAndNegotiate() throws {
        // TODO: open TCP connection to host:port
        // TODO: send Tversion with msize + version string
        // TODO: parse Rversion and set negotiatedVersion
        //
        // For now, just implement deterministic negotiation selection so the
        // rest of the FSKit skeleton compiles.
        let requested = config.requestedVersion

        let candidates: [String] = {
            if let requested { return [requested, "9P2000.L", "9P2000.u", "9P2000"] }
            return ["9P2000.L", "9P2000.u", "9P2000"]
        }()

        guard let chosen = candidates.first else { throw POSIXError(.EINVAL) }
        switch chosen {
        case NegotiatedVersion.v2000L.rawValue: negotiatedVersion = .v2000L
        case NegotiatedVersion.v2000u.rawValue: negotiatedVersion = .v2000u
        case NegotiatedVersion.v2000.rawValue: negotiatedVersion = .v2000
        default:
            // If the server returns something unknown, you can either error or
            // treat it as baseline 9P2000 depending on your compatibility goals.
            throw POSIXError(.EPROTO)
        }
    }
}

