import Foundation
import FSKit
import os.log

final class Mac9PUnaryFileSystem: FSUnaryFileSystem, FSUnaryFileSystemOperations {
    private static let log = Logger(subsystem: "mac9p.fskit", category: "fs")

    private var resource: FSGenericURLResource?

    public func loadResource(resource: FSResource,
                             options: FSTaskOptions,
                             replyHandler: @escaping (FSVolume?, (any Error)?) -> Void) {
        guard let urlResource = resource as? FSGenericURLResource else {
            return replyHandler(nil, POSIXError(.EINVAL))
        }

        // FSKit may pass security-scoped URLs in options; for generic URLs this may be a no-op.
        // Keep the pattern consistent with Apple's sample.
        _ = urlResource.url.startAccessingSecurityScopedResource()

        guard urlResource.url.scheme?.lowercased() == "9p" else {
            Self.log.error("Invalid scheme: \(urlResource.url.scheme ?? "<nil>")")
            return replyHandler(nil, POSIXError(.EINVAL))
        }

        do {
            let cfg = try NinePClient.Config.from(url: urlResource.url)
            let client = NinePClient(config: cfg)
            try client.connectAndNegotiate()
            let volume = try Mac9PVolume(client: client, mountURL: urlResource.url)
            self.resource = urlResource
            self.containerStatus = .ready
            return replyHandler(volume, nil)
        } catch {
            Self.log.error("loadResource failed: \(String(describing: error))")
            return replyHandler(nil, error)
        }
    }

    public func unloadResource(resource: FSResource,
                               options: FSTaskOptions,
                               replyHandler: @escaping ((any Error)?) -> Void) {
        guard let urlResource = resource as? FSGenericURLResource else {
            return replyHandler(POSIXError(.EINVAL))
        }
        guard let loaded = self.resource, loaded.url == urlResource.url else {
            return replyHandler(POSIXError(.EINVAL))
        }
        loaded.url.stopAccessingSecurityScopedResource()
        self.resource = nil
        self.containerStatus = .offline
        return replyHandler(nil)
    }
}

