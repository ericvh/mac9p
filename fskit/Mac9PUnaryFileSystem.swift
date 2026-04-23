import Foundation
import FSKit
import os.log
import Mac9PCore

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

        // NOTE: Foundation.URL does not reliably parse schemes that start with a digit ("9p").
        // Use the core parser which operates on the string form.
        let mountString = urlResource.url.absoluteString
        guard mountString.hasPrefix("9p://") else {
            Self.log.error("Invalid mount string: \(mountString, privacy: .public)")
            return replyHandler(nil, POSIXError(.EINVAL))
        }

        do {
            let cfg = try NinePClient.Config.from(mountString: mountString)
            let volume = try Mac9PVolume(config: cfg, mountURL: urlResource.url)
            self.resource = urlResource
            self.containerStatus = .ready
            return replyHandler(volume, nil)
        } catch {
            Self.log.error("loadResource failed: \(String(describing: error), privacy: .public)")
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

